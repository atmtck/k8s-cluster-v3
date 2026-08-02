#!/bin/sh

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

apt install -y --no-install-recommends --no-install-suggests systemd-resolved

cp "$SCRIPT_DIR"/resolved.conf /etc/systemd/
chmod 644 /etc/systemd/resolved.conf
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl enable systemd-resolved
