# syntax=docker/dockerfile:1.6
# Hermes Workspace — imagem de producao (fork doutortenente, ajustes Tijolao)
#
# Diferencas em relacao ao Dockerfile upstream:
#   1. ELECTRON_SKIP_BINARY_DOWNLOAD=1 no build: o app desktop nao e usado aqui,
#      e o postinstall do electron baixava ~150 MB a cada build.
#   2. O estagio de runtime passa a copiar swarm.yaml, assets/, scripts/ e agents/.
#      O servidor le esses caminhos a partir de process.cwd() (= /app):
#        - src/server/swarm-roster.ts        -> <cwd>/swarm.yaml
#        - src/server/mcp-presets-store.ts   -> <cwd>/assets/mcp-presets.seed.json
#        - src/routes/api/skills/hub-search.ts -> <cwd>/scripts/skills-search.py
#      Sem eles, Swarm / presets de MCP / busca de skills quebram em container.
#   3. /app/.runtime criado e com dono correto. O servidor grava ali
#      (tool-artifacts, sessoes locais, swarm-missions) e /app pertence ao root.
#
FROM tianon/gosu:1.17-bookworm AS gosu_source

# --- estagio de build --------------------------------------------------------
FROM node:22-slim AS build
# ELECTRON_SKIP_BINARY_DOWNLOAD: o app desktop nao e usado aqui; poupa ~150 MB
# de download em cada build.
# NODE_OPTIONS: o bundle arrasta three.js + monaco + shiki; o heap padrao do
# node nesta maquina (7,6 GB de RAM) fica perto de 2 GB e o vite build estoura.
ENV ELECTRON_SKIP_BINARY_DOWNLOAD=1 \
    NODE_OPTIONS=--max-old-space-size=4096
RUN corepack enable && apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app

# Instala deps (cache-friendly: so os manifests primeiro).
# pnpm-workspace.yaml carrega as aprovacoes de allowBuilds (electron/esbuild/...);
# precisa existir ou o pnpm 10+/11 aborta por causa de build scripts ignorados.
COPY package.json pnpm-lock.yaml* pnpm-workspace.yaml* .npmrc* ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build

# --- estagio de runtime ------------------------------------------------------
FROM node:22-slim
# Binarios que o servidor invoca via execFileSync. Faltando qualquer um, a
# funcionalidade correspondente falha em silencio:
#   python3  src/server/pty-helper.py              terminal PTY
#   sqlite3  src/server/kanban-backend.ts          Kanban ("spawnSync ENOENT")
#   tmux     src/routes/api/swarm-tmux-start.ts    Swarm (so o CLIENTE; o
#            src/server/swarm-notifications.ts     servidor roda no host)
#   git      src/routes/api/swarm-project.ts       status do repo do worker
#   lsof     src/routes/api/swarm-project.ts       cwd do processo do worker
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl tini python3 sqlite3 tmux git lsof \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r workspace && useradd -r -g workspace -u 10010 -m workspace

COPY --from=gosu_source /gosu /usr/local/bin/gosu

WORKDIR /app

# server-entry.js e o servidor HTTP Node que embrulha o fetch handler exportado
# por dist/server/server.js. Sem ele, `node dist/server/server.js` importa o
# modulo, roda o top-level e sai com codigo 0 — ver issue #129.
COPY --from=build --chown=workspace:workspace /app/dist ./dist
COPY --from=build --chown=workspace:workspace /app/node_modules ./node_modules
COPY --from=build --chown=workspace:workspace /app/package.json ./package.json
COPY --from=build --chown=workspace:workspace /app/server-entry.js ./server-entry.js
COPY --from=build --chown=workspace:workspace /app/skills ./skills
# lidos em runtime a partir de process.cwd() — ver cabecalho
COPY --from=build --chown=workspace:workspace /app/swarm.yaml ./swarm.yaml
COPY --from=build --chown=workspace:workspace /app/assets ./assets
COPY --from=build --chown=workspace:workspace /app/scripts ./scripts
COPY --from=build --chown=workspace:workspace /app/agents ./agents
COPY --chown=workspace:workspace docker/entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# estado gravavel do servidor (tool-artifacts, sessoes, swarm-missions)
RUN mkdir -p /app/.runtime && chown -R workspace:workspace /app/.runtime

ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0 \
    HERMES_API_URL=http://hermes-agent:8642

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3000/ >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["node", "--max-old-space-size=2048", "server-entry.js"]
