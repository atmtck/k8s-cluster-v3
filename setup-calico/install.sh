#!/bin/sh

HOSTNAME=$( cat /etc/hostname )
[ -f "/usr/local/etc/env/$HOSTNAME.env.private" ] || exit 1

# verifica path di esecuzione
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

# creazione sezione ipPools per ogni nodo
mkdir -p /etc/kubernetes
host_number=$( find /usr/local/etc/env/ -name '*.public' -type f | wc -l )
awk -v N=$host_number '/- cidr:/,/nodeSelector:/{b=b $0 "\n"; if(/nodeSelector:/){while(N--) printf "%s",b; b=""}; next} 1' "${SCRIPT_DIR}/calico-deployment.yaml" > /etc/kubernetes/calico-deployment.yaml
chmod 600 /etc/kubernetes/calico-deployment.yaml

# riempimento dati sezione ipPools per ogni nodo
for host_public_config in $( find /usr/local/etc/env/ -name '*.public' -type f | sort ); do

  . "$host_public_config"
  pod_network_cidr="$POD_SUBNET"
  pod_network_mask=$( printf '%s' "$POD_SUBNET" | cut -d '/' -f 2 )

  sed -i "0,/###pod_network_cidr###/ s|###pod_network_cidr###|$pod_network_cidr|" /etc/kubernetes/calico-deployment.yaml
  sed -i "0,/###pod_network_mask###/ s/###pod_network_mask###/$pod_network_mask/" /etc/kubernetes/calico-deployment.yaml
  sed -i "0,/###hostname###/         s/###hostname###/$NODE_HOSTNAME/"            /etc/kubernetes/calico-deployment.yaml
done
