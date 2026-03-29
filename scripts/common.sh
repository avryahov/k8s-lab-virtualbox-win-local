#!/usr/bin/env bash
set -euo pipefail

HOSTNAME_VALUE="${1:?hostname is required}"
NODE_IP="${2:?node ip is required}"
HOST_ENTRIES="${3:?host entries are required}"
K8S_VERSION="${4:?kubernetes version is required}"
GATEWAY_IP="${5:?gateway ip is required}"
NODE_NAME="${6:?node name is required}"
NODE_PUBLIC_KEY="/vagrant/.vagrant/node-keys/${NODE_NAME}.ed25519.pub"

sudo hostnamectl set-hostname "${HOSTNAME_VALUE}"

{
  echo "127.0.0.1 localhost"
  echo "127.0.1.1 ${HOSTNAME_VALUE}"
  echo
  echo "::1 localhost ip6-localhost ip6-loopback"
  echo "ff02::1 ip6-allnodes"
  echo "ff02::2 ip6-allrouters"
  echo
  IFS=',' read -ra ENTRIES <<< "${HOST_ENTRIES}"
  for entry in "${ENTRIES[@]}"; do
    echo "${entry}"
  done
} | sudo tee /etc/hosts >/dev/null

sudo swapoff -a
sudo sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

sudo mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" | sudo tee /etc/apt/sources.list.d/docker.list

sudo apt-get update
sudo apt-get install -y containerd.io kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl enable containerd
sudo systemctl restart containerd

cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}
EOF

sudo systemctl enable kubelet

if [ -f "${NODE_PUBLIC_KEY}" ]; then
  install -d -m 700 /home/vagrant/.ssh
  touch /home/vagrant/.ssh/authorized_keys
  grep -qxF "$(cat "${NODE_PUBLIC_KEY}")" /home/vagrant/.ssh/authorized_keys || cat "${NODE_PUBLIC_KEY}" >> /home/vagrant/.ssh/authorized_keys
  chmod 600 /home/vagrant/.ssh/authorized_keys
  chown -R vagrant:vagrant /home/vagrant/.ssh
fi
