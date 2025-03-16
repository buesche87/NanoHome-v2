# NanoHome v2

This repository will not be maintained anymore. Use the docker repository instead

---

A simple home automation solution for shelly devices with focus on a nice dashboard that can be presented on a tablet.

Version 2 changes:

- New UI, minimalist approach
- Completely rewritten
- Add support for Shelly Plus devices
- Adopt to InfluxDB v2
- Adopt to Grafana service accounts
- Working installer

I used https://dietpi.com as distribution

You can install NanoHome on a virtual machine, Raspberry Pi or any another SBC. 
The following steps should be everything you need on a debian based distro.

# Dependencies

## Install InfluxDB with Influx CLI

```bash
wget https://dl.influxdata.com/influxdb/releases/influxdb2-2.7.1-amd64.deb
sudo dpkg -i influxdb2-2.7.1-amd64.deb

wget https://dl.influxdata.com/influxdb/releases/influxdb2-client-2.7.3-linux-amd64.tar.gz
mkdir ./influxcli
tar xvzf influxdb2-client-2.7.3-linux-amd64.tar.gz -C ./influxcli
sudo cp ./influxcli/influx /usr/local/bin/
```

## Add Grafana repository
```bash
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
```

## Install software
```bash
sudo apt update
sudo apt install grafana mosquitto mosquitto-clients git openssl jq
```

# Start Services
```bash
sudo systemctl enable influxdb
sudo systemctl enable grafana-server
sudo systemctl enable mosquitto
sudo systemctl start influxdb
sudo systemctl start grafana-server
sudo systemctl start mosquitto
```

# Install NanoHome

## Clone NanoHome
```bash
git clone https://github.com/buesche87/NanoHome-v2.git
```

## Edit NanoHome config
```bash
cd NanoHome-v2
cp config.cfg.example config.cfg
```

Edit account details. Don't mess with the dashboard settings, these id's are given by the installation.

## Install

```bash
chmod +x ./install.sh
sudo ./install.sh
```

Go to http://youripadress:3000/ and login with admin:admin
