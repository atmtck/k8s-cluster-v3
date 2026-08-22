#!/bin/sh

apt install -y nfs-common open-iscsi cryptsetup

cat <<EOF > /etc/modules-load.d/longhorn.conf
nfs
iscsi_tcp
dm_crypt
EOF

curl -LO "https://github.com/longhorn/cli/releases/download/v1.12.1/longhornctl-linux-amd64"
mv longhornctl-linux-amd64 /usr/local/bin/longhornctl
chmod 700 /usr/local/bin/longhornctl
