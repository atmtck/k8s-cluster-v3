#!/bin/sh

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

if [ -f /etc/network/interfaces ]; then
  mv /etc/network/interfaces /etc/network/interfaces.save
fi

cp "$SCRIPT_DIR"/*.network /etc/systemd/network/
chmod 644 /etc/systemd/network/*.network
systemctl enable systemd-networkd
systemctl disable systemd-networkd-wait-online
