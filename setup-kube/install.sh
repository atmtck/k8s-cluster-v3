#!/bin/sh

HOSTNAME=$( cat /etc/hostname )
[ -f "/usr/local/etc/env/$HOSTNAME.env.private" ] || exit 1

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

# abilitazione forwarding via sysctl
mkdir -p /etc/sysctl.d
cat <<"EOF" > /etc/sysctl.d/00-forwarding.conf
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl -p /etc/sysctl.d/00-forwarding.conf

# installazione containerd
apt install -y containernetworking-plugins containerd
systemctl enable --now containerd

# installazione kubeadm
apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
printf '%s' 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

# installazione haproxy
apt install -y haproxy
cp "$SCRIPT_DIR"/haproxy.cfg /etc/haproxy/

for host_public_config in $( find /usr/local/etc/env/ -name '*.public' -type f | sort ); do

  . "$host_public_config"
  printf '    server %s %s:6443\n' "$NODE_HOSTNAME" "$( printf '%s' "$WG_ADDRESS" | sed -E 's#/[0-9]+##' )" >> /etc/haproxy/haproxy.cfg
done

chmod 644 /etc/haproxy/haproxy.cfg
systemctl enable --now haproxy.service

# installazione config kubeadm
. "/usr/local/etc/env/$HOSTNAME.env.private"
. "/usr/local/etc/env/$HOSTNAME.env.public"
mkdir -p /etc/kubernetes

cp "$SCRIPT_DIR"/kubeadm.yaml /etc/kubernetes/
chmod 600 /etc/kubernetes/kubeadm.yaml

sed -i "s/###hostname###/$HOSTNAME/g"                                          /etc/kubernetes/kubeadm.yaml
sed -i "s/###wg_address###/$( printf '%s' "$WG_ADDRESS" | cut -d '/' -f 1 )/g" /etc/kubernetes/kubeadm.yaml
sed -i "s/###token###/$KUBEADM_TOKEN/g"                                        /etc/kubernetes/kubeadm.yaml
sed -i "s/###cert_key###/$KUBEADM_CERT_KEY/g"                                  /etc/kubernetes/kubeadm.yaml
