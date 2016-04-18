#!/bin/bash

# install requirements
apt-get install -yq unzip

# install vault
unzip -o /tmp/vault_*_linux_amd64.zip -d /usr/bin/
rm /tmp/vault_*_linux_amd64.zip
chmod +x /usr/bin/vault
