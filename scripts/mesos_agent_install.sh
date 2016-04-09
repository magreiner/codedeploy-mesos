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

#
# DOCKER
#
apt-get update
apt-get --yes install apt-transport-https ca-certificates

apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get --yes install apparmor \
                      linux-image-extra-$(uname -r)
apt-get --yes install docker-engine

usermod -aG docker ubuntu

service docker start
#
# MESOS CLIENT
#
apt-key adv --keyserver keyserver.ubuntu.com --recv E56151BF
DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
CODENAME=$(lsb_release -cs)
echo "deb http://repos.mesosphere.com/${DISTRO} ${CODENAME} main" > /etc/apt/sources.list.d/mesosphere.list
apt-get --yes update
apt-get --yes install mesos

# Disable mesos-master on the slaves
service mesos-master stop
echo manual | tee /etc/init/mesos-master.override

# Disable zookeeper on the slaves
service zookeeper stop
echo manual | tee /etc/init/zookeeper.override
apt-get -y remove --purge zookeeper

echo 'docker,mesos' > /etc/mesos-slave/containerizers
echo '5mins' > /etc/mesos-slave/executor_registration_timeout
echo $LOCAL_IP_ADDRESS | tee /etc/mesos-slave/ip
echo zk://$FIRST_MASTER_IP:2181/mesos | tee /etc/mesos/zk
echo $LOCAL_IP_ADDRESS | tee /etc/mesos-slave/hostname

service mesos-slave restart

# screen -dmS mesos-agent bash -c  "/usr/sbin/mesos-slave --master=$FIRST_MASTER_IP:5050 --ip=$LOCAL_IP_ADDRESS --work_dir=/var/lib/mesos"

# Preload seafile docker image
mkdir git
cd git
git clone git@bitbucket.org:m_greiner/docbox.git
cd ./seafile/
sudo docker build -t "mgreiner/seafile" "."
