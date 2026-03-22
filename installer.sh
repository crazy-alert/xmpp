#!/bin/bash
set -e

# Цвета
GREEN='\033[0;32m'
YELLOW='033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Параметры по умолчанию
REPO_URL="https://github.com/crazy-alert/xmpp.git"
DEFAULT_INSTALL_DIR="/opt/xmpp"

# Функции вывода
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Проверка наличия команды
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Команда '$1' не найдена. Установите её и повторите."
    fi
}

# Настройка UFW
configure_ufw() {
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        warn "Обнаружен активный UFW. Необходимо открыть порты"
        read -p "Разрешить автоматически добавить правила UFW? (y/N): " CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        info "Добавление правил UFW..."
        ufw allow 22/tcp comment 'ssh'
        ufw allow 80/tcp comment ' HTTP'
        ufw allow 443/tcp comment ' HTTPS'
        ufw allow 3478/tcp comment 'TURN'
        ufw allow 3478/udp comment 'STUN/TURN (UDP)'
        ufw allow 5349/tcp comment 'TURN over TLS (TCP) '
        ufw allow 5349/udp comment 'TURN over DTLS (UDP)'
        ufw allow 49152:65535/udp comment 'COTURN'
        ufw reload
        info "Правила UFW добавлены."
        else
            warn "Не забудьте вручную открыть порты"
        fi
    else
        info "UFW не установлен или не активен. Пропускаем настройку файрвола."
    fi
}

# Проверка статуса контейнеров
check_containers() {
    local compose_cmd="$1"
    sleep 5
    if $compose_cmd ps | grep -q "Exit"; then
        warn "Некоторые контейнеры остановились. Проверьте логи: $compose_cmd logs"
    else
        info "Все контейнеры запущены успешно."
    fi
}

# Основная функция
main() {
    info "Добро пожаловать в установщик Matrix-сервера!"

    # 1. Директория установки
    read -p "Введите директорию для установки (Enter для использования $DEFAULT_INSTALL_DIR): " INSTALL_DIR
    INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
    info "Директория установки: $INSTALL_DIR"

    # 2. Обновление системы и установка базовых пакетов
    info "Обновление списка пакетов и установка git, curl, dnsutils..."
    apt update && apt install -y git curl dnsutils

    # 3. Установка Docker (если не установлен)
    if ! command -v docker &> /dev/null; then
        info "Docker не найден. Устанавливаем Docker..."

        # Устанавливаем зависимости для добавления репозитория
        apt install -y ca-certificates curl

        # Создаём директорию для ключей (если нет)
        install -m 0755 -d /etc/apt/keyrings

        # Скачиваем GPG-ключ Docker
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        # Определяем дистрибутив (ubuntu/debian)
        source /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            DISTRO="ubuntu"
        elif [[ "$ID" == "debian" ]]; then
            DISTRO="debian"
        else
            error "Неподдерживаемый дистрибутив: $ID"
        fi

        # Добавляем репозиторий Docker
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$DISTRO ${VERSION_CODENAME} stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Обновляем список пакетов и устанавливаем Docker
        apt update
        apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        info "Docker успешно установлен."
    else
        info "Docker уже установлен, пропускаем установку."
    fi

    # 4. Определяем команду Docker Compose
    info "Проверка Docker Compose..."
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        error "Docker Compose не найден. Установите docker-compose или docker compose."
    fi
    info "Используется команда: $COMPOSE_CMD"

    # 5. Подготовка директории и клонирование репозитория
    if [ -d "$INSTALL_DIR" ]; then
        warn "Директория $INSTALL_DIR уже существует."
        read -p "Продолжить и перезаписать файлы? (y/N): " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            error "Установка отменена."
        fi
        rm -rf "$INSTALL_DIR"
    fi
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    info "Клонирование репозитория..."
    git clone -v "$REPO_URL" .

    # 6. Запрос домена и проверка DNS
    read -p "Введите ваш домен (например, example.org): " DOMAIN
    [ -z "$DOMAIN" ] && error "Домен не может быть пустым."

    # Определяем внешний IP
    info "Определение внешнего IP..."
    EXTERNAL_IP=$(curl -s -4 ifconfig.me || curl -s -4 icanhazip.com || curl -s -4 ipinfo.io/ip)
    if [ -z "$EXTERNAL_IP" ]; then
        error "Не удалось определить внешний IP сервера."
    fi
    info "Внешний IP: $EXTERNAL_IP"

    # Проверка DNS
    check_dns() {
        local host="$1"
        local ip
        ip=$(dig +short "$host" A | head -n1)
        if [ -z "$ip" ]; then
            error "Не удалось получить IP для $host. Проверьте DNS-записи."
        fi
        if [ "$ip" != "$EXTERNAL_IP" ]; then
            error "IP домена $host ($ip) не совпадает с внешним IP сервера ($EXTERNAL_IP)."
        fi
        info "$host -> $ip (OK)"
    }
    info "Проверка DNS для основного домена..."
    check_dns "$DOMAIN"
    info "Проверка DNS для matrix.$DOMAIN..."
    info "Если завершится с ошибкой - вам нужно добавить A - запись для  *.$DOMAIN , подомены нужны будут и для работы админки и Element-web "
    check_dns "matrix.$DOMAIN"

    # 7. Создание .env из примера
    if [ ! -f "example.env" ]; then
        error "Файл example.env не найден в репозитории."
    fi
    cp example.env .env
    info "Файл .env создан."

    # Генератор пароля
    generate_password() {
        tr -dc 'a-zA-Z0-9!@#$%^&*()_+' < /dev/urandom 2>/dev/null | fold -w 32 | head -n1 || openssl rand -base64 32
    }

    # 8. Замена переменных в .env
    PUBLIC_IP="$EXTERNAL_IP"
    POSTGRES_PASSWORD=$(openssl rand -hex 8)
    TURN_PASSWORD=$(openssl rand -hex 32)
    TURN_SECRET=$(openssl rand -hex 32)
    EJABBERD_ADMIN_PASSWORD=$(openssl rand -hex 8)
    sed -i "s/^DOMAIN=.*/DOMAIN=$DOMAIN/" .env
    sed -i "s/^PUBLIC_IP=.*/PUBLIC_IP=$PUBLIC_IP/" .env
    sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env
    sed -i "s/^TURN_PASSWORD=.*/TURN_PASSWORD=$TURN_PASSWORD/" .env
    sed -i "s/^TURN_SECRET=.*/TURN_SECRET=$TURN_SECRET/" .env
    sed -i "s/^EJABBERD_ADMIN_PASSWORD=.*/EJABBERD_ADMIN_PASSWORD=$EJABBERD_ADMIN_PASSWORD/" .env
    info "Переменные в .env обновлены."



    # 10. Настройка UFW (опционально)
    configure_ufw

    # 11. Запуск Docker-стека
    info "Запуск контейнеров с помощью $COMPOSE_CMD..."
    $COMPOSE_CMD up -d

    # 12. Проверка статуса контейнеров
    check_containers "$COMPOSE_CMD"

    # 13. Финальное сообщение
    echo -e "${GREEN}"
    cat << EOF
✅ Установка завершена!

Ваш xmpp сервера доступен по адресам: https://$DOMAIN:443

пароль для admin@$DOMAIN   :    $EJABBERD_ADMIN_PASSWORD
Внимание:
 - для подключения в клиенте необходимо указывать порты 443 (по умолчанию там 5222)!
 - чтобы клиенты знали, что подключаться нужно на порт 443, а не на 5222. В DNS вашего домена необходимо добавить следующие SRV-записи:
         _xmpps-client._tcp.$DOMAIN. 86400 IN SRV 5  0 443 $DOMAIN.
         _xmpp-client._tcp.$DOMAIN.  86400 IN SRV 10 0 443 $DOMAIN.

Для просмотра логов:
  $COMPOSE_CMD logs -f

Управление регистрацией описано в README.

Вы можете самостоятельно внести изменения в .env файл (команда nano .env), после вызвать "docker compose down &&  docker compose  up -d"
EOF
    echo -e "${NC}"
}

# Запуск
main