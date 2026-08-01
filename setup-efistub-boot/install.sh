#!/bin/sh

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

apt install -y efibootmgr

cp "$SCRIPT_DIR"/uki-boot-update /etc/kernel/postinst.d/zc-uki-boot
chmod 744 /etc/kernel/postinst.d/zc-uki-boot