#!/bin/sh

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

apt install -y chrony

cp "$SCRIPT_DIR"/chrony.conf /etc/chrony/
chmod 644 /etc/chrony/chrony.conf
systemctl enable --now chrony
