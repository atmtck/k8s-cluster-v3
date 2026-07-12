#!/bin/sh

if ! command -v wg > /dev/null; then
    printf 'errore: installare comando wg (wireguard-tools)' >&2
    exit 1
fi

# scrittura variabili condivise
shared_env_file="env/env.shared"
> $shared_env_file
printf 'KUBEADM_TOKEN="%s"\n'    "$( kubeadm token generate )"        >> $shared_env_file
printf 'KUBEADM_CERT_KEY="%s"\n' "$( kubeadm certs certificate-key )" >> $shared_env_file
printf 'WG_PRESHARED_KEY="%s"\n' "$( wg genpsk )"                     >> $shared_env_file

# scrittura variabili per-host
printf '%s\n' "$( cat cluster_config.csv | tail -n +2 )" | while IFS=, read -r hostname domain wg_address pod_subnet root_drive timezone root_pubkey luks_password infomaniak_api_token; do

    public_env_file="env/$hostname.$domain.env.public"
    private_env_file="env/$hostname.$domain.env.private"
    > $public_env_file
    > $private_env_file
    printf 'NODE_HOSTNAME="%s"\n'        "$hostname.$domain"     >> $public_env_file
    printf 'WG_ADDRESS="%s"\n'           "$wg_address"           >> $public_env_file
    printf 'POD_SUBNET="%s"\n'           "$pod_subnet"           >> $public_env_file
    printf 'ROOT_DRIVE="%s"\n'           "$root_drive"           >> $private_env_file
    printf 'TIMEZONE="%s"\n'             "$timezone"             >> $private_env_file
    printf 'ROOT_PUBKEY="%s"\n'          "$root_pubkey"          >> $private_env_file
    printf 'LUKS_PASSWORD="%s"\n'        "$luks_password"        >> $private_env_file
    printf 'INFOMANIAK_API_TOKEN="%s"\n' "$infomaniak_api_token" >> $private_env_file
    
    wg_privkey=$( wg genkey )
    wg_pubkey=$( printf '%s' $wg_privkey | wg pubkey )
    printf 'WG_PRIVKEY="%s"\n' "$wg_privkey" >> $private_env_file
    printf 'WG_PUBKEY="%s"\n'  "$wg_pubkey"  >> $public_env_file
done
