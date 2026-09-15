
#!/usr/bin/env bash
# n1-core/setup.sh — VM "Core" (N1): Kubernetes (minikube) + free5GC via Helm
#
# Baseado no tutorial "Introduza o Kubernetes e implante o free5GC no
# Kubernetes com o helm" (free5GC.org) e em
# https://github.com/Orange-OpenSource/towards5gs-helm
#
# Diferença em relação ao tutorial original: aqui só é instalado o chart do
# free5GC. O UERANSIM roda fora, nas VMs N2/N3, então o chart 'ueransim' do
# towards5gs-helm NÃO é instalado (evita gNB/UE duplicados dentro do cluster).
#
# Uso:
#   ./setup.sh
#   INSTALL_MONITORING=1 ./setup.sh     # também sobe Prometheus/Grafana
#   MASTER_IF=eth0 ./setup.sh           # força a interface (senão detecta sozinho)
#
set -euo pipefail

MASTER_IF="${MASTER_IF:-}"
INSTALL_MONITORING="${INSTALL_MONITORING:-0}"
GTP5G_TAG="v0.8.1"

log() { echo -e "\n[n1-core] $*"; }

# ---------------------------------------------------------------------------
log "Checando versão do kernel (UPF/gtp5g precisa de 5.0.0-23 genérico ou 5.4.x)..."
uname -r || true

log "Atualizando pacotes..."
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y curl wget apt-transport-https gcc make git

# ---------------------------------------------------------------------------
log "Instalando módulo de kernel gtp5g (${GTP5G_TAG})..."
if [ ! -d "$HOME/gtp5g" ]; then
  git clone -b "$GTP5G_TAG" https://github.com/free5gc/gtp5g.git "$HOME/gtp5g"
fi
cd "$HOME/gtp5g"
make
sudo make install

# ---------------------------------------------------------------------------
log "Instalando Docker..."
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt-get remove -y "$pkg" 2>/dev/null || true
done
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"

# ---------------------------------------------------------------------------
log "Instalando minikube..."
if ! command -v minikube &>/dev/null; then
  cd "$HOME"
  wget -q https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  sudo cp minikube-linux-amd64 /usr/local/bin/minikube
  sudo chmod +x /usr/local/bin/minikube
fi

log "Instalando kubectl..."
if ! command -v kubectl &>/dev/null; then
  cd "$HOME"
  KUBECTL_VER="$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)"
  curl -LO "https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VER}/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
fi

log "Instalando Helm..."
if ! command -v helm &>/dev/null; then
  cd "$HOME"
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh
fi

log "Clonando multus-cni..."
if [ ! -d "$HOME/multus-cni" ]; then
  git clone https://github.com/k8snetworkplumbingwg/multus-cni.git "$HOME/multus-cni"
fi

# ---------------------------------------------------------------------------
log "Subindo minikube com driver docker + CNI flannel (via grupo docker, sem precisar relogar)..."
sg docker -c "minikube start --driver=docker --cpus=4 --memory=8g --disk-size=20g --cni=flannel"
minikube status

log "Aplicando Multus-CNI..."
cd "$HOME/multus-cni"
cat ./deployments/multus-daemonset.yml | kubectl apply -f -

# ---------------------------------------------------------------------------
if [ -z "$MASTER_IF" ]; then
  MASTER_IF="$(ip route show default | awk '/default/ {print $5; exit}')"
  log "MASTER_IF não informado — detectado automaticamente: ${MASTER_IF:-<não encontrado>}"
fi
if [ -z "$MASTER_IF" ]; then
  log "AVISO: não consegui detectar a interface de rede. Defina MASTER_IF manualmente e rode de novo,"
  log "ou ajuste os valores abaixo direto no comando helm install."
fi

log "Clonando towards5gs-helm e instalando o free5GC (sem o chart ueransim)..."
kubectl create ns free5gc 2>/dev/null || log "namespace free5gc já existe"
if [ ! -d "$HOME/towards5gs-helm" ]; then
  git clone https://github.com/Orange-OpenSource/towards5gs-helm.git "$HOME/towards5gs-helm"
fi
cd "$HOME/towards5gs-helm/charts/"

helm -n free5gc install free5gc-v1 ./free5gc/ \
  --set global.n2network.masterIf="${MASTER_IF}" \
  --set global.n3network.masterIf="${MASTER_IF}" \
  --set global.n4network.masterIf="${MASTER_IF}" \
  --set global.n6network.masterIf="${MASTER_IF}" \
  --set global.n9network.masterIf="${MASTER_IF}"

log "Aguardando pods do free5gc subirem (Ctrl+C p/ sair do watch quando estiver tudo Running)..."
watch kubectl get pods -n free5gc || true

# ---------------------------------------------------------------------------
if [ "$INSTALL_MONITORING" = "1" ]; then
  log "Instalando Prometheus + Grafana (kube-prometheus-stack)..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update
  kubectl create namespace prometheus 2>/dev/null || log "namespace prometheus já existe"
  helm install prometheus prometheus-community/kube-prometheus-stack -n prometheus
  log "Grafana: kubectl port-forward -n prometheus svc/prometheus-grafana 8080:80 (login admin / prom-operator)"
fi

# ---------------------------------------------------------------------------
cat <<EOF

[n1-core] Setup concluído.

WebConsole do free5GC (login admin / free5gc):
  kubectl port-forward --namespace free5gc svc/webui-service 5000:5000
  # de fora da VM: ssh -L localhost:5000:localhost:5000 ubuntu@<IP da N1 no FABRIC>

Cadastre no WebConsole os SUPIs que você configurou nos UEs do N2/N3
(imsi-208930000000002 e imsi-208930000000003, se você usou os valores
padrão dos scripts n2-ueransim/setup.sh e n3-client/setup.sh).

Lembrete: essa VM expira em 24h no FABRIC — depois que confirmar que
'kubectl get pods -n free5gc' está tudo Running, considere salvar uma
imagem/snapshot da VM (se o FABRIC permitir) pra não repetir esse setup.
EOF
