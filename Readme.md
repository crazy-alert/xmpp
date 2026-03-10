ejabberd (XMPP-сервер), PostgreSQL (база данных), Caddy с плагином caddy-l4 (для мультиплексирования XMPP и HTTPS на порту 443) и PHP 8.4 (через PHP-FPM) для возможного запуска веб-приложений (например, сайта или админ-панели).



 - Caddy с layer4 анализирует входящие TLS-соединения на порту 443 по протоколу ALPN.
 - Если ALPN = xmpp-client, трафик направляется в ejabberd на порт 5223 (Direct TLS для клиентов).
 - Если ALPN = xmpp-server, трафик направляется в ejabberd на порт 5270 (Direct TLS для федерации).
 - Если ALPN = http/1.1 или h2, трафик обрабатывается как обычный HTTPS и проксируется на PHP-FPM или на админку ejabberd.
 - ejabberd настроен на приём защищённых соединений (Direct TLS) на портах 5223 и 5270, а также HTTP на порту 5280.
 - PHP-FPM обрабатывает PHP-скрипты, а Caddy выступает как веб-сервер.

Структура файлов:

```
xmpp/
├── docker-compose.yml
├── caddy/
│   ├── Dockerfile
│   └── Caddyfile
├── ejabberd/
│   └── ejabberd.yml
├── php/
│   └── (ваши PHP-файлы, например index.php)
└── data/
    ├── postgres/
    ├── caddy/
    │   ├── data/
    │   └── config/
    └── ejabberd/
        ├── ssl/
        └── backup/
        ```


Для вашей конфигурации с Caddy и Direct TLS (порт 443) нужно добавить две SRV-записи:
 - Для клиентов (c2s):
```
Service: _xmpps-client
Protocol: _tcp
Port: 443
Target: xmpp.example.com
Priority: 5
Weight: 0
```
 - Для федерации (s2s, связь с другими серверами):
```
 Service: _xmpps-server
Protocol: _tcp
Port: 443
Target: xmpp.example.com
Priority: 5
Weight: 0
```
Обратите внимание: имена сервисов — `_xmpps-client` и `_xmpps-server` (с буквой `s` на конце). Это важно, так как именно они указывают на использование `Direct TLS (XEP-0368)` 

#### Как проверить, что всё добавилось правильно?
Windows:
```cmd
nslookup -type=srv _xmpps-client._tcp.xmpp.example.com
```
На Linux/macOS:
```bash
dig _xmpps-client._tcp.xmpp.example.com SRV
```
В ответ вы должны увидеть что-то похожее на:
`_xmpps-client._tcp.xmpp.example.com. 3600 IN SRV 5 0 443 xmpp.example.com.`