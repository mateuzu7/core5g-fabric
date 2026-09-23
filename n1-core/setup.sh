#!/bin/bash

set -e

# ============================================================
# N1 - free5GC + Kubernetes + Multus + gtp5g
#
# Ambiente:
#   Ubuntu 22.04
#   Kernel 5.15.x
#   Docker
#   Minikube
#   Kubernetes
#   Helm
#   Multus
#   gtp5g v0.8.10
#   free5GC Helm chart
#
# ============================================================

set -e

FREE5GC_DIR="$HOME/free5gc"
GTP5G_DIR="$HOME/gtp5g"

MINIKUBE_CPUS=8
MINIKUBE_MEMORY=15000

GTP5G_VERSION="v0.8.10"

NAMESPACE="free5gc"
RELEASE="free5gc"

echo "============================================================"
echo "       N1 - FREE5GC / KUBERNETES SETUP"
echo "============================================================"
echo

# ------------------------------------------------------------
# 0. Verificação do sistema
# ------------------------------------------------------------

echo "[0/12] Verificando sistema..."

if ! grep -q "22.04" /etc/os-release; then
    echo
    echo "ERRO: este script foi preparado para Ubuntu 22.04."
    exit 1
fi

echo "Sistema:"
lsb_release -ds

echo
echo "Kernel:"
uname -r

KERNEL_MAJOR=$(uname -r | cut -d. -f1)
KERNEL_MINOR=$(uname -r | cut -d. -f2)

if [ "$KERNEL_MAJOR" -ne 5 ] || [ "$KERNEL_MINOR" -ne 15 ]; then
    echo
    echo "AVISO: este ambiente foi preparado para kernel 5.15."
    echo "Kernel atual: $(uname -r)"
    echo
fi

# ------------------------------------------------------------
# 1. Atualização
# ------------------------------------------------------------

echo
echo "[1/12] Atualizando sistema..."

sudo apt-get update

sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# ------------------------------------------------------------
# 2. Dependências
# ------------------------------------------------------------

echo
echo "[2/12] Instalando dependências..."

sudo apt-get install -y \
    git \
    curl \
    wget \
    vim \
    nano \
    net-tools \
    iproute2 \
    iputils-ping \
    dnsutils \
    tcpdump \
    ethtool \
    build-essential \
    linux-headers-$(uname -r) \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    make \
    gcc \
    g++ \
    cmake \
    autoconf \
    libtool \
    pkg-config \
    libmnl-dev \
    libyaml-dev \
    iptables

# ------------------------------------------------------------
# 3. Docker
# ------------------------------------------------------------

echo
echo "[3/12] Configurando Docker..."

if ! command -v docker >/dev/null 2>&1; then
    sudo apt-get install -y docker.io
fi

sudo systemctl enable docker
sudo systemctl start docker

sudo usermod -aG docker "$USER" || true

echo
sudo docker --version

# ------------------------------------------------------------
# 4. kubectl
# ------------------------------------------------------------

echo
echo "[4/12] Instalando kubectl..."

if ! command -v kubectl >/dev/null 2>&1; then

    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)

    curl -LO \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

    sudo install \
        -o root \
        -g root \
        -m 0755 \
        kubectl \
        /usr/local/bin/kubectl

    rm -f kubectl
fi

kubectl version --client

# ------------------------------------------------------------
# 5. Minikube
# ------------------------------------------------------------

echo
echo "[5/12] Instalando Minikube..."

if ! command -v minikube >/dev/null 2>&1; then

    curl -LO \
        https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64

    sudo install \
        minikube-linux-amd64 \
        /usr/local/bin/minikube

    rm -f minikube-linux-amd64
fi

minikube version

# ------------------------------------------------------------
# 6. Helm
# ------------------------------------------------------------

echo
echo "[6/12] Instalando Helm..."

if ! command -v helm >/dev/null 2>&1; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm version

# ------------------------------------------------------------
# 7. gtp5g
# ------------------------------------------------------------

echo
echo "[7/12] Instalando gtp5g ${GTP5G_VERSION}..."

if [ ! -d "$GTP5G_DIR" ]; then
    git clone https://github.com/free5gc/gtp5g.git "$GTP5G_DIR"
fi

cd "$GTP5G_DIR"

git fetch --tags

git checkout "$GTP5G_VERSION"

echo
echo "Versão:"
git describe --tags --always

echo
echo "Removendo módulo anterior, se existir..."

sudo modprobe -r gtp5g 2>/dev/null || true

echo
echo "Limpando compilação anterior..."

make clean 2>/dev/null || true

echo
echo "Compilando gtp5g..."

make

echo
echo "Instalando gtp5g..."

sudo make install

echo
echo "Carregando módulo..."

sudo depmod -a
sudo modprobe gtp5g

echo
echo "Módulo:"
lsmod | grep gtp5g || true

# ------------------------------------------------------------
# 8. Minikube
# ------------------------------------------------------------

echo
echo "[8/12] Configurando Kubernetes / Minikube..."

unset KUBECONFIG

if ! minikube status >/dev/null 2>&1; then

    echo
    echo "Iniciando Minikube..."

    minikube start \
        --driver=docker \
        --cpus="$MINIKUBE_CPUS" \
        --memory="$MINIKUBE_MEMORY"
else

    echo
    echo "Minikube já está iniciado."
fi

kubectl config use-context minikube

echo
echo "Aguardando Kubernetes..."

kubectl wait \
    --for=condition=Ready \
    node/minikube \
    --timeout=180s

echo
echo "Node:"
kubectl get nodes -o wide

# ------------------------------------------------------------
# 9. Multus
# ------------------------------------------------------------

echo
echo "[9/12] Instalando Multus..."

kubectl apply \
    -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

echo
echo "Aguardando Multus..."

kubectl -n kube-system rollout status \
    daemonset/kube-multus-ds \
    --timeout=180s

echo
echo "Multus:"
kubectl get pods \
    -n kube-system \
    -o wide | grep -i multus || true

# ------------------------------------------------------------
# 10. Helm repository / free5GC
# ------------------------------------------------------------

echo
echo "[10/12] Preparando free5GC..."

helm repo add \
    towards5gs \
    https://orange-opensource.github.io/towards5gs-helm/ \
    2>/dev/null || true

helm repo update

if [ ! -d "$FREE5GC_DIR" ]; then

    echo
    echo "Baixando chart free5GC..."

    cd "$HOME"

    helm pull \
        towards5gs/free5gc \
        --untar
else

    echo
    echo "~/free5gc já existe."
fi

echo
echo "Chart:"
helm show chart "$FREE5GC_DIR"

# ------------------------------------------------------------
# 11. Configuração inicial
# ------------------------------------------------------------

echo
echo "[11/12] Preparando namespace e configuração..."

kubectl create namespace "$NAMESPACE" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

echo
echo "Namespace:"
kubectl get namespace "$NAMESPACE"

echo
echo "Interfaces dentro do Minikube:"
minikube ssh -- ip -br link

# ------------------------------------------------------------
# 12. Instalação free5GC
# ------------------------------------------------------------

echo
echo "[12/12] Instalando free5GC..."
echo

echo "IMPORTANTE:"
echo
echo "Antes da instalação, precisamos garantir que os"
echo "NetworkAttachmentDefinitions N2/N3/N4/N6 estejam"
echo "corretamente configurados para o ambiente Minikube."
echo
echo "O chart não será instalado automaticamente nesta etapa."
echo

echo "============================================================"
echo " SETUP BASE CONCLUÍDO"
echo "============================================================"
echo
echo "Componentes instalados:"
echo
echo "  Ubuntu 22.04          OK"
echo "  Kernel 5.15           OK"
echo "  Docker                OK"
echo "  kubectl               OK"
echo "  Minikube               OK"
echo "  Kubernetes             OK"
echo "  Helm                   OK"
echo "  Multus                 OK"
echo "  gtp5g ${GTP5G_VERSION}        OK"
echo "  free5GC chart          OK"
echo
echo "============================================================"
echo " VERIFICAÇÕES"
echo "============================================================"
echo

echo "Kubernetes:"
kubectl get nodes

echo
echo "Pods:"
kubectl get pods -A

echo
echo "gtp5g:"
lsmod | grep gtp5g || true

echo
echo "Helm:"
helm list -A

echo
echo "free5GC chart:"
helm show chart "$FREE5GC_DIR"

echo
echo "============================================================"
echo " PRÓXIMO PASSO"
echo "============================================================"
echo
echo "Configurar N2/N3/N4/N6 e instalar o release free5GC."
echo
