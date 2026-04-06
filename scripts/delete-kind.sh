#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-local-lab}"

log() {
  echo
  echo "====> $1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Erro: comando '$1' não encontrado"
    exit 1
  fi
}

delete_cluster() {
  if kind get clusters | grep -qx "$CLUSTER_NAME"; then
    log "Deletando cluster kind '$CLUSTER_NAME'"
    kind delete cluster --name "$CLUSTER_NAME"
  else
    log "Cluster '$CLUSTER_NAME' não existe"
  fi
}

cleanup_docker() {
  log "Limpando containers órfãos (opcional)"

  docker ps -a --filter "name=kind" -q | grep -q . && \
    docker rm -f $(docker ps -a --filter "name=kind" -q) || \
    echo "Nenhum container restante"
}

cleanup_images() {
  log "Removendo imagens locais (opcional)"

  docker images "go-time-api" -q | grep -q . && \
    docker rmi -f $(docker images "go-time-api" -q) || true

  docker images "python-text-api" -q | grep -q . && \
    docker rmi -f $(docker images "python-text-api" -q) || true
}

cleanup_volumes() {
  log "Removendo volumes não utilizados (opcional)"
  docker volume prune -f
}

main() {
  log "Iniciando destruição do ambiente"

  require_command kind
  require_command docker

  delete_cluster
  cleanup_docker
  cleanup_images
  cleanup_volumes

  log "Ambiente destruído 💀"
}

main "$@"