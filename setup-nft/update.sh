#!/bin/sh

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

cp "$SCRIPT_DIR"/nft-input-rules.nft /usr/local/bin/
chmod 544 /usr/local/bin/nft-input-rules.nft

cp "$SCRIPT_DIR"/nft-input-rules.service /etc/systemd/system/
chmod 444 /etc/systemd/system/nft-input-rules.service

nft delete table inet input-rules
systemctl restart nft-input-rules.service
