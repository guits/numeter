#!/bin/bash

set -x

# Config
OSLO_MESSAGING_FREEZE=5a48b027a015109096d3827300d7185a8cf3fdf0
DIST=wheezy
BRANCH=${BRANCH:-"master"}

# Force --go just in case :p
if ! [ "$1" == "--go" ];then
    echo "This script install a full numeter from sources with nginx and apache and validate config in docs example"
    echo "usage $0 --go"
    exit 1
fi

setup_sourcelist(){
    echo "deb http://cloud.pkgs.enovance.com/$DIST-havana havana main" > /etc/apt/sources.list.d/havana.list
    apt-key adv --recv-keys --keyserver keyserver.ubuntu.com E52660B15D964F0B
    if [ "$DIST" == "wheezy" ]; then
        echo "deb http://ftp.fr.debian.org/debian wheezy-backports main" > /etc/apt/sources.list.d/debian-backports.list
    fi
}

setup_numeter(){
    # Force django backports
    if [ "$DIST" == "wheezy" ]; then
        apt-get install -y -t wheezy-backports python-django python-mimeparse
    fi

    pip install djangorestframework

    cd /opt && git clone https://github.com/enovance/numeter
    cd /opt/numeter && git checkout $BRANCH

    for package in {common,poller,storage,web-app}; do
        echo "# Setup $package"
        cd /opt/numeter/$package && python setup.py install

        if [ "$?" -ne "0" ]; then
          echo "ERROR : Unable to setup package $package"
          exit 2
        fi
    done
}

setup_oslo_messaging(){
    # Depends
    apt-get install -y python-kombu
    cd /opt && git clone https://github.com/openstack/oslo.messaging
    cd /opt/oslo.messaging && git checkout $OSLO_MESSAGING_FREEZE
    cd /opt/oslo.messaging && python setup.py install
}

config_poller(){
    sed -i 's/enable = false/enable = true/' /etc/numeter/numeter_poller.cfg
    sed -i 's/host_id =.*/host_id = poller/' /etc/numeter/numeter_poller.cfg
    sed -i 's/plugins_enable =.*/plugins_enable = ^load$/' /etc/numeter/numeter_poller.cfg
}

config_storage(){
    sed -i 's/enable = false/enable = true/' /etc/numeter/numeter_storage.cfg
    echo poller > /etc/numeter/host-list
    # Nginx
    cd /opt/numeter && cp storage/storage-web/numeter-storage-web.nginx.example /etc/nginx/sites-available/numeter-storage-web
    ln -s /etc/nginx/sites-available/numeter-storage-web /etc/nginx/sites-enabled/
    /etc/init.d/nginx restart
    # uwsgi
    cd /opt/numeter && cp storage/storage-web/numeter-storage-uwsgi.ini.example /etc/uwsgi/apps-available/numeter-storage-uwsgi.ini
    ln -s /etc/uwsgi/apps-available/numeter-storage-uwsgi.ini /etc/uwsgi/apps-enabled/
    /etc/init.d/uwsgi restart
}

config_webapp(){

    # Create database
    cat <<EOF | mysql --defaults-file=/etc/mysql/debian.cnf
CREATE DATABASE numeter;
GRANT ALL ON numeter.* TO numeter@'localhost' IDENTIFIED BY 'yourpass';
EOF

    # Config webapp
    sed -i /etc/numeter/numeter_webapp.cfg -re '
      s/^engine.*/engine = django.db.backends.mysql/ ;
      s/^name.*/name = numeter/ ;
      s/^user.*/user = numeter/ ;
      s/^password.*/password = yourpass/ ;
      s/^host.*/host = localhost/ ;
      s/^port.*/port = 3306/'

    # Write default json user
    # Generated by : numeter-webapp dumpdata --indent=2 core.user > /tmp/user.json
    cat > /tmp/user.json <<EOF
[
{
  "pk": 1,
  "model": "core.user",
  "fields": {
    "username": "admin",
    "graph_lib": "dygraph",
    "is_active": true,
    "is_superuser": true,
    "is_staff": true,
    "last_login": "2013-10-30T21:15:47Z",
    "groups": [],
    "password": "pbkdf2_sha256\$10000\$cX65C75h7s3t\$z0J3y6808UcsJ0aVpqn4OZ7OJcYMVlEGljbHOWZbnOI=",
    "email": "",
    "date_joined": "2013-10-30T21:15:47Z"
  }
}
]
EOF
    # populate database
    numeter-webapp syncdb --noinput
    # Import default admin user (admin : admin)
    numeter-webapp loaddata /tmp/user.json
    # Add storage
    numeter-webapp storage add --name=local_storage --port=8080 --url_prefix=/numeter-storage --address=127.0.0.1

    # Configure web server
    unlink /etc/nginx/sites-enabled/default
    NUMETER_DIR=$(dirname $(python -c 'import numeter_webapp;print numeter_webapp.__file__'))

    # Apache
    a2enmod wsgi
    a2dissite default
    cd /opt/numeter && cp web-app/extras/numeter-apache.example /etc/apache2/sites-available/numeter-webapp
    a2ensite numeter-webapp
    sed -i "s#@APP_DIR@#$NUMETER_DIR#g" /etc/apache2/sites-available/numeter-webapp
    sed -i "s/:80/:81/g" /etc/apache2/sites-available/numeter-webapp
    sed -i "s/80/81/g" /etc/apache2/ports.conf
    /etc/init.d/apache2 restart

    # Nginx
    cd /opt/numeter && cp web-app/extras/numeter-nginx.example /etc/nginx/sites-available/numeter-webapp
    ln -s /etc/nginx/sites-available/numeter-webapp /etc/nginx/sites-enabled/
    sed -i "s#@APP_DIR@#$NUMETER_DIR#g" /etc/nginx/sites-available/numeter-webapp
    /etc/init.d/nginx restart
    # uwsgi
    cd /opt/numeter && cp web-app/extras/numeter_webapp.ini.example /etc/uwsgi/apps-available/numeter_webapp.ini
    ln -s /etc/uwsgi/apps-available/numeter_webapp.ini /etc/uwsgi/apps-enabled/
    sed -i "s#@APP_DIR@#$NUMETER_DIR#g" /etc/uwsgi/apps-available/numeter_webapp.ini
    /etc/init.d/uwsgi restart

}

launch_numeter(){
    # First launch storage to create rabbitmq queue
    eval "numeter-storage &"
    storage_pid=$!
    sleep 5
    kill $storage_pid

    sleep 1

    # Launch poller
    rm -f /tmp/numeter-poller_last
    numeter-poller

    sleep 1

    # Launch storage to consume datas
    eval "numeter-storage &"
    storage_pid=$!
    sleep 5
    kill $storage_pid

    # Populate webapp db after storage launch one time
    numeter-webapp populate -i all
}

check_wsp_file(){
    if [ -z "$(find /var/lib/numeter/wsps/ -type f -name load.wsp)" ];then
        echo ERROR wsp file not found
        exit 2
    fi
}

check_storage_api(){
    if [ -z "$(curl http://127.0.0.1:8080/numeter-storage/list?host=poller | grep load)" ];then
        echo ERROR storage api datas
        exit 2
    fi
    if [ -z "$(curl 'http://127.0.0.1:8080/numeter-storage/info?host=poller&plugin=load' | grep load)" ];then
        echo ERROR storage api infos
        exit 2
    fi
}

check_webapp(){
    # By Nginx
    if [ -z "$(curl 'http://127.0.0.1/wide-storage/list?host=poller' -u admin:admin | grep load)" ];then
        echo ERROR webapp wild_storage info by Nginx
        exit 2
    fi
    if [ -z "$(curl 'http://127.0.0.1/login' | grep '<title>Numeter - Authentification</title>')" ];then
        echo ERROR webapp login page by Nginx
        exit 2
    fi
    # By Apache
    if [ -z "$(curl 'http://127.0.0.1:81/wide-storage/list?host=poller' -u admin:admin | grep load)" ];then
        echo ERROR webapp wild_storage info by Apache
        exit 2
    fi
    if [ -z "$(curl 'http://127.0.0.1:81/login' | grep '<title>Numeter - Authentification</title>')" ];then
        echo ERROR webapp login page by Apache
        exit 2
    fi
}

#
# main
#

echo "Setup dependencies ..."

setup_sourcelist
apt-get update

# Apt depends
apt-get install -y devscripts reprepro rabbitmq-server python-dev git-core python-daemon python-setuptools curl munin-node
apt-get install -y nginx uwsgi uwsgi-plugin-python python-flask python-whisper redis-server python-redis
apt-get install -y python-mysqldb mysql-client apache2 libapache2-mod-wsgi
easy_install pip

export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install mysql-server
unset DEBIAN_FRONTEND

# Install numeter
setup_oslo_messaging
setup_numeter

# Configure numeter
config_poller
config_storage
config_webapp

# Launch numeter
launch_numeter

# Check if it's ok
check_wsp_file
check_storage_api
check_webapp

echo "Success"
