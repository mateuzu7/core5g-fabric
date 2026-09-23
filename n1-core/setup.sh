#!/bin/bash
#
# n1-core/setup.sh — VM "Core" (N1): Kubernetes (minikube --driver=none) + free5GC
#
# Correções em relação à versão anterior deste script:
#   - driver=none em vez de driver=docker: com docker, o node do K8s fica
#     isolado na rede interna do Docker (172.x) e as redes N2/N3/N4/N6/N9 do
#     free5GC ficam INACESSÍVEIS pras outras VMs do FABRIC, mesmo que os pods
#     subam "saudáveis". driver=none roda o kubelet direto no host, expondo a
#     interface física real.
#   - masterIf aplicado via --set global.<net>.masterIf=... (confirmado
#     funcionando), em vez de regex sobre o values.yaml (que procurava chaves
#     no lugar errado e não alterava nada).
#   - mongodb.image via --set (bitnamilegacy/mongodb, já que a Bitnami
#     removeu as tags antigas do Docker Hub em 2025), em vez de patch Python
#     frágil sobre o YAML.
#   - pré-requisitos do driver=none adicionados: crictl, cni-plugins
#     (containernetworking-plugins) e CRI habilitado no containerd (o
#     containerd que vem com o Docker geralmente desabilita o plugin CRI).
#   - chart do free5GC via git clone (testado de ponta a ponta), não via
#     helm repo customizado.
#   - roda inteiro como root (se chamado sem sudo, se re-executa sozinho).
#
set -euo pipefail

# Reexecuta como root se necessário — driver=none exige.
if [ "$EUID" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
fi

MINIKUBE_CPUS="${MINIKUBE_CPUS:-4}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-12000mb}"
GTP5G_VERSION="${GTP5G_VERSION:-v0.8.10}"
MASTER_IF="${MASTER_IF:-}"
WORKDIR="/home/${SUDO_USER:-ubuntu}/core5g-fabric/n1-core"

log() { echo -e "\n------------------------------------------------------------\n$1\n------------------------------------------------------------\n"; }
error_exit() { echo -e "\n=== ERRO ===\n$1\n"; exit 1; }

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ============================================================
log "[1/11] Verificando sistema"
uname -r
nproc
free -h

# ============================================================
log "[2/11] Instalando Docker"
if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi
docker --version

# ============================================================
log "[3/11] Habilitando o plugin CRI do containerd (necessário pro driver=none)"
containerd config default > /etc/containerd/config.toml
systemctl restart containerd

# ============================================================
log "[4/11] Instalando crictl e cni-plugins (pré-requisitos do driver=none)"
if ! command -v crictl >/dev/null 2>&1; then
  CRICTL_VERSION="v1.32.0"
  curl -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz" -o /tmp/crictl.tar.gz
  tar zxvf /tmp/crictl.tar.gz -C /usr/local/bin
  chmod +x /usr/local/bin/crictl
  rm -f /tmp/crictl.tar.gz
fi
crictl version

if [ ! -d /opt/cni/bin ] || [ -z "$(ls -A /opt/cni/bin 2>/dev/null)" ]; then
  CNI_PLUGIN_VERSION="v1.5.1"
  curl -LO "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGIN_VERSION}/cni-plugins-linux-amd64-${CNI_PLUGIN_VERSION}.tgz"
  mkdir -p /opt/cni/bin
  tar -xf "cni-plugins-linux-amd64-${CNI_PLUGIN_VERSION}.tgz" -C /opt/cni/bin
  rm -f "cni-plugins-linux-amd64-${CNI_PLUGIN_VERSION}.tgz"
fi
mkdir -p /etc/cni/net.d

# ============================================================
log "[5/11] Instalando kubectl, minikube e Helm"
if ! command -v kubectl >/dev/null 2>&1; then
  KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
fi
kubectl version --client

if ! command -v minikube >/dev/null 2>&1; then
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  install minikube-linux-amd64 /usr/local/bin/minikube
  rm -f minikube-linux-amd64
fi
minikube version

if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm version

# ============================================================
log "[6/11] Instalando módulo de kernel gtp5g ($GTP5G_VERSION)"
apt-get install -y git make gcc build-essential "linux-headers-$(uname -r)" libnl-3-dev libnl-genl-3-dev

GTP5G_DIR="/home/${SUDO_USER:-ubuntu}/gtp5g"
if [ -d "$GTP5G_DIR" ]; then
  cd "$GTP5G_DIR"
  git fetch --tags
  git checkout "$GTP5G_VERSION"
else
  git clone --branch "$GTP5G_VERSION" --depth 1 https://github.com/free5gc/gtp5g.git "$GTP5G_DIR"
  cd "$GTP5G_DIR"
fi

modprobe -r gtp5g 2>/dev/null || true
make clean 2>/dev/null || true
make
make install
depmod -a
modprobe gtp5g
lsmod | grep gtp5g || error_exit "O módulo gtp5g não carregou."

# ============================================================
log "[7/11] Limpando estado antigo do Kubernetes (se houver) e subindo minikube --driver=none"
if minikube status >/dev/null 2>&1; then
  echo "minikube já está de pé, pulando recriação."
else
  systemctl stop kubelet 2>/dev/null || true
  rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd /var/lib/minikube /root/.minikube /root/.kube
  minikube start --driver=none --cni=flannel
fi
minikube status
kubectl get nodes -o wide

# ============================================================
log "[8/11] Instalando Multus-CNI"
if ! kubectl get daemonset kube-multus-ds -n kube-system >/dev/null 2>&1; then
  kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
fi
echo "Aguardando Multus ficar Running..."
kubectl -n kube-system rollout status daemonset/kube-multus-ds --timeout=180s || true
kubectl get pods -n kube-system | grep -i multus

# ============================================================
log "[9/11] Detectando interface de rede do host"
if [ -z "$MASTER_IF" ]; then
  MASTER_IF="$(ip route show default | awk '/default/ {print $5; exit}')"
fi
echo "MASTER_IF = ${MASTER_IF:-<não detectado>}"
[ -n "$MASTER_IF" ] || error_exit "Não consegui detectar a interface de rede. Defina MASTER_IF=<interface> manualmente e rode de novo."

# ============================================================
log "[10/11] Instalando free5GC via towards5gs-helm (git clone)"
TOWARDS5GS_DIR="/home/${SUDO_USER:-ubuntu}/towards5gs-helm"
if [ ! -d "$TOWARDS5GS_DIR" ]; then
  git clone https://github.com/Orange-OpenSource/towards5gs-helm.git "$TOWARDS5GS_DIR"
fi
cd "$TOWARDS5GS_DIR/charts/"

kubectl create ns free5gc 2>/dev/null || echo "namespace free5gc já existe"

HELM_ARGS=(
  --set "global.n2network.masterIf=${MASTER_IF}"
  --set "global.n3network.masterIf=${MASTER_IF}"
  --set "global.n4network.masterIf=${MASTER_IF}"
  --set "global.n6network.masterIf=${MASTER_IF}"
  --set "global.n9network.masterIf=${MASTER_IF}"
  --set "mongodb.image.repository=bitnamilegacy/mongodb"
  --set "mongodb.image.tag=4.4.15"
)

if helm status free5gc-v1 -n free5gc >/dev/null 2>&1; then
  echo "free5gc-v1 já instalado, aplicando upgrade..."
  helm -n free5gc upgrade free5gc-v1 ./free5gc/ "${HELM_ARGS[@]}"
else
  helm -n free5gc install free5gc-v1 ./free5gc/ "${HELM_ARGS[@]}"
fi

# ============================================================
log "[11/11] Validando instalação"
echo "Aguardando pods subirem (60s)..."
sleep 60
kubectl get pods -n free5gc -o wide

echo
echo "Imagem do MongoDB realmente usada:"
kubectl get pod mongodb-0 -n free5gc -o jsonpath='{.spec.containers[0].image}' 2>/dev/null || true
echo

cat <<EOF

============================================================
SETUP CONCLUÍDO — próximos passos manuais
============================================================

1. Confira se todos os pods estão 1/1 Running:
     kubectl get pods -n free5gc

2. Se o UPF ficar em CrashLoopBackOff com erro de gtp5g, veja o log:
     kubectl logs -n free5gc \$(kubectl get pod -n free5gc -l nf-name=upf -o name) --previous

3. WebConsole (login admin / free5gc):
     kubectl port-forward --namespace free5gc svc/webui-service 5000:5000

4. IMPORTANTE: essa VM usa --driver=none, então TODO comando kubectl/helm
   daqui pra frente deve ser rodado como root (ou com sudo). Não mova
   ~/.kube nem ~/.minikube para outro usuário.

5. Se a VM reiniciar e o kernel atualizar sozinho (Ubuntu costuma avisar
   "Pending kernel upgrade"), o módulo gtp5g precisa ser recompilado pro
   kernel novo — rode este script de novo, ele detecta e refaz só essa parte.
EOF
