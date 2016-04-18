#!/bin/bash

MASTER_INSTANCE_TAGNAME="AS_Master"

LOCAL_IP_ADDRESS="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
AZ="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
REGION="${AZ::-1}"

MASTER_IPS="$(aws ec2 describe-instances --region $REGION --filters "Name=tag:Name,Values=$MASTER_INSTANCE_TAGNAME" | jq '. | {ips: .Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddress}' | grep "\." | cut -f4 -d'"')"
FIRST_MASTER_IP="$(echo "$MASTER_IPS" | head -n1)"

mkdir -p /etc/mesos-dns/
cat > /etc/mesos-dns/config.json << EOF
{
  "zk": "zk://$FIRST_MASTER_IP:2181/mesos",
  "masters": ["$FIRST_MASTER_IP:5050"],
  "refreshSeconds": 60,
  "ttl": 60,
  "domain": "mesos",
  "port": 53,
  "resolvers": ["169.254.169.254"],
  "timeout": 5,
  "httpon": true,
  "dnson": true,
  "httpport": 8123,
  "externalon": true,
  "listener": "$LOCAL_IP_ADDRESS",
  "SOAMname": "ns1.mesos",
  "SOARname": "root.ns1.mesos",
  "SOARefresh": 60,
  "SOARetry":   600,
  "SOAExpire":  86400,
  "SOAMinttl": 60,
  "IPSources": ["netinfo", "mesos", "host"]
}
EOF
