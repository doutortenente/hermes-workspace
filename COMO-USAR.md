# Hermes no Tijolão — como usar

Tudo passa por um script só: `~/hermes-workspace/tijolao.sh`

## Os 4 comandos que importam

| O que você quer | O que digitar |
|---|---|
| Ligar | `~/hermes-workspace/tijolao.sh up` |
| Ver se está de pé | `~/hermes-workspace/tijolao.sh status` |
| Ver o que está acontecendo | `~/hermes-workspace/tijolao.sh logs` |
| Desligar | `~/hermes-workspace/tijolao.sh down` |

Depois do `up`, a interface abre em **http://localhost:3000**

Os outros: `restart`, `build`, `update`, `shell`, `ui`, `help`.

## O que sobe

São dois containers, os dois na rede do próprio notebook:

- **hermes-agent** — o cérebro. Gateway em `127.0.0.1:8642`,
  painel em `127.0.0.1:9119`. É a imagem oficial `nousresearch/hermes-agent`.
- **hermes-workspace** — a interface web em `127.0.0.1:3000`.
  Essa é construída a partir do código do **seu fork**, aqui na pasta.

Nada escuta fora do `127.0.0.1`. De fora do notebook, nada responde.

## O `hermes` na linha de comando continua valendo

`~/.local/bin/hermes` já estava escrito para entrar no container.
Com a stack ligada, `hermes` no terminal funciona normal.
Com a stack desligada, ele avisa e manda você rodar `tijolao.sh up`.

## Onde ficam os dados

| O quê | Onde |
|---|---|
| Config, skills, kanban, sessões, cron | `~/.hermes/` (na máquina, não no container) |
| Segredos (um arquivo só) | `~/projetos/.env` |
| Seus projetos, visíveis pro agente | `~/projetos/` |

Os containers montam essas pastas nos **mesmos caminhos** por dentro.
Então `~/.hermes/config.yaml` vale dentro e fora, sem cópia e sem divergência.

`docker compose down` **não apaga nada** disso — é pasta sua, não volume do Docker.

## O 9Router é pré-requisito

O `config.yaml` aponta o modelo padrão para `http://127.0.0.1:20128/v1`
(9Router, modelo `cx/gpt-5.6-sol`). Se o 9Router estiver fora,
o agente sobe mas não responde.

`tijolao.sh status` mostra a linha `9Router 20128` — se ela não devolver `200`,
o problema é o 9Router, não o Hermes.

## Quando quebrar

1. `tijolao.sh status` — diz qual das quatro portas está muda.
2. `tijolao.sh logs agent` — erro de chave, de modelo ou de config.
3. `tijolao.sh logs ws` — erro da interface.
4. `tijolao.sh restart` — resolve travada de lock.

Se o gateway reclamar de lock antigo: já está tratado, o container sobe
com `gateway run --replace`.

## Atualizar

`tijolao.sh update` faz, nessa ordem:
`git fetch upstream` → atualiza `main` → rebase do branch `tijolao` → rebuild → restart.

Dois branches, de propósito:

- **`main`** = espelho limpo do upstream `outsourc-e/hermes-workspace`. Não mexa.
- **`tijolao`** = o branch em uso: poda + Dockerfile corrigido + compose desta máquina.

Assim `git pull` do upstream nunca dá conflito em `main`, e tudo que é seu
está num lugar só.

## Duas coisas que ficaram pendentes por decisão

1. **O fork no GitHub ainda está no commit antigo.** Aqui o `main` está
   3 commits à frente. Quando quiser refletir lá: `git push origin main` e
   `git push -u origin tijolao`.
2. **O socket do Docker não está montado no agente.** Montar daria ao agente
   poder de root no notebook. O terminal dele está em `backend: local`,
   que não precisa disso. Se um dia precisar de terminal em sandbox,
   é uma linha no compose — e é uma decisão de segurança, não de configuração.
