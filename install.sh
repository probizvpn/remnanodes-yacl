#!/bin/bash

# ============================================
# АВТОМАТИЧЕСКАЯ УСТАНОВКА И НАСТРОЙКА
# Multi-Instance Remnanode с Policy-Based Routing
# 
# Версия: 2.0
# Дата: 2025-01-08
# ============================================

set -e

# ============================================
# ЦВЕТА ДЛЯ ВЫВОДА
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
ORANGE='\033[38;5;208m'
NC='\033[0m' # No Color / Reset

# ============================================
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# ============================================
REINSTALL_MODE=false
MAX_NODES=8  # Максимальное количество нод (1 основная + 7 дополнительных)

# Массивы для хранения данных
declare -a IPS=()
declare -a IFACES=()
declare -a PORTS=()
declare -a SECRET_KEYS=()

# Количество нод для установки
TOTAL_NODES=0
ADDITIONAL_NODES=0

# Системные характеристики
CPU_CORES=0
RAM_GB=0
RECOMMENDED_MAX_NODES=0

# ============================================
# ФУНКЦИИ ВЫВОДА
# ============================================
print_header() {
    echo -e "\n${CYAN}============================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}============================================${NC}\n"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================
# ПРОВЕРКА ROOT
# ============================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен быть запущен от root (sudo)"
        exit 1
    fi
}

# ============================================
# ПОЛУЧЕНИЕ СИСТЕМНЫХ ХАРАКТЕРИСТИК
# ============================================
get_system_specs() {
    print_header "Определение характеристик системы"
    
    # Получаем количество CPU
    CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "1")
    print_info "CPU ядер: ${CPU_CORES}"
    
    # Получаем количество RAM в GB
    local ram_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    if [[ -n "$ram_kb" ]]; then
        RAM_GB=$((ram_kb / 1024 / 1024))
        # Округляем до ближайшего целого
        if [[ $((ram_kb / 1024 % 1024)) -gt 512 ]]; then
            RAM_GB=$((RAM_GB + 1))
        fi
        # Минимум 1 GB
        [[ $RAM_GB -lt 1 ]] && RAM_GB=1
    else
        RAM_GB=1
    fi
    print_info "RAM: ${RAM_GB} GB"
    
    # Определяем рекомендуемое максимальное количество нод
    # Логика: 1 нода на каждые 0.5 CPU и 0.5 GB RAM, но не более MAX_NODES
    local max_by_cpu=$((CPU_CORES * 2))
    local max_by_ram=$((RAM_GB * 2))
    
    # Берём минимум из двух
    if [[ $max_by_cpu -lt $max_by_ram ]]; then
        RECOMMENDED_MAX_NODES=$max_by_cpu
    else
        RECOMMENDED_MAX_NODES=$max_by_ram
    fi
    
    # Ограничиваем максимумом
    [[ $RECOMMENDED_MAX_NODES -gt $MAX_NODES ]] && RECOMMENDED_MAX_NODES=$MAX_NODES
    [[ $RECOMMENDED_MAX_NODES -lt 2 ]] && RECOMMENDED_MAX_NODES=2
    
    print_info "Рекомендуемое макс. количество нод: ${RECOMMENDED_MAX_NODES}"
}

# ============================================
# ПОЛУЧЕНИЕ IP-АДРЕСОВ
# ============================================
get_internal_ips() {
    print_header "Определение внутренних IP-адресов"
    
    # Получаем IP из ip route (src адреса default маршрутов)
    mapfile -t IPS < <(ip route | grep "^default" | grep -oP 'src \K[\d.]+' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n)
    
    # Получаем интерфейсы
    mapfile -t IFACES < <(ip route | grep "^default" | grep -oP 'dev \K\S+')
    
    local ip_count=${#IPS[@]}
    
    # Проверка минимального количества IP
    if [[ $ip_count -lt 2 ]]; then
        print_error "Найден только ${ip_count} IP-адрес."
        print_error "Для работы скрипта требуется минимум 2 IP-адреса."
        print_error "Дополнительные ноды невозможны."
        exit 1
    fi
    
    print_success "Найдено ${ip_count} IP-адресов"
    echo ""
    
    # Выводим список найденных IP
    print_info "Список найденных IP-адресов:"
    for i in "${!IPS[@]}"; do
        if [[ $i -eq 0 ]]; then
            echo -e "  ${GREEN}$((i+1)).${NC} ${IPS[$i]} (${IFACES[$i]}) - ${CYAN}основная нода${NC}"
        else
            echo -e "  ${GREEN}$((i+1)).${NC} ${IPS[$i]} (${IFACES[$i]}) - ${YELLOW}дополнительная нода $i${NC}"
        fi
    done
    echo ""
    
    # Ограничиваем количество IP максимумом
    if [[ $ip_count -gt $MAX_NODES ]]; then
        print_warning "Найдено ${ip_count} IP, но максимальное поддерживаемое количество нод: ${MAX_NODES}"
        ip_count=$MAX_NODES
    fi
    
    # Максимальное количество дополнительных нод
    local max_additional=$((ip_count - 1))
    
    # Выводим рекомендации по нагрузке
    echo ""
    print_info "Рекомендации по нагрузке:"
    echo -e "  ${YELLOW}Характеристики сервера:${NC} ${CPU_CORES} CPU, ${RAM_GB} GB RAM"
    echo -e "  ${YELLOW}Рекомендуемое макс. нод:${NC} ${RECOMMENDED_MAX_NODES}"
    echo ""
    
    if [[ $ip_count -gt $RECOMMENDED_MAX_NODES ]]; then
        print_warning "Количество доступных IP (${ip_count}) превышает рекомендуемое количество нод (${RECOMMENDED_MAX_NODES})"
        print_warning "При превышении рекомендаций сервер может быть перегружен!"
    fi
    
    local potential_users=$((ip_count * 50))
    
    echo -e "  ${YELLOW}Если установить ${max_additional} дополнительных нод:${NC}"
    echo -e "    - 1 основная + ${max_additional} дополнительных = ${ip_count} нод"
    echo -e "    - При ~50 пользователей на ноду = ~${potential_users} пользователей"
    echo ""
    
    # Спрашиваем количество ДОПОЛНИТЕЛЬНЫХ нод с повторным вводом при ошибке
    while true; do
        echo -e "${YELLOW}Сколько дополнительных нод вы хотите установить?${NC}"
        echo -e "${YELLOW}(от 1 до ${max_additional}):${NC}"
        read -r input_additional
        
        # Валидация ввода
        if ! [[ "$input_additional" =~ ^[0-9]+$ ]]; then
            print_error "Введите число!"
            echo ""
            continue
        fi
        
        if [[ $input_additional -lt 1 ]]; then
            print_error "Минимальное количество дополнительных нод: 1"
            echo ""
            continue
        fi
        
        if [[ $input_additional -gt $max_additional ]]; then
            print_error "Недостаточно IP-адресов. Максимум дополнительных нод: ${max_additional}"
            echo ""
            continue
        fi
        
        if [[ $input_additional -gt $((MAX_NODES - 1)) ]]; then
            print_error "Максимальное количество дополнительных нод: $((MAX_NODES - 1))"
            echo ""
            continue
        fi
        
        # Ввод корректный, выходим из цикла
        break
    done
    
    ADDITIONAL_NODES=$input_additional
    TOTAL_NODES=$((ADDITIONAL_NODES + 1))
    
    print_success "Будет установлено дополнительных нод: ${ADDITIONAL_NODES}"
    echo ""
    
    # Выводим распределение IP по нодам
    print_info "Распределение IP по нодам:"
    echo -e "  ${CYAN}remnanode${NC}  -> ${IPS[0]} (${IFACES[0]})"
    for i in $(seq 1 $ADDITIONAL_NODES); do
        echo -e "  ${CYAN}remnanode${i}${NC} -> ${IPS[$i]} (${IFACES[$i]})"
    done
}

# ============================================
# ПРОВЕРКИ
# ============================================
check_prerequisites() {
    print_header "Проверка предварительных требований"
    
    # Проверка docker-compose.yml основной ноды
    if [[ ! -f "/opt/remnanode/docker-compose.yml" ]]; then
        print_error "Файл /opt/remnanode/docker-compose.yml не найден!"
        print_error "Похоже, основная нода remnanode не установлена."
        print_error "Сначала установите remnanode, затем запустите этот скрипт."
        exit 1
    fi
    print_success "Найден /opt/remnanode/docker-compose.yml"
    
    # Проверка docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker не установлен!"
        exit 1
    fi
    print_success "Docker установлен"
    
    # Проверка docker compose
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose не установлен!"
        exit 1
    fi
    print_success "Docker Compose установлен"
    
    # Проверка curl
    if ! command -v curl &> /dev/null; then
        print_error "curl не установлен!"
        exit 1
    fi
    print_success "curl установлен"
    
    # Проверка существования дополнительных нод (динамически)
    local nodes_exist=false
    local existing_nodes=""
    
    for i in $(seq 1 $((MAX_NODES - 1))); do
        if [[ -d "/opt/remnanode${i}" ]]; then
            nodes_exist=true
            if [[ -n "$existing_nodes" ]]; then
                existing_nodes="${existing_nodes}, /opt/remnanode${i}"
            else
                existing_nodes="/opt/remnanode${i}"
            fi
        fi
    done
    
    if [[ "$nodes_exist" == true ]]; then
        print_warning "Обнаружены существующие дополнительные ноды: ${existing_nodes}"
        echo ""
        echo -e "${YELLOW}Похоже, у вас уже установлены дополнительные ноды.${NC}"
        echo -e "${YELLOW}Переустановить? Все данные в этих папках будут удалены!${NC}"
        echo -e "${YELLOW}(y/n):${NC}"
        read -r answer
        if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
            print_info "Установка отменена пользователем."
            exit 0
        fi
        print_info "Продолжаем переустановку..."
        REINSTALL_MODE=true
    else
        print_success "Дополнительные ноды не установлены"
        REINSTALL_MODE=false
    fi
}

# ============================================
# ПОЛУЧЕНИЕ ПОРТА ИЗ DOCKER-COMPOSE
# ============================================
get_node_port() {
    local file=$1
    grep -oP 'NODE_PORT=\K\d+' "$file" 2>/dev/null || echo ""
}

# ============================================
# ИНТЕРАКТИВНЫЙ ВВОД
# ============================================
get_user_input() {
    print_header "Ввод параметров для нод"
    
    # Получаем порт из основной ноды
    local main_port=$(get_node_port "/opt/remnanode/docker-compose.yml")
    if [[ -z "$main_port" ]]; then
        print_warning "Не удалось определить NODE_PORT из основной ноды"
        main_port="2222"
    fi
    print_info "NODE_PORT основной ноды: ${main_port}"
    PORTS[0]=$main_port
    echo ""
    
    # Спрашиваем про порты с повторным вводом
    while true; do
        echo -e "${YELLOW}Использовать одинаковый порт (${main_port}) для всех дополнительных нод?${NC}"
        echo -e "${YELLOW}(y - одинаковый для всех / n - ввести для каждой отдельно):${NC}"
        read -r same_port
        
        if [[ "$same_port" == "y" || "$same_port" == "Y" || "$same_port" == "n" || "$same_port" == "N" ]]; then
            break
        else
            print_error "Введите 'y' или 'n'"
            echo ""
        fi
    done
    
    if [[ "$same_port" == "y" || "$same_port" == "Y" ]]; then
        # Одинаковый порт для всех
        for i in $(seq 1 $ADDITIONAL_NODES); do
            PORTS[$i]=$main_port
        done
        print_success "Порт ${main_port} будет использован для всех дополнительных нод"
    else
        # Разные порты
        for i in $(seq 1 $ADDITIONAL_NODES); do
            while true; do
                echo ""
                echo -e "${YELLOW}Введите NODE_PORT для remnanode${i}${NC} [по умолчанию: ${main_port}]:"
                read -r input_port
                
                # Если пустой ввод - используем порт по умолчанию
                if [[ -z "$input_port" ]]; then
                    PORTS[$i]=$main_port
                    break
                fi
                
                # Проверяем, что это число
                if [[ "$input_port" =~ ^[0-9]+$ ]]; then
                    # Проверяем диапазон портов
                    if [[ $input_port -ge 1 && $input_port -le 65535 ]]; then
                        PORTS[$i]=$input_port
                        break
                    else
                        print_error "Порт должен быть в диапазоне 1-65535"
                    fi
                else
                    print_error "Введите число!"
                fi
            done
            print_success "NODE_PORT для remnanode${i}: ${PORTS[$i]}"
        done
    fi
    
    echo ""
    
    # Запрашиваем SECRET_KEY для каждой дополнительной ноды
    for i in $(seq 1 $ADDITIONAL_NODES); do
        while true; do
            echo -e "${YELLOW}Вставьте SECRET_KEY из панели для remnanode${i}:${NC}"
            read -r secret_key
            
            if [[ -z "$secret_key" ]]; then
                print_error "SECRET_KEY не может быть пустым!"
                echo ""
            else
                SECRET_KEYS[$i]="$secret_key"
                print_success "SECRET_KEY для remnanode${i} получен"
                echo ""
                break
            fi
        done
    done
}

# ============================================
# МОДИФИКАЦИЯ ОСНОВНОЙ НОДЫ
# ============================================
modify_main_node() {
    print_header "Шаг 1: Модификация /opt/remnanode/docker-compose.yml"
    
    local file="/opt/remnanode/docker-compose.yml"
    local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Создаём бэкап
    cp "$file" "$backup"
    print_success "Создан бэкап: ${backup}"
    
    # Получаем NODE_PORT
    local node_port=${PORTS[0]}
    print_info "NODE_PORT: ${node_port}"
    
    # Получаем версию образа из файла
    local image_version=$(grep -oP 'image: remnawave/node:\K[^\s]+' "$file" || echo "latest")
    
    # Получаем SECRET_KEY из файла (убираем кавычки если есть)
    local secret_key=$(grep 'SECRET_KEY=' "$file" | sed 's/.*SECRET_KEY=//' | sed 's/^"//' | sed 's/"$//' | tr -d "'" | xargs)
    
    # Создаём новый docker-compose.yml
    cat > "$file" << EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:${image_version}
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    ports:
      - "${IPS[0]}:${node_port}:${node_port}"
      - "${IPS[0]}:443:443"
    environment:
      - NODE_PORT=${node_port}
      - SECRET_KEY="${secret_key}"
    volumes:
      - /var/log/remnanode:/var/log/remnanode
EOF
    
    print_success "Файл /opt/remnanode/docker-compose.yml обновлён"
    print_info "IP: ${IPS[0]}, PORT: ${node_port}"
}

# ============================================
# СОЗДАНИЕ ДОПОЛНИТЕЛЬНЫХ НОД
# ============================================
create_additional_nodes() {
    print_header "Шаг 2: Создание дополнительных нод"
    
    # Получаем версию образа из основной ноды
    local image_version=$(grep -oP 'image: remnawave/node:\K[^\s]+' "/opt/remnanode/docker-compose.yml" || echo "latest")
    
    for i in $(seq 1 $ADDITIONAL_NODES); do
        local node_dir="/opt/remnanode${i}"
        local node_name="remnanode${i}"
        local node_ip="${IPS[$i]}"
        local node_port="${PORTS[$i]}"
        local node_secret="${SECRET_KEYS[$i]}"
        
        print_info "Создание ${node_name}..."
        
        # Удаляем старую папку если режим переустановки
        if [[ -d "$node_dir" ]]; then
            if [[ "$REINSTALL_MODE" == true ]]; then
                print_info "Удаление старой ${node_dir}..."
                cd "$node_dir" && docker compose down 2>/dev/null || true
                rm -rf "$node_dir"
            fi
        fi
        
        # Создаём папку
        mkdir -p "$node_dir"
        
        # Создаём docker-compose.yml
        cat > "${node_dir}/docker-compose.yml" << EOF
services:
  remnanode:
    container_name: ${node_name}
    hostname: ${node_name}
    image: remnawave/node:${image_version}
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    ports:
      - "${node_ip}:${node_port}:${node_port}"
      - "${node_ip}:443:443"
    environment:
      - NODE_PORT=${node_port}
      - SECRET_KEY="${node_secret}"
    volumes:
      - /var/log/${node_name}:/var/log/remnanode
EOF
        
        print_success "Создан ${node_dir}/docker-compose.yml"
        print_info "IP: ${node_ip}, PORT: ${node_port}"
        echo ""
    done
}

# ============================================
# СКАЧИВАНИЕ И УСТАНОВКА СЛУЖЕБНЫХ СКРИПТОВ
# ============================================
install_pbr_scripts() {
    print_header "Шаг 3: Установка служебных скриптов PBR"
    
    local GITHUB_BASE="https://raw.githubusercontent.com/probizvpn/remnanodes-yacl/main"
    
    # 3.1 setup-pbr.sh
    print_info "Скачивание setup-pbr.sh..."
    if curl -fsSL "${GITHUB_BASE}/setup-pbr.sh" | tr -d '\r' > /opt/setup-pbr.sh; then
        chmod +x /opt/setup-pbr.sh
        print_success "Установлен /opt/setup-pbr.sh"
    else
        print_error "Не удалось скачать setup-pbr.sh"
        exit 1
    fi
    
    # 3.2 pbr-setup.service
    print_info "Скачивание pbr-setup.service..."
    if curl -fsSL "${GITHUB_BASE}/pbr-setup.service" | tr -d '\r' > /etc/systemd/system/pbr-setup.service; then
        print_success "Установлен /etc/systemd/system/pbr-setup.service"
    else
        print_error "Не удалось скачать pbr-setup.service"
        exit 1
    fi
    
    # 3.3 pbr-docker-watch.sh
    print_info "Скачивание pbr-docker-watch.sh..."
    if curl -fsSL "${GITHUB_BASE}/pbr-docker-watch.sh" | tr -d '\r' > /opt/pbr-docker-watch.sh; then
        chmod +x /opt/pbr-docker-watch.sh
        print_success "Установлен /opt/pbr-docker-watch.sh"
    else
        print_error "Не удалось скачать pbr-docker-watch.sh"
        exit 1
    fi
    
    # 3.4 pbr-docker-watch.service
    print_info "Скачивание pbr-docker-watch.service..."
    if curl -fsSL "${GITHUB_BASE}/pbr-docker-watch.service" | tr -d '\r' > /etc/systemd/system/pbr-docker-watch.service; then
        print_success "Установлен /etc/systemd/system/pbr-docker-watch.service"
    else
        print_error "Не удалось скачать pbr-docker-watch.service"
        exit 1
    fi
}

# ============================================
# НАСТРОЙКА SYSTEMD СЕРВИСОВ
# ============================================
setup_systemd_services() {
    print_header "Шаг 4: Настройка systemd сервисов"
    
    # Перезагрузка systemd
    print_info "Перезагрузка systemd daemon..."
    systemctl daemon-reload
    print_success "systemd daemon перезагружен"
    
    # Включение pbr-setup.service
    print_info "Включение pbr-setup.service..."
    systemctl enable pbr-setup.service
    print_success "pbr-setup.service включён"
    
    # Включение и запуск pbr-docker-watch.service
    print_info "Включение pbr-docker-watch.service..."
    systemctl enable pbr-docker-watch.service
    systemctl start pbr-docker-watch.service
    print_success "pbr-docker-watch.service включён и запущен"
}

# ============================================
# ЗАПУСК НОД
# ============================================
start_nodes() {
    print_header "Шаг 5: Запуск всех нод"
    
    # Останавливаем существующие контейнеры
    print_info "Останавливаем существующие контейнеры..."
    
    # Основная нода
    if [[ -f "/opt/remnanode/docker-compose.yml" ]]; then
        cd /opt/remnanode && docker compose down 2>/dev/null || true
    fi
    
    # Дополнительные ноды
    for i in $(seq 1 $((MAX_NODES - 1))); do
        if [[ -f "/opt/remnanode${i}/docker-compose.yml" ]]; then
            cd "/opt/remnanode${i}" && docker compose down 2>/dev/null || true
        fi
    done
    
    print_success "Контейнеры остановлены"
    
    # Запускаем основную ноду
    print_info "Запуск remnanode..."
    cd /opt/remnanode && docker compose up -d
    print_success "remnanode запущен"
    
    # Запускаем дополнительные ноды
    for i in $(seq 1 $ADDITIONAL_NODES); do
        print_info "Запуск remnanode${i}..."
        cd "/opt/remnanode${i}" && docker compose up -d
        print_success "remnanode${i} запущен"
    done
    
    # Ждём немного и запускаем PBR
    print_info "Ожидание запуска контейнеров (5 сек)..."
    sleep 5
    
    print_info "Запуск setup-pbr.sh..."
    /opt/setup-pbr.sh
    print_success "PBR настроен"
}

# ============================================
# ИТОГОВАЯ ИНФОРМАЦИЯ
# ============================================
print_summary() {
    print_header "УСТАНОВКА ЗАВЕРШЕНА!"
    
    echo -e "${GREEN}Модифицированная основная нода:${NC}"
    echo ""
    echo -e "  ${CYAN}remnanode${NC}"
    echo -e "    Папка: /opt/remnanode"
    echo -e "    IP: ${IPS[0]}"
    echo -e "    Порт: ${PORTS[0]}"
    echo ""
    
    echo -e "${GREEN}Установленные дополнительные ноды:${NC}"
    echo ""
    for i in $(seq 1 $ADDITIONAL_NODES); do
        echo -e "  ${CYAN}remnanode${i}${NC}"
        echo -e "    Папка: /opt/remnanode${i}"
        echo -e "    IP: ${IPS[$i]}"
        echo -e "    Порт: ${PORTS[$i]}"
        echo ""
    done
    
    echo -e "${GREEN}Установленные сервисы:${NC}"
    echo -e "  - pbr-setup.service (запуск PBR при загрузке)"
    echo -e "  - pbr-docker-watch.service (автообновление PBR при перезапуске контейнеров)"
    echo ""
    
    echo -e "${GREEN}Полезные команды:${NC}"
    echo -e "  Статус контейнеров:  ${YELLOW}docker ps${NC}"
    echo -e "  Логи основной ноды:  ${YELLOW}docker logs remnanode${NC}"
    for i in $(seq 1 $ADDITIONAL_NODES); do
        echo -e "  Логи ноды ${i}:         ${YELLOW}docker logs remnanode${i}${NC}"
    done
    echo -e "  Статус PBR watch:    ${YELLOW}systemctl status pbr-docker-watch${NC}"
    echo -e "  Перезапуск PBR:      ${YELLOW}/opt/setup-pbr.sh${NC}"
    echo ""
    
    echo -e "${GREEN}Информация о нагрузке:${NC}"
    echo -e "  Всего нод: ${TOTAL_NODES} (1 основная + ${ADDITIONAL_NODES} дополнительных)"
    echo -e "  Примерная ёмкость: ~$((TOTAL_NODES * 50)) пользователей (при 50 на ноду)"
    echo -e "  Характеристики сервера: ${CPU_CORES} CPU, ${RAM_GB} GB RAM"
}

# ============================================
# MAIN
# ============================================
main() {
    clear
    echo -e "${CYAN}"
    echo "  ██████╗ ███████╗███╗   ███╗███╗   ██╗ █████╗ ███╗   ██╗ ██████╗ ██████╗ ███████╗"
    echo "  ██╔══██╗██╔════╝████╗ ████║████╗  ██║██╔══██╗████╗  ██║██╔═══██╗██╔══██╗██╔════╝"
    echo "  ██████╔╝█████╗  ██╔████╔██║██╔██╗ ██║███████║██╔██╗ ██║██║   ██║██║  ██║█████╗  "
    echo "  ██╔══██╗██╔══╝  ██║╚██╔╝██║██║╚██╗██║██╔══██║██║╚██╗██║██║   ██║██║  ██║██╔══╝  "
    echo "  ██║  ██║███████╗██║ ╚═╝ ██║██║ ╚████║██║  ██║██║ ╚████║╚██████╔╝██████╔╝███████╗"
    echo "  ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝"
    echo -e "${NC}"
    echo -e "${YELLOW}  Multi-Instance Setup with Policy-Based Routing${NC}"
    echo -e "${YELLOW}  Версия 2.0${NC}"
    echo ""
    echo -e "${MAGENTA}  Specially for SoloBot Community${NC}"
    echo -e "${ORANGE}  GitHub SoloBot: https://github.com/Vladless/Solo_bot${NC}"
    echo ""
    
    check_root
    check_prerequisites
    get_system_specs
    get_internal_ips
    get_user_input
    modify_main_node
    create_additional_nodes
    install_pbr_scripts
    setup_systemd_services
    start_nodes
    print_summary
}

main "$@"