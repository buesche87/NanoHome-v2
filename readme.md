# NanoHome

This is a one-man show, don't expect it to be bug-free...

I used https://dietpi.com as distribution

You can install NanoHome on a virtual machine, Raspberry Pi or any another SBC. 
The following steps should be everything you need on a debian based distro for it to start.

# Repositories

## InfluxDB (example debian bullseye)

```bash
wget https://dl.influxdata.com/influxdb/releases/influxdb2-2.7.1-amd64.deb
sudo dpkg -i influxdb2-2.7.1-amd64.deb


wget https://dl.influxdata.com/influxdb/releases/influxdb2-client-2.7.3-linux-amd64.tar.gz
tar xvzf influxdb2-client-2.7.3-linux-amd64.tar.gz
sudo cp influx /usr/local/bin/

```

## Grafana
```bash
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
```

# Dependencies


## Install software
```bash
sudo apt update
sudo apt install grafana mosquitto git 
```

## Install dependencies
```bash
sudo apt install mosquitto-clients build-essential libfreetype6-dev libjpeg-dev jq openssl tree bc
```

# unmask influxdb and start it
```bash
sudo service influxdb start
```

## Install NanoHome

# Clone NanoHome
```bash
git clone https://github.com/buesche87/NanoHome.git
```

# Edit NanoHome Config

Copy `config.cfg.example` to `config.cfg`.

Edit username and password entries. Don't mess with the dashboard settings, these id's are given by the installation.

# Install

```bash
cd NanoHome
chmod +x ./install.sh
sudo ./install.sh
```

Start your Webbroser and go to http://ipaddress:3000/
