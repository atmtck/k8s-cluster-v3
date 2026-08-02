#!/bin/sh

HOSTNAME=$( cat /etc/hostname )
[ -f "/usr/local/etc/env/$HOSTNAME.env.private" ] || exit 1

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

# installazione chiavi secure boot
apt install -y --no-install-recommends --no-install-suggests openssl sbsigntool efitools uuid-runtime

sb_folder=/etc/secureboot/keys
mkdir -p "$sb_folder"

for cert in PK KEK db; do
  openssl req -new -x509 -newkey rsa:4096 -days 36500 -sha256 -nodes \
    -subj "/CN=$HOSTNAME $cert/" \
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

# configurazione dracut
luks_uuid=$( blkid | grep 'PARTLABEL="ROOT"' | grep -oP '(?<= UUID=")[A-Za-z0-9-]+' )
root_uuid=$( blkid | grep /dev/mapper/luks_root | grep -oP '(?<= UUID=")[A-Za-z0-9-]+' )

mkdir -p /boot/efi/EFI/Linux
mkdir -p /etc/kernel/postinst.d
mkdir -p /etc/kernel/postrm.d

cp "$SCRIPT_DIR"/za-uki-gen /etc/kernel/postinst.d/za-uki-gen
sed -i "s/###luks_uuid###/$luks_uuid/g" /etc/kernel/postinst.d/za-uki-gen
sed -i "s/###root_uuid###/$root_uuid/g" /etc/kernel/postinst.d/za-uki-gen
chmod 744 /etc/kernel/postinst.d/za-uki-gen

cp "$SCRIPT_DIR"/zb-uki-sign /etc/kernel/postinst.d/zb-uki-sign
chmod 744 /etc/kernel/postinst.d/zb-uki-sign

# configurazione divert dpkg per evitare generazione initramfs default
dpkg-divert --local --rename --divert /etc/kernel/postinst.d/dracut.disabled /etc/kernel/postinst.d/dracut
dpkg-divert --local --rename --divert /etc/kernel/postrm.d/dracut.disabled /etc/kernel/postrm.d/dracut
mkdir -p /etc/kernel/postinst.d /etc/kernel/postrm.d
printf '%s\n%s' '#!/bin/sh' 'exit 0' > /etc/kernel/postinst.d/dracut
printf '%s\n%s' '#!/bin/sh' 'exit 0' > /etc/kernel/postrm.d/dracut
chmod +x /etc/kernel/postinst.d/dracut
chmod +x /etc/kernel/postrm.d/dracut

# installazione kernel
apt install -y intel-microcode systemd-cryptsetup tpm2-tools systemd-boot-efi dracut linux-image-amd64

# installazione script per enrollment tpm chiavi luks legate a stato secure boot
mkdir -p /usr/local/bin
cp "$SCRIPT_DIR"/tpm2-enroll-sb-keys /usr/local/bin/
chmod 744 /usr/local/bin/tpm2-enroll-sb-keys
