#!/bin/sh
# BuckeyeStudio
# Install / Setup Script for our network monitor

# Declair all variables
RPI_HOST_NAME = rpi # name of the RPI
RPI_DOMAIN_NAME = rpi.local # domain of the RPI

PI_USER_NAME = "pi"
PI_USER_PASSWORD = "raspberry"

ROOT_PUID = 1000 # root user policy id
ROOT_PGID = 1000 # root groups policy id
MY_TIME_ZONE = "America/New_York" # our local timezone

NPM_DATABASE_NAME = "npm" # nginx proxy manager's mysql database name
NPM_USERNAME = "user1" # nginx proxy manager's mysql username
NPM_USER_PASSWORD = "change#me" # nginx proxy manager's mysql password
NPM_USER_PASSWORD = "this_should_be_long" # nginx proxy manager's mysql root password

NGINX_PORT = 81 # port to access nginx proxy managernginx proxy manager will use
NPM_DB_PORT = 3306 # port for mysql that 
DOCKER_PORT = 8000 # port docker uses
PORTAINER_PORT = 9000 # port to access portainer

PORTAINER_APP_TEMPLETES = https://raw.githubusercontent.com/Qballjos/portainer_templates/master/Template/template.json # uses this for the app store

FILES_PATH = /portainer/Files/AppData # base path for all sharded folders

CONFIGS_DIR = FILES_PATH . /Config # used to store all the config files for our docker images
LOGS_DIR = FILES_PATH . /Logs # used to store all the logs
DATABASE_DIR = FILES_PATH . /Databases # used to store all the databases for our docker images
BACKUPS_DIR = FILES_PATH . /Backups # used to temporaly store all the backup until it can be uploaded to where ever
# End Variables

# Start of options
CREATE_SMB_SHARE = TRUE # this will create a Windows share of the directors below
CREATE_UNIX_SHARE = TRUE # this will create a Unix/Linux share of the directors below
SSH_ENABLED = TRUE # enable ssh onthe RPI
# end options

# Start the Script
# DO NOT CHANGE ANY CODE BELOW THIS LINE

set -o errexit
set -o nounset

IFS=$(printf '\n\t')

# Docker
sudo apt remove --yes docker docker-engine docker.io containerd runc
sudo apt update
sudo apt --yes --no-install-recommends install apt-transport-https ca-certificates
wget --quiet --output-document=- https://download.docker.com/linux/debian/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/debian $(lsb_release --codename --short) stable"
sudo apt update
sudo apt --yes --no-install-recommends install docker-ce docker-ce-cli containerd.io
sudo usermod --append --groups docker "$USER"
sudo systemctl enable docker
printf '\nDocker installed successfully\n\n'

printf 'Waiting for Docker to start...\n\n'
sleep 5

# Docker Compose
sudo wget --output-document=/usr/local/bin/docker-compose "https://github.com/docker/compose/releases/download/$(wget --quiet --output-document=- https://api.github.com/repos/docker/compose/releases/latest | grep --perl-regexp --only-matching '"tag_name": "\K.*?(?=")')/run.sh"
sudo chmod +x /usr/local/bin/docker-compose
sudo wget --output-document=/etc/bash_completion.d/docker-compose "https://raw.githubusercontent.com/docker/compose/$(docker-compose version --short)/contrib/completion/bash/docker-compose"
printf '\nDocker Compose installed successfully\n\n'

# Portainer
sudo docker pull portainer/portainer-ce
sudo docker run --restart=always --name=portainer -d -p 9000:9000 -v /var/run/docker.sock:/var/run/docker.sock portainer/portainer-ce
printf '\nPortainer installed successfully\n\n'

# NGINX Proxy Manager
sudo tee -a /nginx/docker-compose.yml > /dev/null <<EOT
version: '3'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    environment:
      DB_MYSQL_HOST: "db"
      DB_MYSQL_PORT: 3306
      DB_MYSQL_USER: "npm"
      DB_MYSQL_PASSWORD: "npm"
      DB_MYSQL_NAME: "npm"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
  db:
    image: 'jc21/mariadb-aria:10.4'
    environment:
      MYSQL_ROOT_PASSWORD: 'npm'
      MYSQL_DATABASE: 'npm'
      MYSQL_USER: 'npm'
      MYSQL_PASSWORD: 'npm'
    volumes:
      - ./data/mysql:/var/lib/mysql
EOT
docker-compose -f /nginx/docker-compose.yml up
printf '\nDocker Container - Nginx Proxy Manager installed successfully\n\n'

# RPI Monitor
docker run --device=/dev/vchiq --volume=/opt/vc:/opt/vc --volume=/boot:/boot --volume=/sys:/dockerhost/sys:ro --volume=/etc:/dockerhost/etc:ro --volume=/proc:/dockerhost/proc:ro --volume=/usr/lib:/dockerhost/usr/lib:ro -p=8888:8888 --name="rpi-monitor" -d  michaelmiklis/rpi-monitor:latest
printf '\nDocker Container - RPI Monitor installed successfully\n\n'

# Watchtower
sudo tee -a /watchtower/docker-compose.yml > /dev/null <<EOT
version: '2.1'
services:
    watchtower :
        image: containrrr/watchtower
        container_name: watchtower
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock
        environment:
            - TZ=America/New_York
            - WATCHTOWER_MONITOR_ONLY=true
            - WATCHTOWER_SCHEDULE=0 0 16 ? * THU
            - WATCHTOWER_CLEANUP=true
            - WATCHTOWER_NOTIFICATIONS=email
            - WATCHTOWER_NOTIFICATION_EMAIL_FROM=FromEmail@gmail.com
            - WATCHTOWER_NOTIFICATION_EMAIL_TO=ToEmail@gmail.com
            - WATCHTOWER_NOTIFICATION_EMAIL_SERVER=smtp.gmail.com
            - WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PASSWORD=password
            - WATCHTOWER_NOTIFICATION_EMAIL_SUBJECTTAG=Pi Server Container Updates
            - WATCHTOWER_NOTIFICATION_EMAIL_SERVER_USER=FromEmail@gmail.com
            - WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PORT=587
        restart: unless-stopped
EOT
docker-compose -f /watchtower/docker-compose.yml up
printf '\nDocker Container - Watchtower installed successfully\n\n'

# Duplicati
sudo tee -a /duplicati/docker-compose.yml > /dev/null <<EOT
version: "2.1"
services:
  duplicati:
    image: linuxserver/duplicati:latest
    container_name: duplicati
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    volumes:
      - </portainer/Files/AppData/Config/Duplicati>:/config
      - </tmp>:/tmp
      - </backups>:/backups
      - </source>:/source
    ports:
      - 8200:8200
    restart: unless-stopped
EOT
docker-compose -f /duplicati/docker-compose.yml up
printf '\nDocker Container - Duplicati installed successfully\n\n'

# PI Hole
sudo tee -a /pihole/docker-compose.yml > /dev/null <<EOT
version: "3.8"

services:
  pihole:
    container_name: pihole
    image: pihole/pihole:v5.1.2
    restart: always

    environment:
      TZ: 'America/New_York' # Put your own timezone here.
      WEBPASSWORD: 'replacethispasswordplease' # Put a strong password here.
    
    # We'll use host networking simply because it is way easier to setup.
    network_mode: host
    
    # Volumes store your data between container upgrades
    volumes:
      - './etc-pihole/:/etc/pihole/'
      - './etc-dnsmasq.d/:/etc/dnsmasq.d/'
    
    # Required for the DHCP server
    cap_add:
      - NET_ADMIN
EOT
docker-compose -f /pihole/docker-compose.yml up
printf '\nDocker Container - PI Hole installed successfully\n\n'

# Cloudflare-ddns
sudo tee -a /cloudflare-ddns/docker-compose.yml > /dev/null <<EOT
version: '2'
services:
  cloudflare-ddns:
    image: oznu/cloudflare-ddns:latest
    restart: always
    environment:
      - API_KEY=ChangeThisAPI-Key
      - ZONE=mysite.com
      - SUBDOMAIN=monitor
      - PROXIED=true
EOT
docker-compose -f /cloudflare-ddns/docker-compose.yml up
printf '\nDocker Container - PI Hole installed successfully\n\n'

# Fail2ban
docker run -d --name fail2ban --restart always \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  -v $(pwd)/data:/data \
  -v /var/log:/var/log:ro \
  crazymax/fail2ban:latest
printf '\nDocker Container - Fail2ban installed successfully\n\n'

# Configure
printf '\nConfiguring your device please wait\n\n'

printf '\nConfiguration successfully\n\n'

# Rebooting
printf '\nRebooting Now\n\n'
sleep 5
sudo reboot now
