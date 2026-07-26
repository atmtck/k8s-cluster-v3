#!/bin/sh

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

mv /etc/network/interfaces /etc/network/interfaces.save

cp "$SCRIPT_DIR"/*.network /etc/systemd/network/
chmod 644 /etc/systemd/network/*.network
systemctl enable --now systemd-networkd
systemctl disable --now systemd-networkd-wait-online
