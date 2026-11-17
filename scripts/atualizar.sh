#!/usr/bin/env bash
# Sobe ou atualiza o proxy no servidor. Roda NO SERVIDOR, como o usuário deploy:
#   sudo -u deploy bash /opt/servidor-apps/scripts/atualizar.sh
# Use depois de mudar o caddy/Caddyfile (por exemplo, para adicionar um app).
# Não reinicia os apps; o reload do Caddy troca a configuração sem derrubar conexões.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "Arquivo .env não encontrado em $(pwd) (veja o README)." >&2
  exit 1
fi
if ! docker network inspect proxy >/dev/null 2>&1; then
  echo "Rede Docker 'proxy' não encontrada: rode scripts/server-setup.sh antes." >&2
  exit 1
fi

echo "==> Atualizando o código"
git pull --quiet --ff-only
git log --oneline -1

echo "==> Subindo o proxy"
docker compose up -d --remove-orphans

echo "==> Validando e recarregando o Caddyfile"
docker compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile

echo "==> Proxy atualizado"
docker compose ps
