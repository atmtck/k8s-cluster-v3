#!/bin/sh

HOSTNAME=$( cat /etc/hostname )
[ -f "/usr/local/etc/env/$HOSTNAME.env.private" ] || exit 1

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

# installazione regole nft per nat degli ip dei pod in caso di traffico fuori dal cluster
cp "$SCRIPT_DIR"/cni-masquerade-rules.nft /usr/local/bin/
chmod 544 /usr/local/bin/cni-masquerade-rules.nft

cp "$SCRIPT_DIR"/cni-masquerade-rules.service /etc/systemd/system/
chmod 444 /etc/systemd/system/cni-masquerade-rules.service

apt install -y --no-install-recommends --no-install-suggests nftables
systemctl enable cni-masquerade-rules.service

# copia file configurazione cni
mkdir -p /etc/cni/net.d/
cp "$SCRIPT_DIR"/10-bridge.conflist /etc/cni/net.d/10-bridge.conflist
chmod 600 /etc/cni/net.d/10-bridge.conflist

# sostituzione subnet corretta in conf cni
. "/usr/local/etc/env/$HOSTNAME.env.public"
sed -i "s|###pod_network_cidr###|$POD_SUBNET|" /etc/cni/net.d/10-bridge.conflist
