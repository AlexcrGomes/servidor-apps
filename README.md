# servidor-apps

Servidor compartilhado para apps pequenos, num **Amazon Lightsail** pago com os créditos do
plano gratuito da AWS. Cada app fica num subdomínio de um domínio gratuito do **DuckDNS**, com
HTTPS automático:

| App | Endereço | Repositório |
|-----|----------|-------------|
| Habits | `https://habits.<nome>.duckdns.org` | [AlexcrGomes/habitsapp](https://github.com/AlexcrGomes/habitsapp) |

Este repositório tem só a parte comum: o proxy HTTPS (**Caddy**), a rede Docker `proxy` e a
preparação do servidor. Cada app tem o seu próprio repositório e o seu próprio deploy.
Decisões e motivos: spec 008 do Habits
([plan](https://github.com/AlexcrGomes/habitsapp/blob/main/specs/008-publicacao-gratuita/plan.md)).

```
navegador ──HTTPS──► Caddy (80/443) ──┬─ habits.<nome>… ──► habits-web (rede proxy) ──► api ──► db
                                      └─ <app>.<nome>…  ──► <app>-web  (rede proxy) ──► …
```

- Só o Caddy publica portas no servidor. Os apps ligam o seu serviço web à rede `proxy`
  com um apelido (ex.: `habits-web`); bancos e APIs ficam na rede interna de cada app.
- Atualizar um app não reinicia o proxy nem os outros apps.

> ⚠️ **Sem backup.** O plano gratuito da AWS **encerra a conta 6 meses após o cadastro ou
> quando os créditos acabam**, e o servidor é desligado com os dados de todos os apps. Veja
> [Fim dos créditos](#fim-dos-créditos).

| O quê | Valor |
|-------|-------|
| Servidor | Lightsail `servidor-apps`: Linux, 2 GB de RAM, 2 vCPU, 60 GB de SSD, Ubuntu 24.04 |
| Região | Ohio, EUA (`us-east-2`) |
| IP estático | `servidor-apps-ip` |
| Custo | Cerca de US$ 12/mês, descontado dos créditos (~US$ 72 em 6 meses) |
| Aviso de gasto | Orçamento de US$ 16/mês no AWS Budgets |

---

## 1. Conta AWS e segurança

1. Entre no console em <https://console.aws.amazon.com> com a conta que recebeu os créditos.
2. **Fique no plano gratuito ("Free plan")**. Não faça upgrade para o plano pago: é ele que
   garante que nada seja cobrado no cartão. Confira em *Billing and Cost Management → Free
   Tier* (mostra o plano e quantos dias faltam).
3. **Créditos**: *Billing and Cost Management → Credits*. Anote o saldo e a validade. US$ 100
   entram no cadastro; até US$ 100 a mais vêm de atividades sugeridas pela AWS.
4. **MFA no usuário raiz**: clique no seu nome (canto superior direito) → *Security
   credentials* → *Assign MFA device* → *Authenticator app*.

## 2. Aviso de gasto (orçamento)

*Billing and Cost Management → Budgets → Create budget*:

1. **Customize (advanced)** → *Budget type*: **Cost budget** → *Next*.
2. Nome `servidor-apps-mensal`, período **Monthly**, *Recurring*, *Fixed*, valor **16.00** (USD).
3. Alertas: **80%** e **100%** de *Actual*, para o seu e-mail.
4. *Next* → *Create budget*.

## 3. Criar o servidor no Lightsail

1. <https://lightsail.aws.amazon.com> → **Create instance**.
2. *Instance location*: **Ohio (us-east-2)**, zona A.
3. **Linux/Unix** → **Operating System (OS) only** → **Ubuntu 24.04 LTS**.
4. *SSH key pair*: **Upload New** com a sua chave pública pessoal (`~/.ssh/id_ed25519.pub`).
   Se o Lightsail não aceitar, mantenha a chave padrão e, depois de criado, abra **Connect
   using SSH** (terminal no navegador) e rode:
   ```bash
   echo "<conteúdo do seu id_ed25519.pub>" >> ~/.ssh/authorized_keys
   ```
5. *Network type*: **Dual-stack**. *Plan*: **2 GB RAM, 2 vCPUs, 60 GB SSD**.
6. Nome `servidor-apps` → **Create instance**.

> O servidor consome crédito enquanto existir, **mesmo parado**. Para parar de gastar, é
> preciso apagá-lo (e soltar o IP estático).

## 4. IP estático e firewall

1. Na aba **Networking** da instância: **Attach static IP** → nome `servidor-apps-ip`. O IP
   estático não tem custo enquanto está ligado; **solto, é cobrado**.
2. Em **Firewall rules**, mantenha *SSH (22)* e *HTTP (80)* e acrescente **HTTPS (443)** para
   *Anywhere IPv4* e *Anywhere IPv6*. Não abra outras portas.
3. No seu PC, crie um atalho em `~/.ssh/config`:
   ```
   Host servidor-apps
       HostName <IP-estático>
       User ubuntu
       IdentityFile ~/.ssh/id_ed25519
   ```
   e teste com `ssh servidor-apps`.

## 5. Domínio no DuckDNS

1. Entre em <https://www.duckdns.org> (login com GitHub ou Google).
2. Crie **um** nome genérico (ex.: `alexapps`) e coloque o **IP estático** em *current ip*.
   Deixe o IPv6 vazio.
3. O DuckDNS responde qualquer subdomínio abaixo do nome com o mesmo IP. Confira:
   ```bash
   nslookup alexapps.duckdns.org
   nslookup habits.alexapps.duckdns.org
   ```
   Os dois devem responder com o IP estático.

## 6. Chave SSH de deploy (no seu PC)

Cada app publica pelo GitHub Actions com uma chave **exclusiva**, sem senha, separada da sua
chave pessoal. Para o Habits:

```bash
ssh-keygen -t ed25519 -C "habits-deploy" -N "" -f ~/.ssh/habits_deploy
```

Gera `habits_deploy` (privada → secret do GitHub do app) e `habits_deploy.pub` (pública →
servidor). Nunca coloque a privada num repositório.

## 7. Preparar o servidor

```bash
ssh servidor-apps
curl -fsSLO https://raw.githubusercontent.com/AlexcrGomes/servidor-apps/main/scripts/server-setup.sh
sudo bash server-setup.sh "<conteúdo de ~/.ssh/habits_deploy.pub>"
```

O script instala Docker e Compose, desliga login SSH por senha, liga atualizações automáticas
de segurança, cria 2 GB de swap, cria o usuário `deploy` com a chave informada, cria a rede
Docker `proxy` e clona este repositório em `/opt/servidor-apps`.

## 8. Subir o proxy

```bash
sudo -u deploy bash -c 'cd /opt/servidor-apps && cp .env.example .env && nano .env'
```

Em `APPS_DOMAIN`, coloque o domínio do passo 5 (ex.: `alexapps.duckdns.org`). Depois:

```bash
sudo -u deploy bash /opt/servidor-apps/scripts/atualizar.sh
```

Abra `https://alexapps.duckdns.org`: deve aparecer **"Nenhum app neste endereço."** com
cadeado. O subdomínio de cada app só funciona depois que o app for publicado (o Habits, pelo
`docs/deploy.md` do repositório dele).

---

## Adicionar um app

1. No repositório do app, o compose de produção liga o serviço web à rede `proxy` com um
   apelido próprio e sem portas publicadas:
   ```yaml
   services:
     web:
       ports: !reset []
       networks:
         default:
         proxy:
           aliases: [meuapp-web]
   networks:
     proxy:
       external: true
   ```
   Banco e API ficam só na rede `default` do app.
2. Neste repositório, acrescente um bloco em [`caddy/Caddyfile`](caddy/Caddyfile):
   ```
   meuapp.{$APPS_DOMAIN} {
   	import padrao
   	reverse_proxy meuapp-web:80
   }
   ```
   e uma linha na tabela de apps acima. Faça commit e push.
3. Se o app tiver deploy pelo GitHub Actions, gere uma chave de deploy para ele (passo 6) e
   rode de novo `sudo bash server-setup.sh "<chave pública do app>"` no servidor: o script só
   acrescenta a chave.
4. No servidor: `sudo -u deploy bash /opt/servidor-apps/scripts/atualizar.sh`.

Antes do 2º app, confira a memória (`free -h`): o servidor tem 2 GB para todos os apps.

## Operação

```bash
ssh servidor-apps
cd /opt/servidor-apps
docker compose ps
docker compose logs -f --tail 100 caddy   # certificados e erros de encaminhamento
docker network inspect proxy              # quem está na rede compartilhada
free -h                                   # memória livre
```

- Reiniciar o servidor (**Reboot** no Lightsail) é seguro: os contêineres têm
  `restart: unless-stopped`.
- **Nunca** rode `docker compose down -v` em nenhum app: o `-v` apaga os dados.

## Recriar o servidor do zero

1. Crie o servidor novo (passo 3), ligue a ele o **mesmo IP estático** e refaça o firewall
   (passo 4). O DuckDNS continua valendo.
2. Repita os passos 7 e 8, depois o deploy de cada app (com o `known_hosts` novo nos secrets
   de cada um).
3. Apague o servidor antigo. Sem backup, os bancos começam vazios.

## Custos

- *Billing and Cost Management → Bills*: o gasto do mês aparece descontado dos créditos; o
  valor a pagar deve ser **US$ 0,00**.
- *Cost Explorer*: a previsão do mês deve ficar em até **US$ 16**.
- Snapshots, bancos gerenciados, IP estático solto e servidores extras gastam crédito.

## Fim dos créditos

O plano gratuito encerra a conta aos **6 meses do cadastro** ou quando os créditos acabam, o
que vier primeiro, e o servidor é desligado com os dados. **Antes do 5º mês**, decida entre
migrar, passar ao plano pago ou encerrar (spec futura de backup e permanência no Habits).
