#!/bin/bash
set -e

WORKSPACE_USER=workspace
WORKSPACE_GROUP=workspace
WORKSPACE_HOME="$(getent passwd "$WORKSPACE_USER" | cut -d: -f6)"
TARGET_UID="${HERMES_UID:-}"
TARGET_GID="${HERMES_GID:-}"

fix_owner_if_needed() {
  local path="$1"
  if [ ! -e "$path" ]; then
    return
  fi

  local actual_uid
  actual_uid=$(id -u "$WORKSPACE_USER")
  local current_uid
  current_uid=$(stat -c %u "$path" 2>/dev/null || true)
  if [ -n "$current_uid" ] && [ "$current_uid" != "$actual_uid" ]; then
    chown -R "$WORKSPACE_USER:$WORKSPACE_GROUP" "$path" 2>/dev/null || \
      echo "Warning: chown failed for $path (rootless container or restricted mount?) — continuing anyway"
  fi
}

if [ "$(id -u)" = "0" ]; then
  current_uid=$(id -u "$WORKSPACE_USER")
  current_gid=$(id -g "$WORKSPACE_USER")

  if [ -n "$TARGET_GID" ] && [ "$TARGET_GID" != "$current_gid" ]; then
    echo "Changing workspace GID to $TARGET_GID"
    groupmod -o -g "$TARGET_GID" "$WORKSPACE_GROUP" 2>/dev/null || true
  fi

  if [ -n "$TARGET_UID" ] && [ "$TARGET_UID" != "$current_uid" ]; then
    echo "Changing workspace UID to $TARGET_UID"
    usermod -o -u "$TARGET_UID" "$WORKSPACE_USER"
  fi

  # HERMES_HOST_HOME reaponta o home do usuario no /etc/passwd. Necessario
  # porque `gosu` define HOME a partir do passwd e descarta o HOME do compose;
  # sem isso homedir() devolve /home/workspace e o Swarm procura os wrappers
  # em /home/workspace/.local/bin, que nao existe. Os caminhos resolvidos aqui
  # precisam ser validos no HOST tambem: e la que o servidor tmux executa.
  if [ -n "${HERMES_HOST_HOME:-}" ]; then
    echo "Pointing workspace home at $HERMES_HOST_HOME"
    usermod -d "$HERMES_HOST_HOME" "$WORKSPACE_USER"
    WORKSPACE_HOME="$HERMES_HOST_HOME"
  fi

  mkdir -p "$WORKSPACE_HOME/.hermes" /workspace /app/.runtime
  fix_owner_if_needed "$WORKSPACE_HOME"
  fix_owner_if_needed /workspace
  # /app/.runtime nasce no Dockerfile com o uid original do usuario workspace
  # (10010). Quando HERMES_UID troca esse uid, a pasta fica orfa e o servidor
  # nao grava mais nela: "EACCES ... /app/.runtime/swarm-missions.json".
  # Atinge Conductor/Swarm e tool-artifacts.
  fix_owner_if_needed /app/.runtime

  echo "Dropping root privileges"
  exec gosu "$WORKSPACE_USER:$WORKSPACE_GROUP" "$0" "$@"
fi

exec "$@"
