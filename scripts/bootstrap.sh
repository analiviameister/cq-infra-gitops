#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-local-lab}"
KIND_CONFIG="${KIND_CONFIG:-./kind/kind-config.yaml}"
ARGOCD_NAMESPACE="argocd"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ========================
# Utils
# ========================

log() {
  echo
  echo "====> $1"
}

detect_os() {
  OS="$(uname | tr '[:upper:]' '[:lower:]')"
}

ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "⚠️  '$1' não encontrado. Instalando..."
    "$2"
  else
    echo "✔ $1 já instalado"
  fi
}

# ========================
# Installers
# ========================

install_kind() {
  if command -v brew >/dev/null 2>&1 && brew --version >/dev/null 2>&1; then
    echo "Usando brew para instalar kind"
    brew install kind
  else
    echo "Instalando kind via curl"

    ARCH=$(uname -m)
    TMP_KIND="/tmp/kind-bin"

    if [[ "$ARCH" == "arm64" ]]; then
      KIND_BINARY="kind-darwin-arm64"
    else
      KIND_BINARY="kind-darwin-amd64"
    fi

    curl -Lo "$TMP_KIND" "https://kind.sigs.k8s.io/dl/latest/${KIND_BINARY}"
    chmod +x "$TMP_KIND"
    sudo mv "$TMP_KIND" /usr/local/bin/kind
  fi
}

install_kubectl() {
  if command -v brew >/dev/null 2>&1; then
    echo "Usando brew para instalar kubectl"
    brew install kubectl
  else
    echo "Instalando kubectl via curl"
    curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
  fi
}

install_helm() {
  if command -v brew >/dev/null 2>&1; then
    echo "Usando brew para instalar helm"
    brew install helm
  else
    echo "Instalando helm via script oficial"
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
}

# ========================
# Cluster
# ========================

create_cluster() {
  local config_file="$ROOT_DIR/${KIND_CONFIG#./}"

  if kind get clusters | grep -qx "$CLUSTER_NAME"; then
    log "Cluster '$CLUSTER_NAME' já existe"
  else
    log "Criando cluster kind"
    kind create cluster --name "$CLUSTER_NAME" --config "$config_file"
  fi
}

# ========================
# ArgoCD
# ========================

install_argocd() {
  log "Instalando Argo CD"

  kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -n "$ARGOCD_NAMESPACE" --server-side --force-conflicts \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  log "Aguardando Argo CD"

  kubectl rollout status deployment/argocd-server -n "$ARGOCD_NAMESPACE" --timeout=300s
}

# ========================
# Namespaces
# ========================

create_namespaces() {
  log "Criando namespaces"

  kubectl create namespace apps --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace infra --dry-run=client -o yaml | kubectl apply -f -
}

# ========================
# Argo Apps
# ========================

apply_argocd_apps() {
  log "Aplicando Applications do Argo CD"

  kubectl apply -f "$ROOT_DIR/argocd/apps"
}

# ========================
# Info final
# ========================

show_info() {
  log "Ambiente pronto"

  echo "Argo CD:"
  echo "kubectl port-forward svc/argocd-server -n argocd 8081:443"
  echo
  echo "Senha:"
  echo "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
  echo
  echo "Hosts:"
  echo "127.0.0.1 go.local"
  echo "127.0.0.1 python.local"
}

exec_argo_and_traefik() {

  log "Expondo ArgoCD"

  kubectl port-forward svc/argocd-server -n argocd 8081:443 > /dev/null 2>&1 &

  echo "Argo URL: https://localhost:8081 "
  echo "Argo User: admin"
  echo "Argo Password:" `kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo`

  echo ""
  echo "Aguarde..."
  echo ""
  sleep 60

  kubectl port-forward svc/traefik -n traefik 19080:80 > /dev/null 2>&1 &

  echo "echo "Urls prontas:""
  echo "http://go-server-time-api.127.0.0.1.nip.io:19080"
  echo "http://python-text-display-api.127.0.0.1.nip.io:19080"

}

# ========================
# Main
# ========================

main() {
  log "Verificando dependencias"

  detect_os

  if [[ "$OS" == "darwin" ]] && ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew não encontrado: https://brew.sh"
    exit 1
  fi

  ensure_command kind install_kind
  ensure_command kubectl install_kubectl
  ensure_command helm install_helm

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker não encontrado: https://docs.docker.com/get-docker/"
    exit 1
  fi

  create_cluster
  install_argocd
  create_namespaces
  apply_argocd_apps
  show_info
  exec_argo_and_traefik
}

main "$@"