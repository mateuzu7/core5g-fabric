#!/bin/bash
sudo apt-get update && sudo apt-get upgrade -y

# 1. Instala dependências essenciais e módulo gtp5g
sudo apt-get install -y make gcc g++ cmake autoconf libtool pkg-config libmnl-dev libyaml-dev git
git clone https://github.com/free5gc/gtp5g.git
cd gtp5g
make
sudo make install
cd ..

# 2. Instala o K3s (Kubernetes ultraleve e rápido para VMs efêmeras)
curl -sfL https://get.k3s.io | sh -
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# 3. Instala o Helm (Gerenciador de pacotes do K8s)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 4. Adiciona o repositório e instala o free5GC
helm repo add towards5gs https://raw.githubusercontent.com/Orange-OpenSource/towards5gs-helm/main/repo/
helm repo update
kubectl create namespace free5gc
helm install my-free5gc towards5gs/free5gc -n free5gc
