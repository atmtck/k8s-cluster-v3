#!/bin/sh

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

cp "$SCRIPT_DIR"/zram-activate.service /etc/systemd/system/
chmod 644 /etc/systemd/system/zram-activate.service
systemctl daemon-reload
systemctl enable --now zram-activate.service
