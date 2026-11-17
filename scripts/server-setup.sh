#!/usr/bin/env bash
# Prepara o servidor Ubuntu 24.04 (AWS Lightsail) que hospeda os apps. Rode UMA vez, como root:
#   sudo bash server-setup.sh "<chave pública SSH de deploy do primeiro app>"
# Rodar de novo é seguro; serve também para acrescentar a chave de deploy de outro app.
# As portas (22/80/443) são controladas pelo firewall do Lightsail; este script não mexe no
# firewall do Ubuntu (o Docker ignora o ufw nas portas publicadas).
# Passo a passo completo no README.md.
set -euo pipefail

deploy_public_key="${1:?informe a chave pública SSH de deploy (GitHub Actions) como argumento}"
repo_url="${SERVIDOR_APPS_REPO_URL:-https://github.com/AlexcrGomes/servidor-apps.git}"
proxy_dir=/opt/servidor-apps

echo "==> Atualizações e pacotes básicos"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq
DEBIAN_FRONTEND=noninteractive apt-get install -yq ca-certificates curl git unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "==> Docker Engine + Compose (repositório oficial)"
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -q
  DEBIAN_FRONTEND=noninteractive apt-get install -yq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker

echo "==> SSH só por chave"
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl reload ssh

echo "==> Swap de 2 GB"
if [[ ! -f /swapfile ]]; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "==> Usuário deploy (usado pelo GitHub Actions dos apps)"
id deploy &>/dev/null || adduser --disabled-password --gecos "" deploy
usermod -aG docker deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
touch /home/deploy/.ssh/authorized_keys
# Acrescenta sem apagar as chaves de outros apps
grep -qxF "$deploy_public_key" /home/deploy/.ssh/authorized_keys \
  || echo "$deploy_public_key" >> /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys

echo "==> Rede Docker compartilhada entre o proxy e os apps"
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy

echo "==> Proxy em $proxy_dir"
if [[ ! -d "$proxy_dir/.git" ]]; then
  git clone "$repo_url" "$proxy_dir"
fi
chown -R deploy:deploy "$proxy_dir"

echo
echo "Pronto. Próximo passo: criar $proxy_dir/.env com APPS_DOMAIN (veja o README) e subir o proxy:"
echo "  sudo -u deploy bash $proxy_dir/scripts/atualizar.sh"
