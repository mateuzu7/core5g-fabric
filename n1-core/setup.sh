```bash
#!/bin/bash

set -e

echo "=========================================="
echo "   N1 - free5GC / Kubernetes Setup"
echo "   Ubuntu 22.04"
echo "=========================================="

# ============================================================
# 0. Verificações
# ============================================================

echo
echo "[0/9] Verificando sistema..."

if ! grep -q "22.04" /etc/os-release; then
    echo "ERRO: este script foi preparado para Ubuntu 22.04."
    exit 1
fi

echo "Ubuntu:"
lsb_release -ds

echo
echo "Kernel:"
uname -r

# ============================================================
# 1. Atualização
# ============================================================

echo
echo "[1/9] Atualizando sistema..."

sudo apt update
sudo apt upgrade -y

# ============================================================
# 2. Dependências
# ============================================================

echo
echo "[2/9] Instalando dependências..."

sudo apt install -y \
    git \
    curl \
    wget \
    vim \
    nano \
    net-tools \
    iproute2 \
    iputils-ping \
    build-essential \
    linux-headers-$(uname -r) \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common

# ============================================================
# 3. Docker
# ============================================================

echo
echo "[3/9] Instalando Docker..."

if ! command -v docker >/dev/null 2>&1; then
    sudo apt install -y docker.io
fi

sudo systemctl enable docker
sudo systemctl start docker

sudo usermod -aG docker "$USER" || true

echo
echo "Docker instalado:"
sudo docker --version

# ============================================================
# 4. kubectl
# ============================================================

echo
echo "[4/9] Instalando kubectl..."

if ! command -v kubectl >/dev/null 2>&1; then

    KUBECTL_VERSION=$(curl -L -s \
        https://dl.k8s.io/release/stable.txt)

    curl -LO \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

    sudo install -o root -g root -m 0755 \
        kubectl /usr/local/bin/kubectl

    rm -f kubectl
fi

echo
kubectl version --client

# ============================================================
# 5. Minikube
# ============================================================

echo
echo "[5/9] Instalando Minikube..."

if ! command -v minikube >/dev/null 2>&1; then

    curl -LO \
        https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64

    sudo install \
        minikube-linux-amd64 \
        /usr/local/bin/minikube

    rm -f minikube-linux-amd64
fi

echo
minikube version

# ============================================================
# 6. Helm
# ============================================================

echo
echo "[6/9] Instalando Helm..."

if ! command -v helm >/dev/null 2>&1; then

    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
        | bash

fi

echo
helm version

# ============================================================
# 7. gtp5g
# ============================================================

echo
echo "[7/9] Instalando gtp5g v0.8.10..."

if [ ! -d "$HOME/gtp5g" ]; then

    git clone \
        https://github.com/free5gc/gtp5g.git \
        "$HOME/gtp5g"

fi

cd "$HOME/gtp5g"

git fetch --tags

git checkout v0.8.10

echo
echo "gtp5g:"
git describe --tags --always

# Remover módulo antigo, caso exista
sudo modprobe -r gtp5g 2>/dev/null || true

# Limpar compilação anterior
make clean 2>/dev/null || true

# Compilar
make

# Instalar
sudo make install

# Carregar módulo
sudo modprobe gtp5g

echo
echo "Módulo gtp5g:"
lsmod | grep gtp5g || true

# ============================================================
# 8. Minikube + Multus
# ============================================================

echo
echo "[8/9] Configurando Kubernetes..."

# Garantir que o KUBECONFIG antigo não interfira
unset KUBECONFIG

# Verificar se Minikube já está rodando
if ! minikube status >/dev/null 2>&1; then

    minikube start \
        --driver=docker \
        --cpus=4 \
        --memory=12000

fi

# Contexto
kubectl config use-context minikube

echo
echo "Nós Kubernetes:"
kubectl get nodes

# ------------------------------------------------------------
# Multus
# ------------------------------------------------------------

echo
echo "Instalando Multus CNI..."

kubectl apply -f \
    https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

echo
echo "Aguardando Multus..."

kubectl -n kube-system rollout status \
    daemonset/kube-multus-ds \
    --timeout=180s || true

# ============================================================
# 9. Helm + free5GC
# ============================================================

echo
echo "[9/9] Preparando free5GC..."

helm repo add towards5gs \
    https://orange-opensource.github.io/towards5gs-helm/ \
    2>/dev/null || true

helm repo update

cd "$HOME"

if [ ! -d "$HOME/free5gc" ]; then

    helm pull \
        towards5gs/free5gc \
        --untar

fi

# ============================================================
# Final
# ============================================================

echo
echo "=========================================="
echo "       SETUP CONCLUÍDO"
echo "=========================================="

echo
echo "Sistema:"
lsb_release -ds

echo
echo "Kernel:"
uname -r

echo
echo "Docker:"
sudo docker --version

echo
echo "kubectl:"
kubectl version --client

echo
echo "Minikube:"
minikube version

echo
echo "Helm:"
helm version

echo
echo "gtp5g:"
lsmod | grep gtp5g || echo "gtp5g não está carregado"

echo
echo "Kubernetes:"
kubectl get nodes

echo
echo "free5GC:"
if [ -d "$HOME/free5gc" ]; then
    echo "Diretório ~/free5gc encontrado."
else
    echo "Diretório ~/free5gc NÃO encontrado."
fi

echo
echo "=========================================="
echo " ATENÇÃO"
echo "=========================================="
echo
echo "Se esta for a primeira execução após adicionar"
echo "o usuário ao grupo docker, execute:"
echo
echo "    newgrp docker"
echo
echo "Depois teste:"
echo
echo "    docker ps"
echo "    kubectl get nodes"
echo
echo "=========================================="
```
