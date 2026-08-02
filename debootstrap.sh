#!/bin/sh

set -xe

# verifica cartella esecuzione script
if [ "$(cd "$(dirname "$0")" && pwd)" != "$(pwd)" ]; then
    printf 'errore: eseguire lo script nella stessa cartella in cui risiede' >&2
    exit 1
fi


# verifica presenza comandi richiesti
for command in parted mmdebstrap; do
    if ! command -v "$command" > /dev/null; then
        printf 'errore: installare comando %s' "$command" >&2
        printf 'debian: apt install -y parted mmdebstrap' >&2
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
    --components="main non-free-firmware" \
    --skip=check/empty \
    trixie "$chroot_folder"
mkdir -p "$chroot_folder/boot/efi"
mount "$target_esp" "$chroot_folder/boot/efi"


# copia file environment
mkdir -p "$chroot_folder/usr/local/etc/env"
cp "env/$chosen_host.env.private" env/*.public "$chroot_folder/usr/local/etc/env/"


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


# imposta hostname, timezone, locale
chroot "$chroot_folder" apt install -y systemd locales-all
chroot "$chroot_folder" printf "keyboard-configuration keyboard-configuration/layout select us" | debconf-set-selections
chroot "$chroot_folder" printf "keyboard-configuration keyboard-configuration/model select pc105" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive chroot "$chroot_folder" apt install -y keyboard-configuration
#sed -Ei 's/.+(it_IT\.UTF-8 UTF-8)$/\1/' "$chroot_folder"/etc/locale.gen
#chroot "$chroot_folder" locale-gen
chroot "$chroot_folder" systemd-firstboot --force \
  --setup-machine-id \
  --locale=it_IT.UTF-8 \
  --timezone="$TIMEZONE" \
  --hostname="$NODE_HOSTNAME" \
  --root-password="$ROOT_PASSWORD"


# preparazione fstab e crypttab
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


# installazione pacchetti di sistema richiesti
chroot "$chroot_folder" apt install -y nano htop iputils-ping


# installa sshd e configura chiavi utente root
chroot "$chroot_folder" apt install -y ssh
mkdir -p "$chroot_folder/root/.ssh"
printf '%s' "$ROOT_PUBKEY" > "$chroot_folder/root/.ssh/authorized_keys"
chmod 600 -R "$chroot_folder/root/.ssh"
chroot "$chroot_folder" systemctl enable ssh


# configurazione iwd
chroot "$chroot_folder" apt install -y firmware-iwlwifi iwd
mkdir -p "$chroot_folder/var/lib/iwd"
cat <<EOF > "$chroot_folder/var/lib/iwd/${WIFI_SSID}.psk"
[Security]
Passphrase=$WIFI_PASSPHRASE
EOF
chroot "$chroot_folder" systemctl enable iwd


# funzione setup moduli automation
setup_module() {
    module="$1"

    mkdir -p "$chroot_folder/opt/automation/"
    cp -r "$module" "$chroot_folder/opt/automation/"
    chmod 700 "$chroot_folder/opt/automation/$module"
    chmod 600 "$chroot_folder/opt/automation/$module/"*
    chmod 700 "$chroot_folder/opt/automation/$module/install.sh"
    chroot "$chroot_folder" "/opt/automation/$module/install.sh"
}

setup_module setup-signed-uki
setup_module setup-efistub-boot
setup_module setup-networkd
setup_module setup-resolved
setup_module setup-chrony
setup_module setup-dns-infomaniak
setup_module setup-nft
setup_module setup-wg
setup_module setup-acme
setup_module setup-zram

umount -lR "$chroot_folder"
