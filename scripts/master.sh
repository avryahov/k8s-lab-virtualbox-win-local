#!/usr/bin/env bash
set -euo pipefail

MASTER_IP="${1:?master ip is required}"
POD_CIDR="${2:?pod cidr is required}"
JOIN_FILE="/vagrant/join-command.sh"

if [ ! -f /etc/kubernetes/admin.conf ]; then
  sudo kubeadm init \
    --apiserver-advertise-address="${MASTER_IP}" \
    --pod-network-cidr="${POD_CIDR}"
fi

mkdir -p /home/vagrant/.kube
sudo cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/config

sudo kubeadm token create --print-join-command | sudo tee "${JOIN_FILE}" >/dev/null
sudo chmod +x "${JOIN_FILE}"

if ! kubectl --kubeconfig=/etc/kubernetes/admin.conf get daemonset kube-flannel-ds -n kube-flannel >/dev/null 2>&1; then
  kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
fi
