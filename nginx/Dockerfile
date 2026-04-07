# 1. Même base Alpine
FROM alpine:3.18

# 2. On installe :
#    - nginx : le serveur web / reverse proxy
#    - openssl : pour générer le certificat SSL (HTTPS)
RUN apk update && apk add --no-cache \
    nginx \
    openssl

# 3. On crée le dossier pour les certificats SSL
RUN mkdir -p /etc/nginx/ssl

# 4. On génère un certificat SSL auto-signé
#    -x509 : type de certificat
#    -days 365 : valide 1 an
#    -newkey rsa:2048 : clé de 2048 bits
#    -nodes : pas de mot de passe sur la clé
#    -subj : les infos du certificat (pays, ville, nom...)
RUN openssl req -x509 -days 365 -newkey rsa:2048 -nodes \
    -keyout /etc/nginx/ssl/server.key \
    -out /etc/nginx/ssl/server.crt \
    -subj "/C=FR/ST=Paris/L=Paris/O=42/CN=spike.42.fr"

# 5. On copie la config NGINX
COPY conf/nginx.conf /etc/nginx/http.d/default.conf

# 6. On expose le port 443 et 80 pour le HTTP et HTTPS
EXPOSE 80
EXPOSE 443

# 7. Lance NGINX au premier plan
#    "daemon off" = ne pas se lancer en arrière-plan (Docker a besoin du processus au premier plan)
CMD ["nginx", "-g", "daemon off;"]