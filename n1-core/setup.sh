```bash
#!/bin/bash

set -e

echo "=========================================="
echo "  Setup N1 - free5GC + Kubernetes"
echo "=========================================="

# ------------------------------------------
# 1. Atualizar sistema
# ------------------------------------------

echo "[1/10] Atualizando sistema..."

sudo apt update
sudo apt upgrade -y

# ------------------------------------------
# 2. Dependências básicas
# ------------------------------------------

echo "[2/10] Instalando dependências..."

sudo apt install -y \
    git \
    curl \
    wget \
    vim \
    net-tools \
    iproute2 \
    build-essential \
    linux-headers-$(uname -r) \
    ca-certificates \
    gnupg \
    lsb-release

# ------------------------------------------
# 3. Docker
# ------------------------------------------

echo "[3/10] Instalando Docker..."

if ! command -v docker >/dev/null 2>&1; then
    sudo apt install -y docker.io
fi

sudo systemctl enable docker
sudo systemctl start docker

sudo usermod -aG docker "$USER" || true

echo "Docker instalado:"
sudo docker --version

# ------------------------------------------
# 4. kubectl
# ------------------------------------------

echo "[4/10] Instalando kubectl..."

if ! command -v kubectl >/dev/null 2>&1; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    rm -f kubectl
fi

kubectl version --client

# ------------------------------------------
# 5. Minikube
# ------------------------------------------

echo "[5/10] Instalando Minikube..."

if ! command -v minikube >/dev/null 2>&1; then
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64

    sudo install minikube-linux-amd64 /usr/local/bin/minikube

    rm -f minikube-linux-amd64
fi

minikube version

# ------------------------------------------
# 6. Helm
# ------------------------------------------

echo "[6/10] Instalando Helm..."

if ! command -v helm >/dev/null 2>&1; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm version

# ------------------------------------------
# 7. gtp5g
# ------------------------------------------

echo "[7/10] Instalando gtp5g..."

if [ ! -d "$HOME/gtp5g" ]; then
    git clone https://github.com/free5gc/gtp5g.git "$HOME/gtp5g"
fi

cd "$HOME/gtp5g"

# Versão compatível com free5GC v3.3.0
git fetch --tags
git checkout v0.8.10

make clean || true
make
sudo make install

sudo modprobe gtp5g

echo "gtp5g:"
lsmod | grep gtp5g || true

# ------------------------------------------
# 8. Multus CNI
# ------------------------------------------

echo "[8/10] Preparando Kubernetes/Multus..."

# Iniciar Minikube usando Docker
if ! minikube status >/dev/null 2>&1; then
    minikube start \
        --driver=docker \
        --cpus=4 \
        --memory=12000
fi

# Garantir contexto correto
unset KUBECONFIG

kubectl config use-context minikube

echo "Kubernetes:"
kubectl get nodes

# Instalar Multus
kubectl apply -f \
    https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

echo "Aguardando Multus..."

kubectl -n kube-system rollout status \
    daemonset/kube-multus-ds \
    --timeout=180s || true

# ------------------------------------------
# 9. Repositório Helm do free5GC
# ------------------------------------------

echo "[9/10] Preparando Helm..."

helm repo add towards5gs \
    https://orange-opensource.github.io/towards5gs-helm/

helm repo update

# ------------------------------------------
# 10. Diretório do free5GC
# ------------------------------------------

echo "[10/10] Preparando free5GC..."

cd "$HOME"

if [ ! -d "$HOME/free5gc" ]; then
    helm pull towards5gs/free5gc --untar
fi

echo ""
echo "=========================================="
echo " Setup concluído!"
echo "=========================================="
echo ""
echo "Docker:"
sudo docker --version
echo ""
echo "kubectl:"
kubectl version --client
echo ""
echo "Minikube:"
minikube version
echo ""
echo "Helm:"
helm version
echo ""
echo "gtp5g:"
lsmod | grep gtp5g || echo "Módulo gtp5g não carregado"
echo ""
echo "Kubernetes:"
kubectl get nodes
echo ""
echo "free5GC:"
ls -ld "$HOME/free5gc" 2>/dev/null || true
echo ""
echo "IMPORTANTE:"
echo "Se este for o primeiro login após adicionar o usuário"
echo "ao grupo docker, execute:"
echo ""
echo "    newgrp docker"
echo ""
echo "Depois confira:"
echo ""
echo "    docker ps"
echo "    kubectl get nodes"
echo ""
```
