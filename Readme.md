# Ejabberd (XMPP-сервер), PostgreSQL, Caddy с плагином caddy-l4 (для мультиплексирования XMPP и HTTPS на порту 443) и PHP 8.4 (через PHP-FPM) для возможного запуска веб-приложений.
**Особенности установки:** 
 - весь трафик идёт через порт 443.
 - В папке /php можно положить файлы сайта.
 - При открытии доменного имени в браузере откроется сайт, при доступе из клиента xmpp запросы будут проксироваться к ejabberd.

___________________________
Воспользуйтесь автоустановщиком, либо следуйте пошаговой инструкции

## Вариант 1 - Автоустановщик:
(просто скопируй и вставь в терминал правой кнопкой мыши)
```bash
bash <(curl -sSL https://raw.githubusercontent.com/crazy-alert/XMPP/refs/heads/main/installer.sh?timestamp=123)
```
________________________

## Вариант 2 - Пошаговая установка

#### Установка зависимостей:

(просто скопируй и вставь в терминал правой кнопкой мыши)
```bash
apt update
apt install -y ca-certificates curl
# Добавление официального ключа и репозитория Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
# Повторное обновление и установка пакетов
apt update
apt install -y git openssl nano docker-ce docker-ce-cli containerd.io docker-compose-plugin
# Добавление текущего пользователя в группу docker (чтобы не использовать sudo)
usermod -aG docker $USER
```
#### Перейди в папку для установки (например /opt/xmpp) и скопируй туда данный репозиторий:
```bash
git clone https://github.com/crazy-alert/xmpp.git .
```
Убедитесь, что папка назначения пуста, или используйте git clone ... без точки, а затем перейдите в созданную папку
#### Создай файл конфигурации из примера и открой его:
```bash
cp example.env .env &&
nano .env
```
В этом файле нужно зменить:
 - DOMAIN=changeme.com - changeme.com заменить на свой домен
 - PUBLIC_IP=auto - auto заменить на ip сервера
 - EJABBERD_ADMIN_PASSWORD=changeme - changeme установить хороший пароль
 - POSTGRES_PASSWORD=changeme - вместо changeme установить хороший пароль
 - TURN_PASSWORD=changeme - вместо changeme установить хороший пароль
 - TURN_SECRET=changeme - вместо changeme установить хороший пароль

`Ctrl+O`, `Enter` - сохранить, `Ctrl+X`, `Enter` - выйти

#### Запуск:
```bash
docker-compose up -d
```
Или, в зависимости от установки:
```bash
docker compose up -d
```
# Внимание: Ваш xmpp сервер для клиентов доступен по адресу: https://xxxx.xx:443

Для подключения в клиенте необходимо указывать порты 443 (по умолчанию там 5222)!
чтобы клиенты знали, что подключаться нужно на порт 443, а не на 5222. В DNS вашего домена необходимо добавить следующие SRV-записи:
 - `_xmpps-client._tcp.вашдомен.com. 86400 IN SRV 5 0 443 вашдомен.com`.
 - `_xmpps-server._tcp.вашдомен.com. 86400 IN SRV 5 0 443 вашдомен.com`.

Дополнительная запись (рекомендуемая для обратной совместимости):
 - `_xmpp-client._tcp.вашдомен.com. 86400 IN SRV 10 0 443 вашдомен.com`.

Обратите внимание: имена сервисов — `_xmpps-client` и `_xmpps-server` (с буквой `s` на конце). Это важно, так как именно они указывают на использование `Direct TLS (XEP-0368)`
#### Как проверить, что всё добавилось правильно?
# На Linux/macOS
```bash
dig _xmpps-client._tcp.вашдомен.com SRV
```
# На Windows
```cmd
nslookup -type=srv _xmpps-client._tcp.вашдомен.com
```
В ответе вы должны увидеть, что запись указывает на ваш домен и порт 443, что-то похожее на:
`_xmpps-client._tcp.xmpp.example.com. 3600 IN SRV 5 0 443 xmpp.example.com.`

Это не обязательно. Для конфиденциальности лучше ручками каждый раз писать порт 443) 

# Возможно потребуется настроить фаервол и открыть Порты:
```bash
ufw allow 22/tcp comment 'ssh'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment ' HTTPS'
ufw allow 3478/tcp comment 'TURN'
ufw allow 3478/udp comment 'STUN/TURN (UDP)'
ufw allow 5349/tcp comment 'TURN over TLS (TCP)'
ufw allow 5349/udp comment 'TURN over DTLS (UDP)'
ufw allow 49152:65535/udp comment 'COTURN'
ufw reload
```
# Более тонкая настройка Ejabberd описана в [Redme.ejabberd.md](https://github.com/crazy-alert/xmpp/blob/main/Readme.ejabberd.md) 



