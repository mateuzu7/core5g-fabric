#!/bin/bash

set -e

echo "=========================================="
echo "   N1 - free5GC / Kubernetes Setup (K3s)"
echo "   Ubuntu 22.04 - Testbed FABRIC"
echo "=========================================="

echo
echo "[1/7] Atualizando sistema e dependências..."
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y git curl wget vim nano net-tools iproute2 iputils-ping build-essential linux-headers-$(uname -r) ca-certificates gnupg lsb-release software-properties-common

echo
echo "[2/7] Instalando Docker..."
if ! command -v docker >/dev/null 2>&1; then
    sudo apt-get install -y docker.io
fi
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER" || true

echo
echo "[3/7] Instalando módulo de kernel gtp5g v0.8.10..."
if [ ! -d "$HOME/gtp5g" ]; then
    git clone https://github.com/free5gc/gtp5g.git "$HOME/gtp5g"
fi
cd "$HOME/gtp5g"
git fetch --tags
git checkout v0.8.10
sudo modprobe -r gtp5g 2>/dev/null || true
make clean 2>/dev/null || true
make
sudo make install
sudo modprobe gtp5g
lsmod | grep gtp5g || echo "Falha ao carregar gtp5g"

echo
echo "[4/7] Instalando K3s (Kubernetes ultraleve) e Helm..."
if ! command -v k3s >/dev/null 2>&1; then
    curl -sfL https://get.k3s.io | sh -
fi
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc

if ! command -v helm >/dev/null 2>&1; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo
echo "[5/7] Instalando Multus CNI..."
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml
sleep 10

echo
echo "[6/7] Baixando chart do free5GC..."
helm repo add towards5gs https://orange-opensource.github.io/towards5gs-helm/ 2>/dev/null || true
helm repo update
cd "$HOME"
if [ ! -d "$HOME/free5gc" ]; then
    helm pull towards5gs/free5gc --untar
fi

echo
echo "[7/7] Descobrindo interface de rede e instalando free5GC..."
MAIN_IF=$(ip route get 8.8.8.8 | awk -- '{printf $5}')
echo "Interface física detectada: $MAIN_IF"

kubectl create namespace free5gc 2>/dev/null || true

helm install my-free5gc ./free5gc \
    --namespace free5gc \
    --set mongodb.image.tag=4.4.15 \
    --set global.n2network.masterIf=$MAIN_IF \
    --set global.n3network.masterIf=$MAIN_IF \
    --set global.n4network.masterIf=$MAIN_IF \
    --set global.n6network.masterIf=$MAIN_IF

echo
echo "=========================================="
echo "        SETUP CONCLUÍDO COM SUCESSO       "
echo "=========================================="
echo "Acompanhe a inicialização dos pods com o comando:"
echo "kubectl get pods -n free5gc -w"
