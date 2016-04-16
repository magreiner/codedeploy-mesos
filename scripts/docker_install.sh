#!/bin/bash

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
