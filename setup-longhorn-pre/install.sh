#!/bin/sh

apt install -y nfs-common open-iscsi cryptsetup

cat <<EOF > /etc/modules-load.d/longhorn.conf
nfs
iscsi_tcp
dm_crypt
EOF
