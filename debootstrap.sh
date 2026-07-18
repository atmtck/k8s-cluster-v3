#!/bin/sh

set -xe

# verifica cartella esecuzione script
if [ "$(cd "$(dirname "$0")" && pwd)" != "$(pwd)" ]; then
    printf 'errore: eseguire lo script nella stessa cartella in cui risiede' >&2
    exit 1
fi


# verifica presenza comandi richiesti
for command in parted mmdebstrap openssl cert-to-efi-sig-list sign-efi-sig-list sbkeysync efi-updatevar uuidgen; do
    if ! command -v "$command" > /dev/null; then
        printf 'errore: installare comando %s' "$command" >&2
        printf 'debian: apt install -y parted mmdebstrap openssl sbsigntool efitools uuid-runtime' >&2
        exit 1
    fi
done


# selezione host
env_file_list=$( find env/ -name '*.private' -type f | sed -E 's#.*/##' | sed -E 's#.env.private$##' | sort | nl )
while true; do
     printf 'selezionare numero host:\n%s\n' "$env_file_list"
     read chosen_host
     if ! printf '%s' "$chosen_host" | grep -qE '^[0-9]+$'; then continue; fi
     if printf '%s' "$env_file_list" | grep -qE '^\s*'"$chosen_host"'\s+'; then break; fi
done
chosen_host=$( printf '%s' "$env_file_list" | grep -E '^\s*'"$chosen_host"'\s+' | grep -oE '\S+$' )
printf 'selezionato: %s\n' "$chosen_host"


# source host selezionato
. "env/env.shared"
. "env/$chosen_host.env.private"
. "env/$chosen_host.env.public"


# prepara disco e partizioni
blkdiscard -f "$ROOT_DRIVE"
parted "$ROOT_DRIVE" --script mklabel gpt
parted "$ROOT_DRIVE" --script mkpart 'ESP' fat32 1MiB 1025MiB
parted "$ROOT_DRIVE" --script set 1 esp on
parted "$ROOT_DRIVE" --script mkpart 'ROOT' 1025MiB 100%


# crea container luks e filesystem
target_esp=$( blkid | grep "$ROOT_DRIVE" | grep 'PARTLABEL="ESP"' | grep -oP "$ROOT_DRIVE"'\S+(?=: )' )
target_luks=$( blkid | grep "$ROOT_DRIVE" | grep 'PARTLABEL="ROOT"' | grep -oP "$ROOT_DRIVE"'\S+(?=: )' )
cryptsetup -q luksFormat "$target_luks" --cipher aes-xts-plain64 --key-size 512 --pbkdf argon2id --iter-time 100 <<EOF
$LUKS_PASSWORD
EOF
cryptsetup luksOpen --allow-discards --perf-no_read_workqueue --perf-no_write_workqueue --persistent "$target_luks" luks_root <<EOF
$LUKS_PASSWORD
EOF
mkfs.fat "$target_esp"
mkfs.ext4 -F /dev/mapper/luks_root


# bootstrap del sistema
chroot_folder=$(mktemp -d)
mount /dev/mapper/luks_root "$chroot_folder"
/usr/bin/mmdebstrap --variant=minbase \
    --components="main non-free-firmware security-updates" \
    --skip=check/empty \
    trixie "$chroot_folder"
mkdir -p "$chroot_folder/boot/efi"
mount "$target_esp" "$chroot_folder/boot/efi"


# copia file environment
mkdir -p "$chroot_folder/usr/local/etc/env"
cp "env/$chosen_host.env.private" env/*.public env/env.shared "$chroot_folder/usr/local/etc/env/"


# chroot prep
echo "$NODE_HOSTNAME" > "$chroot_folder/etc/hostname"

mount --rbind /dev "$chroot_folder/dev"
mount --make-rslave "$chroot_folder/dev"
mount -t proc /proc "$chroot_folder/proc"
mount --rbind /sys "$chroot_folder/sys"
mount --make-rslave "$chroot_folder/sys"
mount --rbind /tmp "$chroot_folder/tmp"
mount --bind /run "$chroot_folder/run"
cp --dereference /etc/resolv.conf "$chroot_folder/etc/"

chroot "$chroot_folder" apt update
chroot "$chroot_folder" apt modernize-sources -y


# imposta hostname, timezone e locale italiano
echo "$NODE_HOSTNAME" > "$chroot_folder/etc/hostname"
ln -sf "$chroot_folder/usr/share/zoneinfo/$TIMEZONE" "$chroot_folder/etc/localtime"
chroot "$chroot_folder" apt install -y locales
cat << EOF > "$chroot_folder"/etc/locale.gen
it_IT.UTF-8 UTF-8
EOF
chroot "$chroot_folder" locale-gen
chroot "$chroot_folder" update-locale LANG=it_IT.UTF-8


# generazione e installazione chiavi secure boot
sb_folder="$chroot_folder/etc/secureboot/keys"
mkdir -p "$sb_folder"

for cert in PK KEK db; do
  openssl req -new -x509 -newkey rsa:4096 -days 36500 -sha256 -nodes \
    -subj "/CN=$NODE_HOSTNAME $cert/" \
    -keyout "$sb_folder/$cert.key" \
    -out "$sb_folder/$cert.crt"
  cert-to-efi-sig-list "$sb_folder/$cert.crt" "$sb_folder/$cert.esl"
done
touch "$sb_folder/dbx.esl"

for cert in PK KEK db dbx; do
  mkdir -p "$sb_folder/$cert"
done

sign-efi-sig-list -k "$sb_folder/PK.key" -c "$sb_folder/PK.crt" PK "$sb_folder/PK.esl" "$sb_folder/PK/PK.auth"
sign-efi-sig-list -k "$sb_folder/PK.key" -c "$sb_folder/PK.crt" KEK "$sb_folder/KEK.esl" "$sb_folder/KEK/KEK.auth"
guid=$(uuidgen)
sign-efi-sig-list -k "$sb_folder/KEK.key" -c "$sb_folder/KEK.crt" "$guid" "$sb_folder/db.esl" "$sb_folder/db/db.auth"
sign-efi-sig-list -k "$sb_folder/KEK.key" -c "$sb_folder/KEK.crt" "$guid" "$sb_folder/dbx.esl" "$sb_folder/dbx/dbx.auth"

for cert in PK KEK db dbx; do
  chattr -f -i "/sys/firmware/efi/efivars/${cert}"*
done
sbkeysync --keystore "$sb_folder" --verbose
efi-updatevar -f "$sb_folder/PK/PK.auth" PK


# preparazione fstab e configurazione Dracut
target_esp_uuid=$( blkid | grep "$target_esp" | grep -oP '(?<= UUID=")[A-Za-z0-9-]+' )
target_luks_uuid=$( blkid | grep "$target_luks"| grep -oP '(?<= UUID=")[A-Za-z0-9-]+' )
target_root_uuid=$( blkid | grep /dev/mapper/luks_root | grep -oP '(?<= UUID=")[A-Za-z0-9-]+' )

cat << EOF > "$chroot_folder/etc/fstab"
UUID=$target_root_uuid  /          ext4  defaults,noatime,discard 0 1
UUID=$target_esp_uuid   /boot/efi  vfat  defaults,noatime,discard 0 2
EOF

cat << EOF > "$chroot_folder/etc/crypttab"
luks_root  UUID=$target_root_uuid  none  luks
EOF


# installazione script per configurare utilizzo UKI generato tramite Dracut
mkdir -p "$chroot_folder/boot/efi/EFI/Linux"
mkdir -p "$chroot_folder/etc/kernel/postinst.d"
mkdir -p "$chroot_folder/etc/kernel/postrm.d"

cp debian-uki-setup/uki-gen "$chroot_folder/etc/kernel/postinst.d/za-uki-gen"
sed -i "s/###target_luks_uuid###/$target_luks_uuid/g" "$chroot_folder/etc/kernel/postinst.d/za-uki-gen"
sed -i "s/###target_root_uuid###/$target_root_uuid/g" "$chroot_folder/etc/kernel/postinst.d/za-uki-gen"
chmod 744 "$chroot_folder/etc/kernel/postinst.d/za-uki-gen"

cp debian-uki-setup/uki-sign "$chroot_folder/etc/kernel/postinst.d/zb-sign-uki"
chmod 744 "$chroot_folder/etc/kernel/postinst.d/zb-sign-uki"

cp debian-uki-setup/uki-boot-update "$chroot_folder/etc/kernel/postinst.d/zc-uki-boot-update"
chmod 744 "$chroot_folder/etc/kernel/postinst.d/zc-uki-boot-update"

mkdir -p "$chroot_folder/usr/local/bin"
cp debian-uki-setup/tpm2-enroll-uki "$chroot_folder/usr/local/bin/"
chmod 744 "$chroot_folder/etc/kernel/postinst.d/tpm2-enroll-uki"

# configura diversioni con dpkg-divert per impedire la generazione dell'initrd di default
#chroot "$chroot_folder" dpkg-divert --local --rename --add /etc/kernel/postinst.d/dracut
#chroot "$chroot_folder" dpkg-divert --local --rename --add /etc/kernel/postrm.d/dracut


# installazione pacchetti di sistema richiesti
DEBIAN_FRONTEND=noninteractive chroot "$chroot_folder" apt install -y intel-microcode efibootmgr systemd-cryptsetup tpm2-tools systemd-boot-efi sbsigntool efitools dracut linux-image-amd64 nano curl jq


# imposta password di root
printf '%s' "root:${ROOT_PASSWORD}" | chroot "$chroot_folder" chpasswd


# installa sshd e configura chiavi utente root
chroot "$chroot_folder" apt install -y ssh
mkdir -p "$chroot_folder/root/.ssh"
printf '%s' "$ROOT_PUBKEY" > "$chroot_folder/root/.ssh/authorized_keys"
chmod 600 -R "$chroot_folder/root/.ssh"
chroot "$chroot_folder" systemctl enable ssh


# configurazione networkd
cp network/*.network "$chroot_folder/etc/systemd/network/"
chmod 644 "$chroot_folder/etc/systemd/network/"*.network
chroot "$chroot_folder" systemctl enable systemd-networkd
chroot "$chroot_folder" systemctl disable systemd-networkd-wait-online


# configurazione iwd
chroot "$chroot_folder" apt install -y firmware-iwlwifi iwd
mkdir -p "$chroot_folder/var/lib/iwd"
cat <<EOF > "$chroot_folder/var/lib/iwd/${WIFI_SSID}.psk"
[Security]
Passphrase=$WIFI_PASSPHRASE
EOF
chroot "$chroot_folder" systemctl enable iwd


# configurazione resolved
chroot "$chroot_folder" apt install -y systemd-resolved
cp network/resolved.conf "$chroot_folder/etc/systemd/"
chmod 644 "$chroot_folder/etc/systemd/resolved.conf"
chroot "$chroot_folder" ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
chroot "$chroot_folder" systemctl enable systemd-resolved


# configurazione ntp
DEBIAN_FRONTEND=noninteractive chroot "$chroot_folder" apt install -y chrony
cp network/chrony.conf "$chroot_folder/etc/chrony/"
chmod 644 "$chroot_folder/etc/chrony/chrony.conf"
chroot "$chroot_folder" systemctl enable chrony


# configurazione regole nftables
mkdir -p "$chroot_folder/usr/local/lib/nft-input-rules"
chmod 700 "$chroot_folder/usr/local/lib/nft-input-rules"
cp nft-rules-setup/nft-input-rules.* "$chroot_folder/usr/local/lib/nft-input-rules"

mkdir -p "$chroot_folder/usr/local/bin"
cp nft-rules-setup/nft-rules-setup "$chroot_folder/usr/local/bin/"
chmod 744 "$chroot_folder/usr/local/bin/nft-rules-setup"
chroot "$chroot_folder" /usr/local/bin/nft-rules-setup


# configurazione auto update dns
chroot "$chroot_folder" apt install -y curl jq
mkdir -p "$chroot_folder/usr/local/etc" "$chroot_folder/usr/local/bin"
printf '%s' "$INFOMANIAK_API_TOKEN" > "$chroot_folder/usr/local/etc/infomaniak_api_token"
chmod 400 "$chroot_folder/usr/local/etc/infomaniak_api_token"

cp dns-update-infomaniak/dns-update-infomaniak "$chroot_folder/usr/local/bin/"
chmod 744 "$chroot_folder/usr/local/bin/dns-update-infomaniak"

cp dns-update-infomaniak/dns-update-infomaniak.* "$chroot_folder/etc/systemd/system/"
chmod 644 "$chroot_folder/etc/systemd/system/"dns-update-infomaniak.*
chroot "$chroot_folder" systemctl daemon-reload
chroot "$chroot_folder" systemctl enable dns-update-infomaniak.timer


# configurazione acme.sh
chroot "$chroot_folder" apt install -y acme.sh
mkdir -p "$chroot_folder/usr/local/bin"
cp acme-sh-setup/acme-sh-setup "$chroot_folder/usr/local/bin/"
chmod 744 "$chroot_folder/usr/local/bin/acme-sh-setup"
cp acme-sh-setup/acme-sh.* "$chroot_folder/etc/systemd/system/"
chmod 644 "$chroot_folder/etc/systemd/system/acme-sh.*"

chroot "$chroot_folder" /usr/local/bin/acme-sh-setup
systemctl enable acme-sh.timer


# configurazione wireguard
chroot "$chroot_folder" apt install -y wireguard-tools
mkdir -p "$chroot_folder/usr/local/bin"
cp wg-config-generate/wg-config-generate "$chroot_folder/usr/local/bin/"

chmod 744 "$chroot_folder/usr/local/bin/wg-config-generate"
chroot "$chroot_folder" /usr/local/bin/wg-config-generate
