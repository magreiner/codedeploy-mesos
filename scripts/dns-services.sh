#!/bin/bash

apt-get install -yq dnsmasq
echo "server=/consul/127.0.0.1#8600" | tee /etc/dnsmasq.d/10-consul

service dnsmasq restart
