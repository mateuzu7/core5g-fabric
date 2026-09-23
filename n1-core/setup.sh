#!/bin/bash
set -e

echo "[1/7] A atualizar sistema e dependências..."
sudo apt-get update
sudo apt-get install -y git curl wget net-tools iproute2 build-essential linux-headers-$(uname -r) docker.io conntrack
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER" || true

echo "[2/7] A instalar módulo de kernel gtp5g v0.8.10..."
if [ ! -d "$HOME/gtp5g" ]; then
    git clone https://github.com/free5gc/gtp5g.git "$HOME/gtp5g"
fi
cd "$HOME/gtp5g"
git fetch --tags && git checkout v0.8.10
sudo modprobe -r gtp5g 2>/dev/null || true
make clean 2>/dev/null || true
make && sudo make install
sudo modprobe gtp5g

echo "[3/7] A instalar Minikube, kubectl e Helm..."
if ! command -v minikube >/dev/null 2>&1; then
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
fi
if ! command -v kubectl >/dev/null 2>&1; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
fi
if ! command -v helm >/dev/null 2>&1; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "[4/7] A iniciar Minikube (Bare-metal)..."
sudo minikube start --driver=none
mkdir -p $HOME/.kube
sudo cp /root/.kube/config $HOME/.kube/config
sudo chown -R $USER:$USER $HOME/.kube

echo "[5/7] A instalar Multus CNI..."
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml
sleep 10

echo "[6/7] A transferir chart do free5GC..."
helm repo add towards5gs https://raw.githubusercontent.com/Orange-OpenSource/towards5gs-helm/main/repo/
helm repo update
cd "$HOME"
if [ ! -d "$HOME/free5gc" ]; then
    helm pull towards5gs/free5gc --untar
fi

echo "[7/7] A instalar free5GC..."
MAIN_IF=$(ip route get 8.8.8.8 | awk -- '{printf $5}')
kubectl create namespace free5gc 2>/dev/null || true

helm install my-free5gc ./free5gc \
    --namespace free5gc \
    --set mongodb.image.tag=4.4.15 \
    --set global.n2network.masterIf=$MAIN_IF \
    --set global.n3network.masterIf=$MAIN_IF \
    --set global.n4network.masterIf=$MAIN_IF \
    --set global.n6network.masterIf=$MAIN_IF
