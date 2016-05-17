#!/bin/bash

MASTER_INSTANCE_TAGNAME="AS_Master"

LOCAL_IP_ADDRESS="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
AZ="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
REGION="${AZ::-1}"

MASTER_IPS="$(aws ec2 describe-instances --region $REGION --filters "Name=tag:Name,Values=$MASTER_INSTANCE_TAGNAME" --query 'Reservations[*].Instances[*].NetworkInterfaces[*].PrivateIpAddress' --output text)"
FIRST_MASTER_IP="$(echo "$MASTER_IPS" | head -n1)"

service resolvconf stop
echo manual | sudo tee /etc/init/resolvconf.override

# replace resolv.conf and ensure it survives reboots without modifications
SEARCH_ORIG="$(cat /etc/resolv.conf | grep search | cut -d' ' -f2)"
chattr -i /etc/resolv.conf
rm /etc/resolv.conf
cat > /etc/resolv.conf << EOF
nameserver $FIRST_MASTER_IP
search $SEARCH_ORIG
EOF
chattr +i /etc/resolv.conf
