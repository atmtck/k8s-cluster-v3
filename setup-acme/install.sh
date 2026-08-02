#!/bin/sh

HOSTNAME=$( cat /etc/hostname )
[ -f "/usr/local/etc/env/$HOSTNAME.env.private" ] || exit 1

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

. "/usr/local/etc/env/$HOSTNAME.env.private"
. "/usr/local/etc/env/$HOSTNAME.env.public"

export INFOMANIAK_API_TOKEN="$INFOMANIAK_API_TOKEN"
ACME_DOMAIN="$( cat /etc/hostname | cut -d '.' -f 2- )"

apt install -y --no-install-recommends --no-install-suggests acme.sh
mkdir -p /etc/acme.sh

acme.sh --config-home /etc/acme.sh \
        --server letsencrypt \
        --issue \
        --dns dns_infomaniak \
        -d "$ACME_DOMAIN" -d "*.$ACME_DOMAIN"

acme.sh --config-home /etc/acme.sh \
        -d "$ACME_DOMAIN" -d "*.$ACME_DOMAIN" \
        --install-cert \
        --key-file "/etc/ssl/private/${ACME_DOMAIN}.key" \
        --fullchain-file "/etc/ssl/private/${ACME_DOMAIN}.pem"

mkdir -p /etc/auth
printf '%s' "$INFOMANIAK_API_TOKEN" > /etc/auth/infomaniak_api_token

cp "$SCRIPT_DIR"/acme-sh.service "$SCRIPT_DIR"/acme-sh.timer /etc/systemd/system/
chmod 644 /etc/systemd/system/acme-sh.service /etc/systemd/system/acme-sh.timer
systemctl enable acme-sh.timer
