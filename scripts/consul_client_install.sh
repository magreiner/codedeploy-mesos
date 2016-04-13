#!/bin/bash

MIN_MASTER_INSTANCES=1
MASTER_INSTANCE_TAGNAME="AS_Master"
WORKER_INSTANCE_TAGNAME="AS_Worker"

LOCAL_IP_ADDRESS=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
AZ="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
REGION="${AZ::-1}"

# Looking for other master instances for HA (Zookeeper)
MASTER_IPS=$(aws ec2 describe-instances --region $REGION --filters "Name=tag:Name,Values=$MASTER_INSTANCE_TAGNAME" | jq '. | {ips: .Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddress}' | grep "\." | cut -f4 -d'"')
MASTER_INSTANCES_ONLINE=$(echo "$MASTER_IPS" | grep "\." | wc -l)

while [ "$MASTER_INSTANCES_ONLINE" -lt "$MIN_MASTER_INSTANCES" ]; do
  sleep 2
  echo "Waiting for more master instances. ($MASTER_INSTANCES_ONLINE/$MIN_MASTER_INSTANCES online)"
  MASTER_IPS=$(aws ec2 describe-instances --region $REGION --filters "Name=tag:Name,Values=$MASTER_INSTANCE_TAGNAME" | jq '. | {ips: .Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddress}' | grep "\." | cut -f4 -d'"' | head -n1)
  MASTER_INSTANCES_ONLINE=$(echo "$MASTER_IPS" | grep "\." | wc -l)
done
FIRST_MASTER_IP=$(echo "$MASTER_IPS" | head -n1)

apt-get install -yq unzip

# Create consul user
adduser --quiet --disabled-password -shell /bin/bash --home /home/consul --gecos "User" consul

mkdir /var/consul
chown consul:consul /var/consul

# Create config file
mkdir -p /etc/consul.d/client
cat > /etc/consul.d/client/config.json << EOF
{
    "bootstrap": false,
    "server": false,
    "datacenter": "MesosCluster",
    "data_dir": "/var/consul",
    "ui_dir": "/opt/consul",
    "encrypt": "W0OoYJkDcHa+EwmUtbOtcA==",
    "log_level": "INFO",
    "enable_syslog": true,
    "start_join": [ "$FIRST_MASTER_IP" ]
}
EOF

# Extract and start consul binary
unzip /tmp/consul_*_linux_amd64.zip -d /usr/bin/
rm /tmp/consul_*_linux_amd64.zip
chmod +x /usr/bin/consul

start consul

# Debug with:
# consul agent -server \
#     -bootstrap-expect 1 \
#     -data-dir /var/consul \
#     -node=Client-$LOCAL_IP_ADDRESS \
#     -bind=$LOCAL_IP_ADDRESS \
#     -client=0.0.0.0 \
#     -config-dir /etc/consul.d \
#     -ui-dir /opt/consul-ui/

# Extract consul web_ui
unzip /tmp/consul_*_web_ui.zip -d /opt/consul/
rm /tmp/consul_*_web_ui.zip
chown -R consul:consul /opt/consul

# Extract and start consul-template
# Source:
# https://releases.hashicorp.com/consul-template/
unzip /tmp/consul-template_*_linux_amd64.zip -d /usr/bin/
rm /tmp/consul-template_*_linux_amd64.zip
chmod a+x /usr/bin/consul-template

# consul-template \
#     -consul $LOCAL_IP_ADDRESS:8500 \
#     -template "$PATH_TO_TEMPLATE:$PATH_TO_CONFIG_FILE" \
#     -retry 30s
