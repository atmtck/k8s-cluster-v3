#!/bin/sh

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

apt install -y --no-install-recommends --no-install-suggests efibootmgr

cp "$SCRIPT_DIR"/zc-uki-boot /etc/kernel/postinst.d/zc-uki-boot
chmod 744 /etc/kernel/postinst.d/zc-uki-boot
/etc/kernel/postinst.d/zc-uki-boot
