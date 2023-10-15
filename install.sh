#!/bin/bash
######################################
# NanoHome Automation Server Install
######################################

if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root. Try 'sudo ./install.sh'\n"
  exit 1
fi

# load settings
source ./config.cfg

# test if user exists
if getent passwd $linuxuser > /dev/null ; then
 
 echo "use existing user \"$linuxuser\""

else

 echo "create user $linuxuser"
 useradd -p $(openssl passwd -1 $linuxpass) $linuxuser

fi

##################################
# Filecopy
##################################

# create directories
mkdir -p $rootpath/bin/
mkdir -p $rootpath/conf/
mkdir -p $rootpath/driver/
mkdir -p $rootpath/service/
mkdir -p $rootpath/template/
mkdir -p /tmp/nanohome/dashboards
mkdir -p /tmp/nanohome/service

# Create list files
touch $rootpath/devlist
touch $rootpath/cronlist
touch $rootpath/killerlist
touch $rootpath/multilist

# Copy files
cp ./config.cfg $rootpath
cp ./devcompatibility $rootpath
cp ./bin/* $rootpath/bin/
cp ./driver/* $rootpath/driver/
cp ./template/* $rootpath/template/
cp ./dashboards/* /tmp/nanohome/dashboards
cp ./service/* /tmp/nanohome/service
cp -R ./res/* /usr/share/grafana/public/

# Change installation parameters
sed -i "s#INSTALLDIR#$rootpath#g" "$rootpath/devcompatibility"

for i in $rootpath/bin/*; do
    sed -i "s#INSTALLDIR#$rootpath#g" "$i"
done

for i in $rootpath/driver/*; do
    sed -i "s#INSTALLDIR#$rootpath#g" "$i"
done

sed -i "s#;disable_sanitize_html.*#disable_sanitize_html = true#g" "/etc/grafana/grafana.ini"

for i in /tmp/nanohome/service/*; do
    sed -i "s#INSTALLDIR#$rootpath#g" "$i"
	sed -i "s#SVCUSER#$linuxuser#g" "$i"
done

# Copy services
cp /tmp/nanohome/service/mqtt_shell.service /etc/systemd/system/
cp /tmp/nanohome/service/* $rootpath/service/

# Make binaries executable
chmod +x $rootpath/bin/*
chmod +x $rootpath/driver/*

# Link binaries
ln -sf $rootpath/bin/* /usr/local/bin/

##################################
# Mosquitto
##################################

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
mosquitto_passwd -b /etc/mosquitto/passwd $mqtt_grafana_user $mqtt_grafana_pass
mosquitto_passwd -b /etc/mosquitto/passwd $mqtt_shelly_user $mqtt_shelly_pass
mosquitto_passwd -b /etc/mosquitto/passwd $mqtt_dash_user $mqtt_dash_pass

##################################
# InfluxDB
##################################

# Setup InfluxDB 
influx setup \
  --username $influxdb_admin \
  --password $influxdb_adminpass \
  --token $influxdb_token \
  --org $influxdb_org \
  --bucket $influxdb_bucket \
  --force

# Create InfluxDB configuration profile
influx config create \
  --config-name $influxdb_config \
  --host-url $influxdb_url \
  --org $influxdb_org \
  --token $influxdb_token \
  --active

##################################
# Grafana
##################################

# Create Grafana Service Account
create_serviceaccount()
{
  cat <<EOF
{
  "name":"nanohome",
  "role":"Admin",
  "isDisabled":false
}
EOF
}

curl -i \
-H "Accept: application/json" \
-H "Content-Type:application/json" \
-X POST -d "$(create_serviceaccount)" "http://admin:admin@$grafana_url/api/serviceaccounts"

# Create Serviceaccount Token
token_json="$(curl -X POST -H "Content-Type: application/json" -d '{"name":"nanohome"}' http://admin:admin@$grafana_url/api/serviceaccounts/2/tokens)"
echo "$token_json" | sudo tee $rootpath/conf/sa_token.json
sa_token="$(echo "$token_json" | jq -r '.key')"

# Create InfluxDB datasource in Grafana
generate_datasource()
{
  cat <<EOF
{
  "name":"InfluxDB",
  "type":"influxdb",
  "typeName":"InfluxDB",
  "access":"proxy",
  "url":"$influxdb_url",
  "jsonData":{"defaultBucket":"$influxdb_bucket","organization":"$influxdb_org","version":"Flux","tlsSkipVerify":true},
  "secureJsonData":{"token":"$influxdb_token"},
  "isDefault":true,
  "readOnly":false
}
EOF
}

curl -i \
-H "Accept: application/json" \
-H "Content-Type:application/json" \
-H "Authorization: Bearer $sa_token" \
-X POST -d "$(generate_datasource)" "http://$grafana_url/api/datasources"

# Create Grafana home dashboard
sed -i 's#var user = \\\"\\\"#var user = \\\"'$mqtt_grafana_user'\\\"#' /tmp/nanohome/dashboards/home.json
sed -i 's#var pwd = \\\"\\\"#var pwd = \\\"'$mqtt_grafana_pass'\\\"#' /tmp/nanohome/dashboards/home.json
 
curl -i \
-H "Accept: application/json" \
-H "Content-Type:application/json" \
-H "Authorization: Bearer $sa_token" \
-X POST -d @/tmp/nanohome/dashboards/home.json "http://$grafana_url/api/dashboards/db"

# Create Grafana settings dashboard
sed -i 's#var user = \\\"\\\"#var user = \\\"'$mqtt_grafana_user'\\\"#' /tmp/nanohome/dashboards/settings.json
sed -i 's#var pwd = \\\"\\\"#var pwd = \\\"'$mqtt_grafana_pass'\\\"#' /tmp/nanohome/dashboards/settings.json
 
curl -i \
-H "Accept: application/json" \
-H "Content-Type:application/json" \
-H "Authorization: Bearer $sa_token" \
-X POST -d @/tmp/nanohome/dashboards/settings.json "http://$grafana_url/api/dashboards/db"
 
# Create Grafana timer dashboard
sed -i 's#var user = \\\"\\\"#var user = \\\"'$mqtt_grafana_user'\\\"#' /tmp/nanohome/dashboards/timer.json
sed -i 's#var pwd = \\\"\\\"#var pwd = \\\"'$mqtt_grafana_pass'\\\"#' /tmp/nanohome/dashboards/timer.json

curl -i \
-H "Accept: application/json" \
-H "Content-Type:application/json" \
-H "Authorization: Bearer $sa_token" \
-X POST -d @/tmp/nanohome/dashboards/timer.json "http://$grafana_url/api/dashboards/db"
 
# Create Grafana measurement dashboard
# 
# curl -i \
# -H "Accept: application/json" \
# -H "Content-Type:application/json" \
# -H "Authorization: Bearer $sa_token" \
# -X POST -d @/tmp/nanohome/dashboards/measurements.json "http://$grafana_url/api/dashboards/db"
#
# Create Grafana carpetplot dashboard
# 
# curl -i \
# -H "Accept: application/json" \
# -H "Content-Type:application/json" \
# -H "Authorization: Bearer $sa_token" \
# -X POST -d @/tmp/nanohome/dashboards/carpetplot.json "http://$grafana_url/api/dashboards/db"   

# Set Grafana home dashboard
home_id="$(curl -X GET -H "Authorization: Bearer $sa_token" -H "Content-Type: application/json" http://$grafana_url/api/dashboards/uid/$home_uid | jq -r '.dashboard.id')"

curl -i \
-H "Accept: application/json" \
-H "Content-Type:application/json" \
-H "Authorization: Bearer $sa_token" \
-X PUT -d '{"homeDashboardId":'$home_id'}' http://$grafana_url/api/org/preferences

##################################
# Postprocessing
##################################

# Change user running nanohome
chown -R $linuxuser:$linuxuser $rootpath

# Install Grafana Plugins
/usr/share/grafana/bin/grafana cli plugins install grafana-clock-panel
/usr/share/grafana/bin/grafana cli plugins install petrslavotinek-carpetplot-panel

# Prepare Crontab 
echo "# Nanohome Crontabs" >> /etc/crontab

# Cleanup
rm -rf /tmp/*.json

# Start services
systemctl restart influxdb
systemctl restart grafana-server
systemctl restart mosquitto
systemctl start mqtt_shell.service
systemctl enable mqtt_shell.service
