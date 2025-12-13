#!/bin/bash

# ============================================
# АВТОМАТИЧЕСКАЯ УСТАНОВКА И НАСТРОЙКА
# Multi-Instance Remnanode с Policy-Based Routing
# ============================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функции вывода
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

# Проверка root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен быть запущен от root (sudo)"
        exit 1
    fi
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
}

# ============================================
# ПОЛУЧЕНИЕ IP-АДРЕСОВ
# ============================================

get_internal_ips() {
    print_header "Определение внутренних IP-адресов"
    
    # Получаем IP из ip route (src адреса default маршрутов)
    mapfile -t IPS < <(ip route | grep "^default" | grep -oP 'src \K[\d.]+' | sort -t. -k3,3n -k4,4n)
    
    # Также получаем интерфейсы
    mapfile -t IFACES < <(ip route | grep "^default" | grep -oP 'dev \K\S+' | head -n ${#IPS[@]})
    
    if [[ ${#IPS[@]} -lt 3 ]]; then
        print_error "Найдено только ${#IPS[@]} IP-адресов. Требуется минимум 3 для трёх нод."
        print_info "Найденные IP: ${IPS[*]}"
        exit 1
    fi
    
    print_info "Найдены следующие IP-адреса:"
    for i in "${!IPS[@]}"; do
        echo -e "  ${GREEN}$((i+1)).${NC} ${IPS[$i]} (${IFACES[$i]})"
    done
    echo ""
    
    # Назначаем IP для нод
    IP_REMNANODE="${IPS[0]}"
    IP_REMNANODE1="${IPS[1]}"
    IP_REMNANODE2="${IPS[2]}"
    
    IFACE_REMNANODE="${IFACES[0]}"
    IFACE_REMNANODE1="${IFACES[1]}"
    IFACE_REMNANODE2="${IFACES[2]}"
    
    print_info "Распределение IP по нодам:"
    echo -e "  ${CYAN}remnanode${NC}  -> ${IP_REMNANODE} (${IFACE_REMNANODE})"
    echo -e "  ${CYAN}remnanode1${NC} -> ${IP_REMNANODE1} (${IFACE_REMNANODE1})"
    echo -e "  ${CYAN}remnanode2${NC} -> ${IP_REMNANODE2} (${IFACE_REMNANODE2})"
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
    print_header "Ввод параметров для новых нод"
    
    # Получаем порт из основной ноды
    MAIN_NODE_PORT=$(get_node_port "/opt/remnanode/docker-compose.yml")
    if [[ -z "$MAIN_NODE_PORT" ]]; then
        print_warning "Не удалось определить NODE_PORT из основной ноды"
        MAIN_NODE_PORT="2222"
    fi
    print_info "NODE_PORT основной ноды: ${MAIN_NODE_PORT}"
    echo ""
    
    # Порт для remnanode1
    echo -e "${YELLOW}Введите NODE_PORT для remnanode1${NC} [по умолчанию: ${MAIN_NODE_PORT}]:"
    read -r input
    PORT_REMNANODE1="${input:-$MAIN_NODE_PORT}"
    print_success "NODE_PORT для remnanode1: ${PORT_REMNANODE1}"
    echo ""
    
    # Порт для remnanode2
    echo -e "${YELLOW}Введите NODE_PORT для remnanode2${NC} [по умолчанию: ${MAIN_NODE_PORT}]:"
    read -r input
    PORT_REMNANODE2="${input:-$MAIN_NODE_PORT}"
    print_success "NODE_PORT для remnanode2: ${PORT_REMNANODE2}"
    echo ""
    
    # SECRET_KEY для remnanode1
    echo -e "${YELLOW}Вставьте SECRET_KEY из панели для remnanode1:${NC}"
    read -r SECRET_KEY_REMNANODE1
    if [[ -z "$SECRET_KEY_REMNANODE1" ]]; then
        print_error "SECRET_KEY не может быть пустым!"
        exit 1
    fi
    print_success "SECRET_KEY для remnanode1 получен"
    echo ""
    
    # SECRET_KEY для remnanode2
    echo -e "${YELLOW}Вставьте SECRET_KEY из панели для remnanode2:${NC}"
    read -r SECRET_KEY_REMNANODE2
    if [[ -z "$SECRET_KEY_REMNANODE2" ]]; then
        print_error "SECRET_KEY не может быть пустым!"
        exit 1
    fi
    print_success "SECRET_KEY для remnanode2 получен"
    echo ""
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
    local node_port=$(get_node_port "$file")
    if [[ -z "$node_port" ]]; then
        print_error "Не удалось определить NODE_PORT!"
        exit 1
    fi
    print_info "NODE_PORT: ${node_port}"
    
    # Проверяем, есть ли уже секция ports
    if grep -q "^[[:space:]]*ports:" "$file"; then
        print_warning "Секция ports уже существует. Обновляем..."
        # Удаляем существующую секцию ports (до следующей секции или environment)
        sed -i '/^[[:space:]]*ports:/,/^[[:space:]]*[a-z]/{ /^[[:space:]]*ports:/d; /^[[:space:]]*-.*:/d; }' "$file"
    fi
    
    # Удаляем network_mode: host если есть
    if grep -q "network_mode:" "$file"; then
        sed -i '/network_mode:/d' "$file"
        print_success "Удалена строка network_mode: host"
    else
        print_info "network_mode: host не найден (возможно, уже удалён)"
    fi
    
    # Получаем версию образа из файла
    local image_version=$(grep -oP 'image: remnawave/node:\K[^\s]+' "$file" || echo "latest")
    
    # Получаем SECRET_KEY из файла
    local secret_key=$(grep -oP 'SECRET_KEY=\K[^\s]+' "$file" | tr -d '"' || echo "")
    
    # Создаём новый docker-compose.yml
    cat > "$file" << EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:${image_version}
    restart: always
    ports:
      - "${IP_REMNANODE}:${node_port}:${node_port}"
      - "${IP_REMNANODE}:443:443"
    environment:
      - NODE_PORT=${node_port}
      - SECRET_KEY=${secret_key}
    volumes:
      - /var/log/remnanode:/var/log/remnanode
EOF
    
    print_success "Файл /opt/remnanode/docker-compose.yml обновлён"
    print_info "IP: ${IP_REMNANODE}, PORT: ${node_port}"
}

# ============================================
# СОЗДАНИЕ ДОПОЛНИТЕЛЬНЫХ НОД
# ============================================

create_additional_nodes() {
    print_header "Шаг 2: Создание remnanode1 и remnanode2"
    
    # Получаем версию образа из основной ноды
    local image_version=$(grep -oP 'image: remnawave/node:\K[^\s]+' "/opt/remnanode/docker-compose.yml" || echo "latest")
    
    # === remnanode1 ===
    if [[ -d "/opt/remnanode1" ]]; then
        echo -e "${YELLOW}Папка /opt/remnanode1 уже существует. Перезаписать? (y/n)${NC}"
        read -r answer
        if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
            print_warning "Пропускаем создание remnanode1"
        else
            rm -rf /opt/remnanode1
            mkdir -p /opt/remnanode1
        fi
    else
        mkdir -p /opt/remnanode1
    fi
    
    if [[ -d "/opt/remnanode1" ]]; then
        cat > "/opt/remnanode1/docker-compose.yml" << EOF
services:
  remnanode:
    container_name: remnanode1
    hostname: remnanode1
    image: remnawave/node:${image_version}
    restart: always
    ports:
      - "${IP_REMNANODE1}:${PORT_REMNANODE1}:${PORT_REMNANODE1}"
      - "${IP_REMNANODE1}:443:443"
    environment:
      - NODE_PORT=${PORT_REMNANODE1}
      - SECRET_KEY=${SECRET_KEY_REMNANODE1}
    volumes:
      - /var/log/remnanode1:/var/log/remnanode
EOF
        print_success "Создан /opt/remnanode1/docker-compose.yml"
        print_info "IP: ${IP_REMNANODE1}, PORT: ${PORT_REMNANODE1}"
    fi
    
    # === remnanode2 ===
    if [[ -d "/opt/remnanode2" ]]; then
        echo -e "${YELLOW}Папка /opt/remnanode2 уже существует. Перезаписать? (y/n)${NC}"
        read -r answer
        if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
            print_warning "Пропускаем создание remnanode2"
        else
            rm -rf /opt/remnanode2
            mkdir -p /opt/remnanode2
        fi
    else
        mkdir -p /opt/remnanode2
    fi
    
    if [[ -d "/opt/remnanode2" ]]; then
        cat > "/opt/remnanode2/docker-compose.yml" << EOF
services:
  remnanode:
    container_name: remnanode2
    hostname: remnanode2
    image: remnawave/node:${image_version}
    restart: always
    ports:
      - "${IP_REMNANODE2}:${PORT_REMNANODE2}:${PORT_REMNANODE2}"
      - "${IP_REMNANODE2}:443:443"
    environment:
      - NODE_PORT=${PORT_REMNANODE2}
      - SECRET_KEY=${SECRET_KEY_REMNANODE2}
    volumes:
      - /var/log/remnanode2:/var/log/remnanode
EOF
        print_success "Создан /opt/remnanode2/docker-compose.yml"
        print_info "IP: ${IP_REMNANODE2}, PORT: ${PORT_REMNANODE2}"
    fi
}

# ============================================
# СКАЧИВАНИЕ И УСТАНОВКА СЛУЖЕБНЫХ СКРИПТОВ
# ============================================

install_pbr_scripts() {
    print_header "Шаг 3: Установка служебных скриптов PBR"
    
    local GITHUB_BASE="https://raw.githubusercontent.com/probizvpn/remnanodes-yacl/refs/heads/main"
    
    # 3.1 setup-pbr.sh
    print_info "Скачивание setup-pbr.sh..."
    if curl -fsSL "${GITHUB_BASE}/setup-pbr.sh" -o /opt/setup-pbr.sh; then
        chmod +x /opt/setup-pbr.sh
        print_success "Установлен /opt/setup-pbr.sh"
    else
        print_error "Не удалось скачать setup-pbr.sh"
        exit 1
    fi
    
    # 3.2 pbr-setup.service
    print_info "Скачивание pbr-setup.service..."
    if curl -fsSL "${GITHUB_BASE}/pbr-setup.service" -o /etc/systemd/system/pbr-setup.service; then
        print_success "Установлен /etc/systemd/system/pbr-setup.service"
    else
        print_error "Не удалось скачать pbr-setup.service"
        exit 1
    fi
    
    # 3.3 pbr-docker-watch.sh
    print_info "Скачивание pbr-docker-watch.sh..."
    if curl -fsSL "${GITHUB_BASE}/pbr-docker-watch.sh" -o /opt/pbr-docker-watch.sh; then
        chmod +x /opt/pbr-docker-watch.sh
        print_success "Установлен /opt/pbr-docker-watch.sh"
    else
        print_error "Не удалось скачать pbr-docker-watch.sh"
        exit 1
    fi
    
    # 3.4 pbr-docker-watch.service
    print_info "Скачивание pbr-docker-watch.service..."
    if curl -fsSL "${GITHUB_BASE}/pbr-docker-watch.service" -o /etc/systemd/system/pbr-docker-watch.service; then
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
    
    # Включение и запуск pbr-setup.service
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
    
    if [[ -f "/opt/remnanode/docker-compose.yml" ]]; then
        cd /opt/remnanode && docker compose down 2>/dev/null || true
    fi
    if [[ -f "/opt/remnanode1/docker-compose.yml" ]]; then
        cd /opt/remnanode1 && docker compose down 2>/dev/null || true
    fi
    if [[ -f "/opt/remnanode2/docker-compose.yml" ]]; then
        cd /opt/remnanode2 && docker compose down 2>/dev/null || true
    fi
    
    print_success "Контейнеры остановлены"
    
    # Запускаем ноды
    print_info "Запуск remnanode..."
    cd /opt/remnanode && docker compose up -d
    print_success "remnanode запущен"
    
    print_info "Запуск remnanode1..."
    cd /opt/remnanode1 && docker compose up -d
    print_success "remnanode1 запущен"
    
    print_info "Запуск remnanode2..."
    cd /opt/remnanode2 && docker compose up -d
    print_success "remnanode2 запущен"
    
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
    
    echo -e "${GREEN}Настроенные ноды:${NC}"
    echo ""
    echo -e "  ${CYAN}remnanode${NC}"
    echo -e "    Папка: /opt/remnanode"
    echo -e "    IP: ${IP_REMNANODE}"
    echo -e "    Порт: $(get_node_port /opt/remnanode/docker-compose.yml)"
    echo ""
    echo -e "  ${CYAN}remnanode1${NC}"
    echo -e "    Папка: /opt/remnanode1"
    echo -e "    IP: ${IP_REMNANODE1}"
    echo -e "    Порт: ${PORT_REMNANODE1}"
    echo ""
    echo -e "  ${CYAN}remnanode2${NC}"
    echo -e "    Папка: /opt/remnanode2"
    echo -e "    IP: ${IP_REMNANODE2}"
    echo -e "    Порт: ${PORT_REMNANODE2}"
    echo ""
    
    echo -e "${GREEN}Установленные сервисы:${NC}"
    echo -e "  - pbr-setup.service (запуск PBR при загрузке)"
    echo -e "  - pbr-docker-watch.service (автообновление PBR при перезапуске контейнеров)"
    echo ""
    
    echo -e "${GREEN}Полезные команды:${NC}"
    echo -e "  Статус контейнеров:  ${YELLOW}docker ps${NC}"
    echo -e "  Логи remnanode:      ${YELLOW}docker logs remnanode${NC}"
    echo -e "  Логи remnanode1:     ${YELLOW}docker logs remnanode1${NC}"
    echo -e "  Логи remnanode2:     ${YELLOW}docker logs remnanode2${NC}"
    echo -e "  Статус PBR watch:    ${YELLOW}systemctl status pbr-docker-watch${NC}"
    echo -e "  Перезапуск PBR:      ${YELLOW}/opt/setup-pbr.sh${NC}"
    echo ""
    
    echo -e "${GREEN}Проверка работы нод:${NC}"
    echo -e "  С внешнего сервера выполните:"
    echo -e "  ${YELLOW}nc -zv <ВНЕШНИЙ_IP_1> $(get_node_port /opt/remnanode/docker-compose.yml)${NC}"
    echo -e "  ${YELLOW}nc -zv <ВНЕШНИЙ_IP_2> ${PORT_REMNANODE1}${NC}"
    echo -e "  ${YELLOW}nc -zv <ВНЕШНИЙ_IP_3> ${PORT_REMNANODE2}${NC}"
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
    echo ""
    
    check_root
    check_prerequisites
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