#!/bin/sh

[ -x $( which wg ) ] || exit 1

printf '%s\n' "$( cat cluster_config.csv | tail -n +2 )" | while IFS=, read -r hostname domain wg_address pod_subnet root_drive timezone root_pubkey luks_password infomaniak_api_token; do

    env_file="env/$hostname.$domain.env"
    > $env_file
    printf 'NODE_HOSTNAME="%s"\n'        "$hostname.$domain"     >> $env_file
    printf 'WG_ADDRESS="%s"\n'           "$wg_address"           >> $env_file
    printf 'POD_SUBNET="%s"\n'           "$pod_subnet"           >> $env_file
    printf 'ROOT_DRIVE="%s"\n'           "$root_drive"           >> $env_file
    printf 'TIMEZONE="%s"\n'             "$timezone"             >> $env_file
    printf 'ROOT_PUBKEY="%s"\n'          "$root_pubkey"          >> $env_file
    printf 'LUKS_PASSWORD="%s"\n'        "$luks_password"        >> $env_file
    printf 'INFOMANIAK_API_TOKEN="%s"\n' "$infomaniak_api_token" >> $env_file
    
    wg_privkey=$( wg genkey )
    wg_pubkey=$( printf '%s' $wg_privkey | wg pubkey )
    printf 'WG_PRIVKEY="%s"\n' "$wg_privkey" >> $env_file
    printf 'WG_PUBKEY="%s"\n'  "$wg_pubkey"  >> $env_file

done
