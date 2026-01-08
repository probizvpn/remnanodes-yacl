#!/bin/bash

# ============================================
# АВТОМАТИЧЕСКАЯ настройка Policy-Based Routing
# для нескольких Remnanode на одной ВМ
# 
# Скрипт автоматически определяет:
# - Дополнительные интерфейсы (eth1, eth2, ...)
# - Docker bridge сети и их подсети
# - Связь контейнер -> интерфейс по IP биндингу
# ============================================

# Убираем set -e чтобы скрипт не падал при ошибках
# set -e

echo "============================================"
echo "  Автоматическая настройка PBR для Remnanode"
echo "============================================"
echo ""

# Базовая метка и таблица (будут увеличиваться для каждого интерфейса)
BASE_MARK=101
BASE_TABLE=101
BASE_PRIORITY=100

# Получаем список всех eth интерфейсов кроме eth0
get_extra_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -E '^eth[1-9]' | sort
}

# Получаем IP адрес интерфейса
get_interface_ip() {
    local iface=$1
    ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1
}

# Получаем подсеть интерфейса
get_interface_subnet() {
    local iface=$1
    ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d./]+' | head -1
}

# Получаем шлюз для интерфейса (обычно .1 в подсети)
get_interface_gateway() {
    local iface=$1
    local ip=$(get_interface_ip "$iface")
    echo "${ip%.*}.1"
}

# Находим контейнер, который слушает на данном IP
get_container_by_ip() {
    local bind_ip=$1
    local found_container=""
    
    for container in $(docker ps --format '{{.Names}}' 2>/dev/null); do
        if docker port "$container" 2>/dev/null | grep -q "$bind_ip:"; then
            found_container="$container"
            break
        fi
    done
    
    echo "$found_container"
}

# Получаем Docker сеть контейнера
get_container_network() {
    local container=$1
    docker inspect "$container" --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}{{end}}' 2>/dev/null
}

# Получаем bridge интерфейс по имени Docker сети
get_bridge_by_network() {
    local net_name=$1
    local net_id=$(docker network inspect "$net_name" --format '{{.Id}}' 2>/dev/null | cut -c1-12)
    if [ -n "$net_id" ]; then
        echo "br-${net_id}"
    fi
}

# Получаем подсеть Docker сети
get_docker_network_subnet() {
    local net_name=$1
    docker network inspect "$net_name" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null
}

# ============================================
# ОСНОВНАЯ ЛОГИКА
# ============================================

echo "=== Поиск дополнительных интерфейсов ==="
EXTRA_IFACES=$(get_extra_interfaces)

if [ -z "$EXTRA_IFACES" ]; then
    echo "Дополнительные интерфейсы (eth1, eth2, ...) не найдены."
    echo "PBR не требуется."
    exit 0
fi

echo "Найдены интерфейсы: $EXTRA_IFACES"
echo ""

# Массивы для хранения конфигурации
declare -A CONFIG

INDEX=0
for IFACE in $EXTRA_IFACES; do
    echo "--- Обработка $IFACE ---"
    
    IFACE_IP=$(get_interface_ip "$IFACE")
    if [ -z "$IFACE_IP" ]; then
        echo "  ПРОПУСК: нет IP адреса"
        echo ""
        continue
    fi
    echo "  IP: $IFACE_IP"
    
    GATEWAY=$(get_interface_gateway "$IFACE")
    echo "  Gateway: $GATEWAY"
    
    # Находим контейнер
    CONTAINER=$(get_container_by_ip "$IFACE_IP")
    if [ -z "$CONTAINER" ]; then
        echo "  ПРОПУСК: контейнер не найден для IP $IFACE_IP"
        echo ""
        continue
    fi
    echo "  Контейнер: $CONTAINER"
    
    # Находим Docker сеть
    DOCKER_NET=$(get_container_network "$CONTAINER")
    if [ -z "$DOCKER_NET" ]; then
        echo "  ПРОПУСК: Docker сеть не найдена"
        echo ""
        continue
    fi
    echo "  Docker сеть: $DOCKER_NET"
    
    # Находим bridge
    BRIDGE=$(get_bridge_by_network "$DOCKER_NET")
    if [ -z "$BRIDGE" ]; then
        echo "  ПРОПУСК: bridge не найден"
        echo ""
        continue
    fi
    echo "  Bridge: $BRIDGE"
    
    # Находим подсеть Docker
    DOCKER_SUBNET=$(get_docker_network_subnet "$DOCKER_NET")
    if [ -z "$DOCKER_SUBNET" ]; then
        echo "  ПРОПУСК: подсеть Docker не найдена"
        echo ""
        continue
    fi
    echo "  Docker подсеть: $DOCKER_SUBNET"
    
    # Вычисляем mark и table
    MARK=$((BASE_MARK + INDEX))
    TABLE=$((BASE_TABLE + INDEX))
    PRIORITY=$((BASE_PRIORITY + INDEX))
    
    echo "  Mark: $MARK, Table: $TABLE"
    
    # Сохраняем конфигурацию
    CONFIG["${INDEX}_IFACE"]="$IFACE"
    CONFIG["${INDEX}_IP"]="$IFACE_IP"
    CONFIG["${INDEX}_GATEWAY"]="$GATEWAY"
    CONFIG["${INDEX}_MARK"]="$MARK"
    CONFIG["${INDEX}_TABLE"]="$TABLE"
    CONFIG["${INDEX}_PRIORITY"]="$PRIORITY"
    CONFIG["${INDEX}_BRIDGE"]="$BRIDGE"
    CONFIG["${INDEX}_DOCKER_SUBNET"]="$DOCKER_SUBNET"
    CONFIG["${INDEX}_CONTAINER"]="$CONTAINER"
    
    INDEX=$((INDEX + 1))
    echo ""
done

if [ $INDEX -eq 0 ]; then
    echo "Нет интерфейсов с активными контейнерами для настройки PBR."
    echo "Это нормально, если вы установили меньше дополнительных нод, чем доступно IP-адресов."
    exit 0
fi

echo "============================================"
echo "  Применение настроек для $INDEX интерфейсов"
echo "============================================"
echo ""

# ============================================
# 1. IP RULES
# ============================================
echo "=== Настройка ip rules ==="

for i in $(seq 0 $((INDEX - 1))); do
    MARK=${CONFIG["${i}_MARK"]}
    TABLE=${CONFIG["${i}_TABLE"]}
    PRIORITY=${CONFIG["${i}_PRIORITY"]}
    
    if ! ip rule show | grep -q "fwmark 0x$(printf '%x' $MARK) "; then
        ip rule add fwmark $MARK table $TABLE priority $PRIORITY 2>/dev/null || true
        echo "Добавлено: fwmark $MARK -> table $TABLE (priority $PRIORITY)"
    else
        echo "Уже существует: fwmark $MARK -> table $TABLE"
    fi
done

echo ""

# ============================================
# 2. МАРШРУТЫ В ТАБЛИЦАХ
# ============================================
echo "=== Настройка маршрутов ==="

for i in $(seq 0 $((INDEX - 1))); do
    TABLE=${CONFIG["${i}_TABLE"]}
    BRIDGE=${CONFIG["${i}_BRIDGE"]}
    DOCKER_SUBNET=${CONFIG["${i}_DOCKER_SUBNET"]}
    IFACE=${CONFIG["${i}_IFACE"]}
    GATEWAY=${CONFIG["${i}_GATEWAY"]}
    
    # Удаляем старый маршрут если есть (bridge мог измениться)
    EXISTING=$(ip route show table $TABLE 2>/dev/null | grep "$DOCKER_SUBNET" | awk '{print $3}')
    if [ -n "$EXISTING" ] && [ "$EXISTING" != "$BRIDGE" ]; then
        ip route del $DOCKER_SUBNET table $TABLE 2>/dev/null || true
        echo "Удалён старый маршрут: $DOCKER_SUBNET dev $EXISTING table $TABLE"
    fi
    
    # Добавляем маршрут для Docker подсети
    if ! ip route show table $TABLE 2>/dev/null | grep -q "$DOCKER_SUBNET.*dev $BRIDGE"; then
        ip route add $DOCKER_SUBNET dev $BRIDGE table $TABLE 2>/dev/null || true
        echo "Добавлено: $DOCKER_SUBNET dev $BRIDGE table $TABLE"
    else
        echo "Уже существует: $DOCKER_SUBNET dev $BRIDGE table $TABLE"
    fi
    
    # Добавляем default маршрут через шлюз
    if ! ip route show table $TABLE 2>/dev/null | grep -q "default via $GATEWAY"; then
        ip route add default via $GATEWAY dev $IFACE table $TABLE 2>/dev/null || true
        echo "Добавлено: default via $GATEWAY dev $IFACE table $TABLE"
    else
        echo "Уже существует: default via $GATEWAY dev $IFACE table $TABLE"
    fi
done

echo ""

# ============================================
# 3. IPTABLES MANGLE
# ============================================
echo "=== Настройка iptables ==="

# Общие правила CONNMARK
iptables -t mangle -C PREROUTING -j CONNMARK --restore-mark 2>/dev/null || {
    iptables -t mangle -A PREROUTING -j CONNMARK --restore-mark
    echo "Добавлено: CONNMARK --restore-mark"
}

iptables -t mangle -C POSTROUTING -j CONNMARK --save-mark 2>/dev/null || {
    iptables -t mangle -A POSTROUTING -j CONNMARK --save-mark
    echo "Добавлено: CONNMARK --save-mark"
}

# Правила для каждого интерфейса
for i in $(seq 0 $((INDEX - 1))); do
    IFACE=${CONFIG["${i}_IFACE"]}
    MARK=${CONFIG["${i}_MARK"]}
    
    # Маркировка новых соединений
    iptables -t mangle -C PREROUTING -i $IFACE -m conntrack --ctstate NEW -j MARK --set-mark $MARK 2>/dev/null || {
        iptables -t mangle -A PREROUTING -i $IFACE -m conntrack --ctstate NEW -j MARK --set-mark $MARK
        echo "Добавлено: -i $IFACE NEW -> MARK $MARK"
    }
    
    # Сохранение метки
    iptables -t mangle -C PREROUTING -i $IFACE -m conntrack --ctstate NEW -j CONNMARK --save-mark 2>/dev/null || {
        iptables -t mangle -A PREROUTING -i $IFACE -m conntrack --ctstate NEW -j CONNMARK --save-mark
        echo "Добавлено: -i $IFACE NEW -> CONNMARK --save-mark"
    }
done

echo ""

# ============================================
# 4. SYSCTL (rp_filter)
# ============================================
echo "=== Настройка sysctl ==="

sysctl -w net.ipv4.conf.all.rp_filter=0 > /dev/null 2>&1 || true
echo "net.ipv4.conf.all.rp_filter=0"

for i in $(seq 0 $((INDEX - 1))); do
    IFACE=${CONFIG["${i}_IFACE"]}
    sysctl -w net.ipv4.conf.${IFACE}.rp_filter=0 > /dev/null 2>&1 || true
    echo "net.ipv4.conf.${IFACE}.rp_filter=0"
done

echo ""

# ============================================
# 5. МАРКИРОВКА ИСХОДЯЩЕГО ТРАФИКА ИЗ КОНТЕЙНЕРОВ
# ============================================
echo "=== Настройка исходящего трафика ==="

for i in $(seq 0 $((INDEX - 1))); do
    IFACE=${CONFIG["${i}_IFACE"]}
    MARK=${CONFIG["${i}_MARK"]}
    IP=${CONFIG["${i}_IP"]}
    DOCKER_SUBNET=${CONFIG["${i}_DOCKER_SUBNET"]}
    
    # Маркировка исходящего трафика из Docker сети
    iptables -t mangle -C PREROUTING -s $DOCKER_SUBNET -j MARK --set-mark $MARK 2>/dev/null || {
        iptables -t mangle -A PREROUTING -s $DOCKER_SUBNET -j MARK --set-mark $MARK
        echo "Добавлено: -s $DOCKER_SUBNET -> MARK $MARK"
    }
    
    # SNAT для исходящего трафика
    iptables -t nat -C POSTROUTING -s $DOCKER_SUBNET -o $IFACE -j SNAT --to-source $IP 2>/dev/null || {
        iptables -t nat -A POSTROUTING -s $DOCKER_SUBNET -o $IFACE -j SNAT --to-source $IP
        echo "Добавлено: SNAT $DOCKER_SUBNET -> $IP (via $IFACE)"
    }
done

echo ""

# ============================================
# ИТОГ
# ============================================
echo "============================================"
echo "  Настройка завершена!"
echo "============================================"
echo ""
echo "Настроенные интерфейсы:"
for i in $(seq 0 $((INDEX - 1))); do
    IFACE=${CONFIG["${i}_IFACE"]}
    IP=${CONFIG["${i}_IP"]}
    CONTAINER=${CONFIG["${i}_CONTAINER"]}
    MARK=${CONFIG["${i}_MARK"]}
    TABLE=${CONFIG["${i}_TABLE"]}
    BRIDGE=${CONFIG["${i}_BRIDGE"]}
    DOCKER_SUBNET=${CONFIG["${i}_DOCKER_SUBNET"]}
    
    echo "  $IFACE ($IP):"
    echo "    Контейнер: $CONTAINER"
    echo "    Mark/Table: $MARK/$TABLE"
    echo "    Bridge: $BRIDGE"
    echo "    Docker subnet: $DOCKER_SUBNET"
done

echo ""
echo "Для проверки выполните с внешнего сервера:"
for i in $(seq 0 $((INDEX - 1))); do
    IP=${CONFIG["${i}_IP"]}
    CONTAINER=${CONFIG["${i}_CONTAINER"]}
    echo "  nc -zv ВНЕШНИЙ_IP_ДЛЯ_${CONTAINER} <порт ноды>"
done