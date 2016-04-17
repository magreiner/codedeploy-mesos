#!/bin/bash

# Preload seafile docker image
# If a old docker container is already running
# it will be removed and newly build

ssh-keyscan bitbucket.org >> ~/.ssh/known_hosts
rm -rf /tmp/docbox 2>/dev/null

git clone https://bitbucket.org/m_greiner/docbox.git /tmp/docbox 2>/dev/null

SEAFILE_CONTAINER_NAME="$(docker ps | grep "seafile" | cut -d' ' -f1)"
docker kill $SEAFILE_CONTAINER_NAME &>/dev/null
docker rm $SEAFILE_CONTAINER_NAME &>/dev/null
docker rmi mgreiner/seafile &>/dev/null
docker build -t "mgreiner/seafile" "/tmp/docbox/seafile/"


MYSQL_CONTAINER_NAME="$(docker ps | grep "mysql" | cut -d' ' -f1)"
docker kill $MYSQL_CONTAINER_NAME &>/dev/null
docker rm $MYSQL_CONTAINER_NAME &>/dev/null
docker rmi mgreiner/mysql &>/dev/null
docker build -t "mgreiner/mysql" "/tmp/docbox/mysql/"
