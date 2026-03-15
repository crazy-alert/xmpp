!#
read -p "Введите доменное имя: " DOMAIN &&
cp data/caddy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.crt data/ejabberd/ssl/${DOMAIN}.pem &&
cp data/caddy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.key data/ejabberd/ssl/${DOMAIN}.key &&
cp data/caddy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/chat.${DOMAIN}/chat.${DOMAIN}.crt data/ejabberd/ssl/chat.${DOMAIN}.pem &&
cp data/caddy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/chat.${DOMAIN}/chat.${DOMAIN}.key data/ejabberd/ssl/chat.${DOMAIN}.key &&
cp data/caddy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/conference.${DOMAIN}/conference.${DOMAIN}.crt data/ejabberd/ssl/conference.${DOMAIN}.pem &&
cp data/caddy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/conference.${DOMAIN}/conference.${DOMAIN}.key data/ejabberd/ssl/conference.${DOMAIN}.key &&
cp data/caddy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/pubsub.${DOMAIN}/pubsub.${DOMAIN}.crt data/ejabberd/ssl/pubsub.${DOMAIN}.pem &&
cp data/caddy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/pubsub.${DOMAIN}/pubsub.${DOMAIN}.key data/ejabberd/ssl/pubsub.${DOMAIN}.key &&
cp data/caddy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/upload.${DOMAIN}/upload.${DOMAIN}.crt data/ejabberd/ssl/upload.${DOMAIN}.pem &&
cp data/caddy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/upload.${DOMAIN}/upload.${DOMAIN}.key data/ejabberd/ssl/upload.${DOMAIN}.key &&
chown 9000:9000 data/ejabberd/ssl/* &&
chmod 640 data/ejabberd/ssl/*