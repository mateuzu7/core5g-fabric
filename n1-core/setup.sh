
Claude terminou a resposta
O namespace free5gc sumiu — provavelmente foi porque o minikube foi reiniciado ou o namespace nunca persistiu de fato (o kubectl anterior tinha dito "already exists" baseado em cache antigo, ou o cluster resetou). De qualquer forma, fácil de resolver:

Executou um comando
bash
kubectl create ns free5gc
Também repara que o pod do Multus ainda estava Init:0/1 (não terminou de subir) quando você rodou o helm install — espera ele ficar 1/1 Running antes de instalar o free5GC:

bash
kubectl get pods -n kube-system | grep multus
Quando aparecer 1/1 Running, roda o namespace + helm install de novo:

bash
kubectl create ns free5gc
cd ~/towards5gs-helm/charts/
helm -n free5gc install free5gc-v1 ./free5gc/ --set global.n2network.masterIf=enp3s0 --set global.n3network.masterIf=enp3s0 --set global.n4network.masterIf=enp3s0 --set global.n6network.masterIf=enp3s0 --set global.n9network.masterIf=enp3s0
E acompanha:

bash
watch kubectl get pods -n free5gc
Me manda o resultado.

ubuntu@n1:~/towards5gs-helm/charts$ kubectl create ns free5gc
namespace/free5gc created
ubuntu@n1:~/towards5gs-helm/charts$ kubectl get pods -n kube-system | grep multus
kube-multus-ds-mnq5k               1/1     Running   0          94s
ubuntu@n1:~/towards5gs-helm/charts$ kubectl create ns free5gc
cd ~/towards5gs-helm/charts/
helm -n free5gc install free5gc-v1 ./free5gc/ --set global.n2network.masterIf=enp3s0 --set global.n3network.masterIf=enp3s0 --set global.n4network.masterIf=enp3s0 --set global.n6network.masterIf=enp3s0 --set global.n9network.masterIf=enp3s0
Error from server (AlreadyExists): namespaces "free5gc" already exists
NAME: free5gc-v1
LAST DEPLOYED: Thu Sep 17 01:36:29 2026
NAMESPACE: free5gc
STATUS: deployed
REVISION: 1
NOTES:
#
# Software Name : towards5gs-helm
# SPDX-FileCopyrightText: Copyright (c) 2021 Orange
# SPDX-License-Identifier: Apache-2.0
#
# This software is distributed under the Apache License 2.0,
# the text of which is available at https://github.com/Orange-OpenSource/towards5gs-helm/blob/main/LICENSE
# or see the "LICENSE" file for more details.
#
# Author: Abderaouf KHICHANE, Ilhem FAJJARI
# Software description: An open-source project providing Helm charts to deploy 5G components (Core + RAN) on top of Kubernetes
#
#
# Visit the project at https://github.com/Orange-OpenSource/towards5gs-helm
#

Get the list of created Pods by running: kubectl get pods --namespace free5gc -l "project="
Release notes (What's changed in this version):
- Fix TLS configuration for SBI communications
ubuntu@n1:~/towards5gs-helm/charts$ watch kubectl get pods -n free5gc
ubuntu@n1:~/towards5gs-helm/charts$ 

Every 2.0s: kubectl get pods -n free5gc                                                                                                        n1: Thu Sep 17 01:37:05 2026

NAME                                                    READY   STATUS              RESTARTS   AGE
free5gc-v1-free5gc-amf-amf-64fb7b849f-f9mdx             0/1     Init:0/1            0          35s
free5gc-v1-free5gc-ausf-ausf-6568c64d8-wjlfh            0/1     Init:0/1            0          35s
free5gc-v1-free5gc-dbpython-dbpython-59868d45b9-lb8qg   0/1     Init:0/1            0          35s
free5gc-v1-free5gc-nrf-nrf-6b4b8ffbc6-chn5f             0/1     Init:0/1            0          35s
free5gc-v1-free5gc-nssf-nssf-55879d59dd-9fhb7           0/1     Init:0/1            0          35s
free5gc-v1-free5gc-pcf-pcf-67457574d4-8b5nq             0/1     Init:0/1            0          35s
free5gc-v1-free5gc-smf-smf-57bd6544b6-9hbsx             0/1     Init:0/1            0          35s
free5gc-v1-free5gc-udm-udm-7bb586fc89-jj7fs             0/1     Init:0/1            0          35s
free5gc-v1-free5gc-udr-udr-6cfd84b65c-njhbt             0/1     Init:0/1            0          35s
free5gc-v1-free5gc-upf-upf-6c7b56fcc6-njgxm             0/1     ContainerCreating   0          35s
free5gc-v1-free5gc-webui-webui-588fc685c6-ff7xl         0/1     Init:0/1            0          35s
mongodb-0                                               0/1     ImagePullBackOff    0          35s

Deploying pods and diagnosing an image pull failure.
Deploying pods and diagnosing an image pull failure.
Progrediu bastante! A maioria dos pods está em Init:0/1 (normal, esperando as dependências), mas o mongodb-0 está em ImagePullBackOff — isso é problema, porque quase tudo (AMF, UDM, UDR, webui etc.) depende do banco Mongo pra sair do estado de inicialização.

Roda isso pra ver o motivo exato:

bash
kubectl describe pod mongodb-0 -n free5gc | tail -20
Provavelmente vai aparecer algo como rate limit, manifest unknown, ou image not found na seção de Events, no final da saída. Me manda o que aparecer aí que eu te ajudo a resolver (geralmente é ajuste de imagem/tag no values.yaml do chart, ou espera de rate-limit do Docker Hub).

ubuntu@n1:~/towards5gs-helm/charts$ kubectl describe pod mongodb-0 -n free5gc | tail -20
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              <none>
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:
  Type     Reason            Age                From               Message
  ----     ------            ----               ----               -------
  Warning  FailedScheduling  63s (x4 over 63s)  default-scheduler  0/1 nodes are available: pod has unbound immediate PersistentVolumeClaims. not found
  Normal   Scheduled         63s                default-scheduler  Successfully assigned free5gc/mongodb-0 to minikube
  Normal   AddedInterface    62s                multus             Add eth0 [10.244.0.6/24] from cbr0
  Normal   BackOff           18s (x2 over 47s)  kubelet            Back-off pulling image "docker.io/bitnami/mongodb:4.4.4-debian-10-r0"
  Warning  Failed            18s (x2 over 47s)  kubelet            Error: ImagePullBackOff
  Normal   Pulling           3s (x3 over 62s)   kubelet            Pulling image "docker.io/bitnami/mongodb:4.4.4-debian-10-r0"
  Warning  Failed            2s (x3 over 47s)   kubelet            Failed to pull image "docker.io/bitnami/mongodb:4.4.4-debian-10-r0": rpc error: code = NotFound desc = failed to pull and unpack image "docker.io/bitnami/mongodb:4.4.4-debian-10-r0": failed to resolve reference "docker.io/bitnami/mongodb:4.4.4-debian-10-r0": docker.io/bitnami/mongodb:4.4.4-debian-10-r0: not found
  Warning  Failed            2s (x3 over 47s)   kubelet            Error: ErrImagePull
ubuntu@n1:~/towards5gs-helm/charts$

Executou 4 comandos, pesquisou na web
Achei a causa raiz: a Bitnami mudou a política de distribuição das imagens em 2025 e removeu as tags versionadas antigas do repositório bitnami/mongodb no Docker Hub — só sobrou a tag latest. As versões antigas (como a 4.4.4-debian-10-r0 que o chart do free5GC pede) foram movidas pra um repositório separado chamado bitnamilegacy, sem mais atualizações.

Fix: apontar o Helm pra essa imagem legada, no helm install:

Executou um comando
Primeiro desinstala essa release quebrada:

bash
helm uninstall free5gc-v1 -n free5gc
Depois reinstala apontando pra imagem legada da Bitnami (tag 4.4.15, a mais recente da série 4.4.x disponível lá):

bash
cd ~/towards5gs-helm/charts/
helm -n free5gc install free5gc-v1 ./free5gc/ --set global.n2network.masterIf=enp3s0 --set global.n3network.masterIf=enp3s0 --set global.n4network.masterIf=enp3s0 --set global.n6network.masterIf=enp3s0 --set global.n9network.masterIf=enp3s0 --set mongodb.image.repository=bitnamilegacy/mongodb --set mongodb.image.tag=4.4.15
E acompanha de novo:

bash
watch kubectl get pods -n free5gc
Se o mongodb-0 conseguir puxar essa imagem e ficar Running, o resto dos pods (que estavam presos em Init:0/1 esperando o Mongo) deve destravar em sequência. Me manda o resultado.

Editou um arquivo, memória atualizada e 2 ferramentas adicionais
Script atualizado no card acima. Enquanto isso, roda os dois comandos que passei (helm uninstall + helm install com o override do MongoDB) direto na sua VM e me manda o watch kubectl get pods -n free5gc.


Setup
SH 
ubuntu@n1:~/towards5gs-helm/charts$ helm uninstall free5gc-v1 -n free5gc
release "free5gc-v1" uninstalled
ubuntu@n1:~/towards5gs-helm/charts$ cd ~/towards5gs-helm/charts/
helm -n free5gc install free5gc-v1 ./free5gc/ --set global.n2network.masterIf=enp3s0 --set global.n3network.masterIf=enp3s0 --set global.n4network.masterIf=enp3s0 --set global.n6network.masterIf=enp3s0 --set global.n9network.masterIf=enp3s0 --set mongodb.image.repository=bitnamilegacy/mongodb --set mongodb.image.tag=4.4.15
NAME: free5gc-v1
LAST DEPLOYED: Thu Sep 17 01:38:48 2026
NAMESPACE: free5gc
STATUS: deployed
REVISION: 1
NOTES:
#
# Software Name : towards5gs-helm
# SPDX-FileCopyrightText: Copyright (c) 2021 Orange
# SPDX-License-Identifier: Apache-2.0
#
# This software is distributed under the Apache License 2.0,
# the text of which is available at https://github.com/Orange-OpenSource/towards5gs-helm/blob/main/LICENSE
# or see the "LICENSE" file for more details.
#
# Author: Abderaouf KHICHANE, Ilhem FAJJARI
# Software description: An open-source project providing Helm charts to deploy 5G components (Core + RAN) on top of Kubernetes
#
#
# Visit the project at https://github.com/Orange-OpenSource/towards5gs-helm
#

Get the list of created Pods by running: kubectl get pods --namespace free5gc -l "project="
Release notes (What's changed in this version):
- Fix TLS configuration for SBI communications
ubuntu@n1:~/towards5gs-helm/charts$ watch kubectl get pods -n free5gc
ubuntu@n1:~/towards5gs-helm/charts$ 

Every 2.0s: kubectl get pods -n free5gc                                                                                                        n1: Thu Sep 17 01:39:50 2026

NAME                                                    READY   STATUS              RESTARTS   AGE
free5gc-v1-free5gc-amf-amf-64fb7b849f-78t78             0/1     Init:0/1            0          62s
free5gc-v1-free5gc-ausf-ausf-6568c64d8-gmlnd            0/1     PodInitializing     0          62s
free5gc-v1-free5gc-dbpython-dbpython-59868d45b9-q8bj5   1/1     Running             0          62s
free5gc-v1-free5gc-nrf-nrf-6b4b8ffbc6-qkl2t             1/1     Running             0          62s
free5gc-v1-free5gc-nssf-nssf-55879d59dd-hhdrq           1/1     Running             0          62s
free5gc-v1-free5gc-pcf-pcf-67457574d4-bdhgx             1/1     Running             0          62s
free5gc-v1-free5gc-smf-smf-57bd6544b6-kplkh             0/1     Init:0/1            0          62s
free5gc-v1-free5gc-udm-udm-7bb586fc89-qwq72             0/1     PodInitializing     0          62s
free5gc-v1-free5gc-udr-udr-6cfd84b65c-b9zkr             0/1     PodInitializing     0          62s
free5gc-v1-free5gc-upf-upf-6c7b56fcc6-tlfb4             0/1     ContainerCreating   0          62s
free5gc-v1-free5gc-webui-webui-588fc685c6-kptg2         1/1     Running             0          62s
mongodb-0                                               1/1     Running             0          62s

Excelente — o fix do MongoDB funcionou. Repara na evolução:

mongodb-0 está 1/1 Running ✅ (era o bloqueador)
NRF, NSSF, PCF, dbpython, webui já estão 1/1 Running ✅
AMF, SMF, UDM, UDR, UPF ainda estão Init/PodInitializing/ContainerCreating — normal, é só a sequência de inicialização (muitos dependem do NRF já estar de pé, o que já aconteceu)
Isso é o comportamento esperado. Deixa o watch rodando mais uns 1-2 minutos. Se depois desse tempo algum pod ficar preso ou entrar em CrashLoopBackOff, me manda:

bash
kubectl logs <nome-do-pod> -n free5gc
do pod específico que travou. Caso contrário, quando tudo estiver 1/1 Running, o free5GC estará no ar e você pode seguir pro WebConsole (cadastro dos SUPIs) e depois pros scripts do N2/N3.

Memória atualizada
Deixa o watch rodando e me avisa quando estabilizar (ou se travar em algo).

Diagnosing a pod stuck between crash and completion states.
Diagnosing a pod stuck between crash and completion states.
O módulo carregou e agora ele nem trava com erro — só que o container terminou com Completed (exit code 0), ou seja, o processo do UPF rodou e saiu sozinho, sem travar, mas também sem ficar de pé como um daemon deveria. Isso é diferente do erro anterior. Vamos ver o log dessa execução:

Executou um comando
bash
kubectl logs free5gc-v1-free5gc-upf-upf-6c7b56fcc6-jk724 -n free5gc
Me manda a saída completa.

root@n1:/home/ubuntu/gtp5g# kubectl logs free5gc-v1-free5gc-upf-upf-6c7b56fcc6-jk724 -n free5gc
RTNETLINK answers: File exists
2026-09-17T02:16:10.841327203Z [INFO][UPF][Main] UPF version:  
    free5GC version: v3.3.0
    build time:      2023-06-20T08:00:43Z
    commit hash:     4474dc86
    commit time:     2023-06-08T03:37:39Z
    go version:      go1.17.8 linux/amd64
2026-09-17T02:16:10.841390473Z [INFO][UPF][CFG] Read config from [/free5gc/config//upfcfg.yaml]
2026-09-17T02:16:10.841648792Z [INFO][UPF][CFG] ==================================================
2026-09-17T02:16:10.841659012Z [INFO][UPF][CFG] (*factory.Config)(0xc0005aaaf0)({
    Version: (string) (len=5) "1.0.3",
    Description: (string) (len=31) "UPF initial local configuration",
    Pfcp: (*factory.Pfcp)(0xc00059b830)({
        Addr: (string) (len=13) "10.100.50.241",
        NodeID: (string) (len=13) "10.100.50.241",
        RetransTimeout: (time.Duration) 1s,
        MaxRetrans: (uint8) 3
    }),
    Gtpu: (*factory.Gtpu)(0xc00059b9e0)({
        Forwarder: (string) (len=5) "gtp5g",
        IfList: ([]factory.IfInfo) (len=1 cap=1) {
            (factory.IfInfo) {
                Addr: (string) (len=13) "10.100.50.233",
                Type: (string) (len=2) "N3",
                Name: (string) "",
                IfName: (string) "",
                MTU: (uint32) 0
            }
        }
    }),
    DnnList: ([]factory.DnnList) (len=1 cap=1) {
        (factory.DnnList) {
            Dnn: (string) (len=8) "internet",
            Cidr: (string) (len=11) "10.1.0.0/17",
            NatIfName: (string) (len=2) "n6"
        }
    },
    Logger: (*factory.Logger)(0xc0005a6da0)({
        Enable: (bool) true,
        Level: (string) (len=4) "info",
        ReportCaller: (bool) false
    })
})
2026-09-17T02:16:10.841662538Z [INFO][UPF][CFG] ==================================================
2026-09-17T02:16:10.841668090Z [INFO][UPF][Main] Log level is set to [info]
2026-09-17T02:16:10.841673279Z [INFO][UPF][Main] Report Caller is set to [false]
2026-09-17T02:16:10.841695661Z [INFO][UPF][Main] starting Gtpu Forwarder [gtp5g]
2026-09-17T02:16:10.841703987Z [INFO][UPF][Main] GTP Address: "10.100.50.233:2152"
2026-09-17T02:16:10.843851811Z [ERRO][UPF][Main] UPF Cli Run Error: open Gtp5g: open link: create: operation not supported
root@n1:/home/ubuntu/gtp5g#

Uncovering a version mismatch between UPF binary and kernel module.
Achei o motivo real, e é mais sério que módulo ausente: o próprio log mostra que essa é uma imagem antiga do free5GC (v3.3.0, de 2023) — towards5gs-helm usa uma imagem de UPF desatualizada, que espera uma versão antiga do gtp5g. A gente instalou gtp5g v0.10.2 (necessário pra compilar no kernel novo), mas o binário do UPF de 2023 não sabe falar com essa versão nova do módulo — daí o operation not supported mesmo com o módulo carregado.

Pesquisou na web
Isso é bem específico do kernel — vamos testar diretamente no host se o módulo consegue criar uma interface gtp5g, sem depender do Kubernetes/container:

Executou um comando
bash
ip link add gtp5g_test type gtp5g
ip link show gtp5g_test
ip link del gtp5g_test
Isso vai dizer se o problema é:

(A) no módulo/kernel em si (se der o mesmo erro Operation not supported aqui no host, fora do container) — nesse caso é uma incompatibilidade entre gtp5g v0.10.2 e o binário do UPF (que é de uma versão bem antiga do free5GC, v3.3.0 de 2023, empacotado pelo towards5gs-helm); ou
(B) específico do namespace de rede do pod/container (se funcionar aqui no host mas não dentro do pod)
Me manda o resultado.



Você está sem mensagens gratuitas até 03:20
Escreva uma mensagem…


Claude é uma IA e pode cometer erros. Por favor, verifique as fontes citadas.
Setup · SH
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
# v0.8.1 (do tutorial original) não compila em kernels >= 6.2 (falta suporte
# à API de netlink genérica nova). v0.8.5+ corrige isso; usamos a mais
# recente estável para máxima compatibilidade com kernels novos do FABRIC.
GTP5G_TAG="${GTP5G_TAG:-v0.10.2}"
 
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
if [ -d "$HOME/gtp5g" ]; then
  CURRENT_TAG="$(git -C "$HOME/gtp5g" describe --tags 2>/dev/null || echo '?')"
  if [ "$CURRENT_TAG" != "$GTP5G_TAG" ]; then
    log "Diretório ~/gtp5g existe com tag diferente (${CURRENT_TAG}) — refazendo clone limpo."
    rm -rf "$HOME/gtp5g"
  fi
fi
[ -d "$HOME/gtp5g" ] || git clone -b "$GTP5G_TAG" https://github.com/free5gc/gtp5g.git "$HOME/gtp5g"
cd "$HOME/gtp5g"
make clean 2>/dev/null || true
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
sg docker -c "minikube status" || log "AVISO: 'minikube status' fora do grupo docker pode acusar permission denied — isso é só do comando de status em si, não do cluster. Rode 'newgrp docker' numa sessão nova pra conferir sem o wrapper."
 
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
# A imagem bitnami/mongodb:4.4.4-debian-10-r0 (default do chart) foi removida
# do Docker Hub em 2025 — a Bitnami mudou tags antigas pro repo bitnamilegacy.
# Por isso apontamos explicitamente pra lá abaixo.
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
  --set global.n9network.masterIf="${MASTER_IF}" \
  --set mongodb.image.repository=bitnamilegacy/mongodb \
  --set mongodb.image.tag=4.4.15
 
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
 














