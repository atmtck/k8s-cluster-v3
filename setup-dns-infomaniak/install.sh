#!/bin/sh

HOSTNAME=$( cat /etc/hostname )
[ -f "/usr/local/etc/env/$HOSTNAME.env.private" ] || exit 1

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

. "/usr/local/etc/env/$HOSTNAME.env.private"

mkdir -p /usr/local/etc /usr/local/bin
printf '%s' "$INFOMANIAK_API_TOKEN" > /usr/local/etc/infomaniak_api_token
chmod 400 /usr/local/etc/infomaniak_api_token

cp "$SCRIPT_DIR"/dns-update-infomaniak /usr/local/bin/
chmod 744 /usr/local/bin/dns-update-infomaniak

cp "$SCRIPT_DIR"/dns-update-infomaniak.service "$SCRIPT_DIR"/dns-update-infomaniak.timer /etc/systemd/system/
chmod 644 /etc/systemd/system/dns-update-infomaniak.service /etc/systemd/system/dns-update-infomaniak.timer

apt install -y --no-install-recommends --no-install-suggests curl jq
systemctl enable dns-update-infomaniak.timer
