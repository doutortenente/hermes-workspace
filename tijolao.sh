#!/usr/bin/env bash
# Controle da stack Hermes no Tijolao.
# Uso:  ~/hermes-workspace/tijolao.sh <comando>
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE=(docker compose -f "$DIR/docker-compose.tijolao.yml")
UI="http://localhost:3000"

cd "$DIR"

uso() {
  echo "tijolao.sh — stack Hermes (agent + workspace) em Docker"
  echo
  echo "  up          sobe a stack (constroi a imagem do workspace se faltar)"
  echo "  down        desliga a stack (os dados em ~/.hermes ficam)"
  echo "  restart     down + up"
  echo "  status      o que esta rodando, saude e portas"
  echo "  logs        log dos dois servicos, ao vivo (Ctrl+C sai)"
  echo "  logs agent  so o agent   |   logs ws   so o workspace"
  echo "  build       reconstroi a imagem do workspace a partir do codigo"
  echo "  update      puxa o upstream, rebaseia o branch tijolao e reconstroi"
  echo "  shell       abre um shell dentro do container do agent"
  echo "  ui          imprime o endereco da interface"
}

espera() {
  local url="$1" nome="$2" tentativas="${3:-60}" i
  for ((i=1; i<=tentativas; i++)); do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then
      echo "$nome OK"
      return 0
    fi
    sleep 2
  done
  echo "$nome NAO respondeu" >&2
  return 1
}

porta() {
  local url="$1" rotulo="$2" code
  code=$(curl -fsS -o /dev/null -w "%{http_code}" --max-time 4 "$url" 2>/dev/null) || code="sem resposta"
  printf "  %-22s %s\n" "$rotulo" "$code"
}

case "${1:-}" in
  up)
    "${COMPOSE[@]}" up -d --build
    echo
    echo "Subindo. Esperando ficar de pe..."
    espera http://127.0.0.1:8642/health "gateway 8642" 60 || true
    espera "$UI" "workspace 3000" 60 || {
      echo "A interface nao subiu. Veja:  $0 logs ws" >&2
      exit 1
    }
    echo
    echo "Pronto:  $UI"
    ;;
  down)
    "${COMPOSE[@]}" down
    ;;
  restart)
    "$0" down
    "$0" up
    ;;
  build)
    "${COMPOSE[@]}" build --pull
    ;;
  status)
    "${COMPOSE[@]}" ps
    echo
    echo "Saude (codigo HTTP):"
    porta http://127.0.0.1:8642/health        "gateway 8642"
    porta http://127.0.0.1:9119/api/status    "dashboard 9119"
    porta "$UI"                               "workspace 3000"
    porta http://127.0.0.1:20128/v1/models    "9Router 20128"
    ;;
  logs)
    case "${2:-}" in
      agent)        "${COMPOSE[@]}" logs -f --tail=120 hermes-agent ;;
      ws|workspace) "${COMPOSE[@]}" logs -f --tail=120 hermes-workspace ;;
      *)            "${COMPOSE[@]}" logs -f --tail=80 ;;
    esac
    ;;
  update)
    git fetch upstream
    git checkout main
    git merge --ff-only upstream/main
    git checkout tijolao
    git rebase main
    "${COMPOSE[@]}" build --pull
    "$0" restart
    ;;
  shell)
    docker exec -it hermes-agent bash
    ;;
  ui)
    echo "$UI"
    ;;
  ""|-h|--help|help)
    uso
    ;;
  *)
    echo "comando desconhecido: $1" >&2
    echo
    uso
    exit 2
    ;;
esac
