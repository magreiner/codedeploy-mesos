#!/bin/bash

MASTER_INSTANCE_TAGNAME="AS_Master"
AZ="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
REGION="${AZ::-1}"
MASTER_IPS="$(aws ec2 describe-instances --region $REGION --filters "Name=tag:Name,Values=$MASTER_INSTANCE_TAGNAME" | jq '. | {ips: .Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddress}' | grep "\." | cut -f4 -d'"')"
FIRST_MASTER_IP="$(echo "$MASTER_IPS" | head -n1)"

export VAULT_ADDR="http://$FIRST_MASTER_IP:8201"
echo "export VAULT_ADDR=\"http://$FIRST_MASTER_IP:8201\"" >> /home/ubuntu/.bashrc
echo "export VAULT_ADDR=\"http://$FIRST_MASTER_IP:8201\"" >> /root/.bashrc

# install requirements
apt-get install -yq unzip

# install vault
unzip -o /tmp/vault_*_linux_amd64.zip -d /usr/bin/
rm /tmp/vault_*_linux_amd64.zip
chmod +x /usr/bin/vault
