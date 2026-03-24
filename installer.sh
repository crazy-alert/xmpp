#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'          # исправлено: был пропущен слеш
RED='\033[0;31m'
NC='\033[0m'

# Параметры по умолчанию
REPO_URL="https://github.com/crazy-alert/xmpp.git"
DEFAULT_INSTALL_DIR="/opt/xmpp"

# Функции вывода (теперь все пишут в stderr)
info()  { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# Проверка наличия команды
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Команда '$1' не найдена. Установите её и повторите."
    fi
}

# Создание пользователя в ejabberd (использует глобальную COMPOSE_CMD)
create_ejabberd_user() {
    local container=$1
    local user_jid=$2
    local user_pass=$3

    local username=$(echo "$user_jid" | cut -d@ -f1)
    local host=$(echo "$user_jid" | cut -d@ -f2)

    info "Создание пользователя $user_jid в ejabberd..."

    # Ждём, пока контейнер запустится
    local max_wait=30
    local wait=0
    while [ $wait -lt $max_wait ]; do
        if $COMPOSE_CMD ps --filter "name=$container" --filter "status=running" | grep -q "$container"; then
            break
        fi
        sleep 2
        wait=$((wait+2))
    done

    if [ $wait -ge $max_wait ]; then
        warn "Контейнер $container не запустился за $max_wait секунд. Пропускаем создание пользователя."
        return
    fi

    # Ожидание готовности ejabberd (вместо sleep 10)
    info "Ожидание готовности ejabberd..."
    local retries=30
    local count=0
    while [ $count -lt $retries ]; do
        if $COMPOSE_CMD exec "$container" /home/ejabberd/bin/ejabberdctl status &>/dev/null; then
            info "ejabberd готов."
            break
        fi
        sleep 2
        count=$((count+1))
    done

    if [ $count -ge $retries ]; then
        warn "ejabberd не ответил за отведённое время. Пропускаем создание пользователя."
        return
    fi

    # Регистрируем пользователя
    if $COMPOSE_CMD exec "$container" /home/ejabberd/bin/ejabberdctl register "$username" "$host" "$user_pass" 2>/dev/null; then
        info "Пользователь $user_jid успешно создан."
    else
        # Проверяем, существует ли уже пользователь
        if $COMPOSE_CMD exec "$container" /home/ejabberd/bin/ejabberdctl check_account "$username" "$host" &>/dev/null; then
            info "Пользователь $user_jid уже существует."
        else
            warn "Не удалось создать пользователя $user_jid. Проверьте логи: $COMPOSE_CMD logs $container"
        fi
    fi
}

# Генерация токена (возвращает токен через stdout, все сообщения в stderr)
create_user_token() {
    local container=$1
    local user_jid=$2

    local username=$(echo "$user_jid" | cut -d@ -f1)
    local host=$(echo "$user_jid" | cut -d@ -f2)

    info "Генерация OAuth-токена для пользователя $user_jid..."

    # Небольшая пауза для завершения регистрации
    sleep 2

    local token
    token=$($COMPOSE_CMD exec "$container" /home/ejabberd/bin/ejabberdctl oauth_issue_token "$user_jid" 32140800 "ejabberd:admin" 2>/dev/null | tail -n1)

    # Проверяем, что токен не пуст и не содержит пробелов (упрощённая проверка)
    if [[ -n "$token" && ! "$token" =~ [[:space:]] ]]; then
        echo "$token"        # только токен в stdout
        info "OAuth-токен для пользователя сгенерирован."
    else
        warn "Не удалось получить OAuth-токен для $user_jid. Проверьте, что модуль OAuth включён в ejabberd."
        return 1
    fi
}

# Настройка UFW
configure_ufw() {
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        warn "Обнаружен активный UFW. Необходимо открыть порты."
        read -p "Разрешить автоматически добавить правила UFW? (y/N): " CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            info "Добавление правил UFW..."
            ufw allow 22/tcp comment 'ssh'
            ufw allow 80/tcp comment 'HTTP'
            ufw allow 443/tcp comment 'HTTPS'
            ufw allow 3478/tcp comment 'TURN'
            ufw allow 3478/udp comment 'STUN/TURN (UDP)'
            ufw allow 5349/tcp comment 'TURN over TLS (TCP)'
            ufw allow 5349/udp comment 'TURN over DTLS (UDP)'
            ufw allow 49152:65535/udp comment 'COTURN'
            ufw reload
            info "Правила UFW добавлены."
        else
            warn "Не забудьте вручную открыть порты."
        fi
    else
        info "UFW не установлен или не активен. Пропускаем настройку файрвола."
    fi
}

# Проверка статуса контейнеров (исправлено: используем docker ps)
check_containers() {
    local compose_cmd="$1"
    sleep 5
    # Проверяем, есть ли остановленные контейнеры
    if $compose_cmd ps --filter "status=exited" --format "{{.Names}}" | grep -q .; then
        warn "Некоторые контейнеры остановились. Проверьте логи: $compose_cmd logs"
    else
        info "Все контейнеры запущены успешно."
    fi
}

# Основная функция
main() {
    # Проверка прав root
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен выполняться от root (sudo)."
    fi

    info "Добро пожаловать в установщик XMPP-сервера!"

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

        apt install -y ca-certificates curl
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        source /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            DISTRO="ubuntu"
        elif [[ "$ID" == "debian" ]]; then
            DISTRO="debian"
        else
            error "Неподдерживаемый дистрибутив: $ID"
        fi

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$DISTRO ${VERSION_CODENAME} stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt update
        apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        info "Docker успешно установлен."
    else
        info "Docker уже установлен, пропускаем установку."
    fi

    # Проверяем, запущен ли демон Docker
    if ! systemctl is-active --quiet docker; then
        info "Запускаем Docker..."
        systemctl start docker
        systemctl enable docker
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
    export COMPOSE_CMD   # делаем глобальной для использования в функциях

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

    # Проверка DNS (основной домен – обязательная ошибка, поддомен – предупреждение)
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

    info "Проверка DNS для xmpp.$DOMAIN..."
    if ! dig +short "xmpp.$DOMAIN" A | grep -q .; then
        warn "Запись A для xmpp.$DOMAIN не найдена. Это может потребоваться для корректной работы клиентов."
        warn "Добавьте A-запись для xmpp.$DOMAIN, указывающую на $EXTERNAL_IP."
    else
        check_dns "xmpp.$DOMAIN"  # используем ту же функцию, но она вызовет error при несовпадении
    fi

    # 7. Создание .env из примера
    if [ ! -f "example.env" ]; then
        error "Файл example.env не найден в репозитории."
    fi
    cp example.env .env
    info "Файл .env создан."

    # Генератор пароля (встроен в скрипт)
    # Удалена неиспользуемая функция generate_password

    # Запрос пароля администратора с подтверждением
    while true; do
        read -s -p "Введите пароль администратора: " EJABBERD_ADMIN_PASSWORD
        echo
        read -s -p "Подтвердите пароль администратора: " EJABBERD_ADMIN_PASSWORD2
        echo
        if [ "$EJABBERD_ADMIN_PASSWORD" = "$EJABBERD_ADMIN_PASSWORD2" ]; then
            break
        else
            echo "Пароли не совпадают. Попробуйте ещё раз."
        fi
    done

    # Если пароль не введён (пустой), генерируем случайный
    if [ -z "$EJABBERD_ADMIN_PASSWORD" ]; then
        EJABBERD_ADMIN_PASSWORD=$(openssl rand -hex 8)
        info "Сгенерирован случайный пароль: $EJABBERD_ADMIN_PASSWORD"
    else
        info "Пароль принят."
    fi

    # 8. Замена переменных в .env (безопасная замена с разделителем '|')
    PUBLIC_IP="$EXTERNAL_IP"
    POSTGRES_PASSWORD=$(openssl rand -hex 8)
    TURN_PASSWORD=$(openssl rand -hex 32)
    TURN_SECRET=$(openssl rand -hex 32)
    EJABBERD_ADMIN_JID=admin@$DOMAIN

    # Используем sed с разделителем '|' и экранируем возможные спецсимволы в паролях (только /)
    # Поскольку пароли могут содержать '|', дополнительно экранируем их
    escape_sed() {
        echo "$1" | sed 's/|/\\|/g'
    }

    sed -i "s|^DOMAIN=.*|DOMAIN=$DOMAIN|" .env
    sed -i "s|^PUBLIC_IP=.*|PUBLIC_IP=$PUBLIC_IP|" .env
    sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(escape_sed "$POSTGRES_PASSWORD")|" .env
    sed -i "s|^TURN_PASSWORD=.*|TURN_PASSWORD=$(escape_sed "$TURN_PASSWORD")|" .env
    sed -i "s|^TURN_SECRET=.*|TURN_SECRET=$(escape_sed "$TURN_SECRET")|" .env
    sed -i "s|^EJABBERD_ADMIN_JID=.*|EJABBERD_ADMIN_JID=$EJABBERD_ADMIN_JID|" .env
    sed -i "s|^EJABBERD_ADMIN_PASSWORD=.*|EJABBERD_ADMIN_PASSWORD=$(escape_sed "$EJABBERD_ADMIN_PASSWORD")|" .env

    info "Переменные в .env обновлены."

    # Устанавливаем строгие права на .env
    chmod 600 .env
    info "Права доступа к .env установлены (600)."

    # 9. Настройка UFW (опционально)
    configure_ufw

    # 10. Запуск Docker-стека
    info "Запуск контейнеров с помощью $COMPOSE_CMD..."
    $COMPOSE_CMD up -d

    # 11. Проверка статуса контейнеров
    check_containers "$COMPOSE_CMD"

    # Создаём администратора
    create_ejabberd_user "ejabberd" "$EJABBERD_ADMIN_JID" "$EJABBERD_ADMIN_PASSWORD"

    # Генерируем токен (переменная получит только токен, т.к. info пишут в stderr)
    EJABBERD_TOKEN=$(create_user_token "ejabberd" "$EJABBERD_ADMIN_JID")

    # 12. Финальное сообщение
    echo -e "${GREEN}"
    cat << EOF
✅ Установка завершена!

Ваш XMPP-сервер доступен по адресу: https://$DOMAIN:443

Для подключения из клиента укажите:
    XMPP-адрес: $EJABBERD_ADMIN_JID
        пароль: $EJABBERD_ADMIN_PASSWORD
   имя сервера: $DOMAIN
          порт: 443

OAuth-токен для пользователя сгенерирован: $EJABBERD_TOKEN

Внимание:
 - для подключения в клиенте необходимо указывать порт 443 (по умолчанию используется 5222).
 - чтобы клиенты знали, что подключаться нужно на порт 443, а не на 5222, в DNS вашего домена необходимо добавить следующие SRV-записи:
         _xmpps-client._tcp.$DOMAIN. 86400 IN SRV 5  0 443 $DOMAIN.
         _xmpp-client._tcp.$DOMAIN.  86400 IN SRV 10 0 443 $DOMAIN.

Для просмотра логов:
  $COMPOSE_CMD logs -f

Управление регистрацией описано в README.

Вы можете самостоятельно внести изменения в .env файл (команда nano .env), после вызвать "docker compose down && docker compose up -d"
EOF
    echo -e "${NC}"
}

# Запуск
main