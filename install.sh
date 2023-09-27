#!/bin/bash
######################################
# NanoHome Automation Server Install
######################################

if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root. Try 'sudo ./install.sh'\n"
  exit 1
fi

# load settings
. ./config.cfg

# test if user exists

if getent passwd $linuxuser > /dev/null ; then
 
 echo "use existing user \"$linuxuser\""

else

 echo "create user $linuxuser"
 useradd -p $(openssl passwd -1 $linuxpass) $linuxuser

fi

# create directories

 mkdir -p $rootpath/bin/
 mkdir -p $rootpath/conf/
 mkdir -p $rootpath/driver/
 mkdir -p $rootpath/sensor/
 mkdir -p $rootpath/template/

# general

 touch $rootpath/devlist
 cp ./config.cfg $rootpath
 cp ./dev_compatibility $rootpath
 cp ./template/* $rootpath/template/

 sed -i "s#INSTALLDIR#$rootpath#" $rootpath/*

# prepare influxdb database

 influx -execute "CREATE DATABASE ${influxdb_database}"
 influx -execute "CREATE USER ${influxdb_admin} WITH PASSWORD '${influxdb_adminpass}' WITH ALL PRIVILEGES"
 influx -execute "CREATE USER ${influxdb_system_user} WITH PASSWORD '${influxdb_system_pass}'"
 influx -execute "GRANT ALL ON ${influxdb_database} TO ${influxdb_system_user}"

# configure mosquitto

 touch /etc/mosquitto/conf.d/nanohome.conf
 echo password_file /etc/mosquitto/passwd > /etc/mosquitto/conf.d/nanohome.conf
 echo allow_anonymous false >> /etc/mosquitto/conf.d/nanohome.conf
 echo listener 1883 >> /etc/mosquitto/conf.d/nanohome.conf
 echo listener 1884 >> /etc/mosquitto/conf.d/nanohome.conf
 echo protocol websockets >> /etc/mosquitto/conf.d/nanohome.conf

# create mosquitto user

 touch /etc/mosquitto/passwd
 mosquitto_passwd -U /etc/mosquitto/passwd
 mosquitto_passwd -b /etc/mosquitto/passwd $mqtt_system_user $mqtt_system_pass

# create mosquitto user for external access

 mosquitto_passwd -b /etc/mosquitto/passwd $mqtt_grafana_user $mqtt_grafana_pass
 mosquitto_passwd -b /etc/mosquitto/passwd $mqtt_shelly_user $mqtt_shelly_pass
 mosquitto_passwd -b /etc/mosquitto/passwd $mqtt_dash_user $mqtt_dash_pass

# copy binaries & make executable

 cp ./bin/* $rootpath/bin/
 chmod +x $rootpath/bin/*
 ln -sf $rootpath/bin/* /usr/local/bin/

 sed -i "s#INSTALLDIR#$rootpath#" $rootpath/bin/*

# copy drivers

 cp ./driver/* $rootpath/driver/
 chmod +x $rootpath/driver/*

 sed -i "s#INSTALLDIR#$rootpath#" $rootpath/driver/*
 sed -i "s#INFLUXDATABASE#$influxdb_database#" $rootpath/driver/*
 sed -i "s#DATABASEUSER#$influxdb_system_user#" $rootpath/driver/*
 sed -i "s#DATABASEPASS#$influxdb_system_pass#" $rootpath/driver/*
 sed -i "s#MQTTSYSTEMUSER#$mqtt_system_user#" $rootpath/driver/*
 sed -i "s#MQTTSYSTEMPASS#$mqtt_system_pass#" $rootpath/driver/*
 
# create services

 cp ./service/* /etc/systemd/system/
 sed -i "s#INSTALLDIR#$rootpath#" /etc/systemd/system/mqtt_*
 sed -i "s#SVCUSER#$linuxuser#" /etc/systemd/system/mqtt_*

 
# Grafana setup

# copy ressources
 
 cp -R ./res/* /usr/share/grafana/public/
 sed -i "s#;disable_sanitize_html.*#disable_sanitize_html = true#g" /etc/grafana/grafana.ini
 
# create datasource
 
  generate_datasource()
{
  cat <<EOF
{
  "name":"InfluxDB",
  "type":"influxdb",
  "url":"http://localhost:8086",
  "user":"$influxdb_system_user",
  "password":"$influxdb_system_pass",
  "database":"$influxdb_database",
  "access":"proxy",
  "isDefault":true,
  "readOnly":false
}
EOF
}
 
 curl -i \
 -H "Accept: application/json" \
 -H "Content-Type:application/json" \
 -X POST --data "$(generate_datasource)" "http://admin:admin@$grafana_url/api/datasources"
 
# create api key
 
 api_json="$(curl -X POST -H "Content-Type: application/json" -d '{"name":"Nanohome System", "role": "Admin"}' http://admin:admin@$grafana_url/api/auth/keys)"
 echo "$api_json" | sudo tee $rootpath/conf/api_key.json
 api_key="$(echo "$api_json" | jq -r '.key')"
 
# create dashboards 
 
 cp ./dashboards/* /tmp/

# home

 sed -i 's#var user = \\\"\\\"#var user = \\\"'$mqtt_grafana_user'\\\"#' /tmp/home.json
 sed -i 's#var pwd = \\\"\\\"#var pwd = \\\"'$mqtt_grafana_pass'\\\"#' /tmp/home.json
 
 curl -i \
 -H "Accept: application/json" \
 -H "Content-Type:application/json" \
 -X POST -d @/tmp/home.json "http://admin:admin@$grafana_url/api/dashboards/db"
 
 
# settings

 sed -i 's#var user = \\\"\\\"#var user = \\\"'$mqtt_grafana_user'\\\"#' /tmp/settings.json
 sed -i 's#var pwd = \\\"\\\"#var pwd = \\\"'$mqtt_grafana_pass'\\\"#' /tmp/settings.json
 
 curl -i \
 -H "Accept: application/json" \
 -H "Content-Type:application/json" \
 -X POST -d @/tmp/settings.json "http://admin:admin@$grafana_url/api/dashboards/db"
 
# timer

 sed -i 's#var user = \\\"\\\"#var user = \\\"'$mqtt_grafana_user'\\\"#' /tmp/timer.json
 sed -i 's#var pwd = \\\"\\\"#var pwd = \\\"'$mqtt_grafana_pass'\\\"#' /tmp/timer.json

 curl -i \
 -H "Accept: application/json" \
 -H "Content-Type:application/json" \
 -X POST -d @/tmp/timer.json "http://admin:admin@$grafana_url/api/dashboards/db"
 
# measurements
 
 curl -i \
 -H "Accept: application/json" \
 -H "Content-Type:application/json" \
 -X POST -d @/tmp/measurements.json "http://admin:admin@$grafana_url/api/dashboards/db"

# carpetplot
 
 curl -i \
 -H "Accept: application/json" \
 -H "Content-Type:application/json" \
 -X POST -d @/tmp/carpetplot.json "http://admin:admin@$grafana_url/api/dashboards/db"   

# change home dashboards

 home_id="$(curl -X GET -H "Authorization: Bearer $api_key" -H "Content-Type: application/json" http://$grafana_url/api/dashboards/uid/$home_uid | jq -r '.dashboard.id')"
 curl -X PUT -H "Content-Type: application/json" -d '{"homeDashboardId":'$home_id'}' http://admin:admin@$grafana_url/api/org/preferences

# install grafana backup

 pip3 install "pip>=20"

 git clone https://github.com/ysde/grafana-backup-tool.git $rootpath/grafana-backup-tool

 cd $rootpath/grafana-backup-tool
 pip3 install $rootpath/grafana-backup-tool
 cd -
 
 gbt_conf="$rootpath/grafana-backup-tool/grafana_backup/conf/grafanaSettings.json"

 echo "$( jq '.grafana.token = "'$api_key'"' $gbt_conf )" > $gbt_conf
 echo "$( jq '.general.backup_dir = "'$backupdir'"' $gbt_conf )" > $gbt_conf
 echo "$( jq '.general.verify_ssl = false' $gbt_conf )" > $gbt_conf

 sed -i "s#python#python3#" $rootpath/grafana-backup-tool/backup_grafana.sh
 sed -i "s#python#python3#" $rootpath/grafana-backup-tool/restore_grafana.sh


 
# post processing
 
 rm -rf /tmp/*.json
 chown -R $linuxuser:$linuxuser $rootpath
 
 /usr/share/grafana/bin/grafana-cli plugins install grafana-clock-panel
 /usr/share/grafana/bin/grafana-cli plugins install petrslavotinek-carpetplot-panel

# start services

 systemctl restart influxdb
 systemctl restart grafana-server
 systemctl restart mosquitto
 systemctl start mqtt_shell.service
 systemctl enable mqtt_shell.service

 
