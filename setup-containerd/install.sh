#!/bin/sh

# installazione containerd
apt install -y --no-install-recommends --no-install-suggests apt-transport-https ca-certificates curl gpg
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docket-apt-keyring.gpg
cat <<EOF > /etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $( . /etc/os-release && echo "$VERSION_CODENAME" )
Components: stable
Architectures: $( dpkg --print-architecture )
Signed-By: /etc/apt/keyrings/docket-apt-keyring.gpg
EOF

apt update
apt install -y --no-install-recommends --no-install-suggests containernetworking-plugins containerd.io cri-tools
systemctl enable containerd

# abilitazione plugin cri
sed -i -E "s|(^disabled_plugins.+["cri"].*$)|#\1|g" /etc/containerd/config.toml
