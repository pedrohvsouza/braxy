# Braxy

Chat em tempo real inspirado no Braxy original (2020), recriado com
**[Saci](https://github.com/pedrohvsouza/saci)** (Crystal, estilo Rails) no
backend e **React** no frontend.

```
braxy/
  backend/    API JSON + Saci Cable (Crystal, Postgres, Redis, S3)
  frontend/   Vite + React + TypeScript
  infra/      Dockerfile de dev, init do Postgres e do S3 (LocalStack)
  docker-compose.yml
```

## Rodando local

Requisitos: Docker e o Saci clonado ao lado (`../saci`), pois o backend
usa o framework por path.

```sh
make up      # pg + redis + s3 + backend (hot reload) + frontend
```

- App: <http://localhost:5173>
- API: <http://localhost:3000> (`/up` = health)
- Postgres `5432` · Redis `6379` · S3/LocalStack `4566`

O backend roda `saci db:migrate`, `saci db:seed` (idempotente) e
`saci serve --watch` ao subir; editar `backend/` ou `../saci` recompila e
reinicia sozinho.

Contas de demonstração (senha **`password123`**):

| Usuário | Cargo | Nível |
|---|---|---|
| `pedro` | Desenvolvedor | 33 |
| `marina` | Administrador | 28 |
| `rafa` | Moderador | 22 |
| `julia` | Suporte | 15 |
| `thiago` | Membro | 8 |

## Testes

```sh
make test-backend    # crystal spec contra o Postgres do compose
make test-frontend   # tsc + vitest
make e2e             # playwright (com a stack no ar)
```

## O que tem no MVP

- Cadastro/login por cookie de sessão HttpOnly + CSRF; card com painel roxo
  deslizante e fundo de formas animadas. Reset de senha por link de uso
  único no e-mail (30 min); trocar ou redefinir a senha encerra as outras
  sessões. Tela "servidor iniciando" com nova tentativa automática.
- Membros de conversas grandes paginados e com busca (o lobby tem dezenas de
  milhares); histórico em memória limitado enquanto se lê o fim da conversa;
  recibos de leitura agrupados (um por conversa a cada 500 ms).
- Sidebar: perfil com XP, busca de usuários, grupos (lobby global "Grupo" +
  grupos criados) e amigos com prévia, não lidas e presença.
- Amizades (pedido, aceitar, recusar, desfazer); DM só entre amigos.
- Mensagens em tempo real (Saci Cable + Redis): responder, @menção, editar,
  apagar (autor, staff, dono do grupo), 6 reações, imagens até 10 MB (S3)
  com prévia e legenda antes de enviar (botão, colar ou arrastar),
  histórico paginado, "digitando…" e "Visto" nas DMs.
- Markdown leve (`**negrito**`, `*itálico*`, `~~riscado~~`, `` `código` ``,
  blocos ```` ``` ````, `> citação`, `||spoiler||`; Ctrl+B / Ctrl+I), emojis
  sozinhos em tamanho grande e seletor de emojis com recentes, busca pelo
  nome em português (anotações CLDR) e navegação por teclado.
- XP/níveis (curva `50·n²`): +10 msg em grupo, +2 em DM (cooldown 10s), +50
  login diário, +20 amizade, +2 reação recebida; notificação ao subir.
  11 conquistas (mensagens, amigos, grupo criado, reações, dias de login,
  níveis) no card de perfil, desbloqueadas ao ganhar XP.
- Notificações (sino + toasts), som com a aba em segundo plano, contador
  no título da aba e notificações do navegador (opt-in nas Preferências:
  DMs e grupos privados; no lobby só menções e respostas). Com
  `VAPID_*` configurado, também push com o Braxy fechado (service worker).
- Moderação: qualquer um bloqueia (desfaz a amizade, some da busca, sem DM,
  pedidos nem menções; mensagens recolhidas); staff no lobby e o dono no
  grupo silenciam (10 min a sem prazo) ou banem, e desfazem pela lista de
  sanções nas informações da conversa.
- Acessibilidade: foco preso nos modais, menus por teclado, mensagens novas
  anunciadas ao leitor de tela, contraste AA no tema.
- Perfil (nome, avatar, recado, aniversário, senha) e card de perfil.
- Tela inicial com contadores ao vivo; latência real no rodapé.
- i18n preparado (só pt-BR por enquanto); layout mobile.

Fora do MVP: música, áudio, GIFs, bot/IA, VIP/loja.

## Configuração opcional

| Variável | Para quê |
|---|---|
| `APP_URL` | Base dos links nos e-mails (padrão: primeira origem de `APP_ORIGINS`). |
| `MAIL_DELIVERY`, `MAIL_FROM`, `SMTP_*` | Envio de e-mail em produção (`smtp`, `ses`, `sendgrid`, `mailgun`, `postmark`; ver `config/initializers/mailer.cr`). Em dev os e-mails vão para `tmp/mails` e o link de reset aparece no log. |
| `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` | Liga o push com o Braxy fechado. Sem elas, a opção nem aparece. |

Gerar as chaves VAPID (P-256):

```sh
openssl ecparam -name prime256v1 -genkey -noout -out vapid.pem
VAPID_PRIVATE_KEY="$(cat vapid.pem)"
VAPID_PUBLIC_KEY="$(openssl ec -in vapid.pem -pubout -outform DER | tail -c 65 | base64 | tr '/+' '_-' | tr -d '=\n')"
```

Os pushes vão sem conteúdo: o service worker busca o texto em
`/api/push/latest` com o cookie da sessão, então não há criptografia de
payload (RFC 8291) no servidor.

## Contrato de tempo real

Uma assinatura `ChatChannel` por aba (auth pelo cookie no upgrade, `Origin`
na allowlist `APP_ORIGINS`). Streams: `user:<id>`, `conversation:<id>` de
cada conversa e `stats`. O cliente envia `typing`, `heartbeat`, `ping`,
`follow`/`unfollow`; o servidor envia `message.created|updated`,
`reaction.updated`, `typing`, `read`, `presence`, `notification.created`,
`friendship.changed`, `conversation.added|removed|updated`, `xp.updated`,
`stats`, `pong`.

## Limites conhecidos

- Imagens são servidas pelo backend (`/api/files/:key`) para qualquer usuário
  logado; as chaves são aleatórias de 128 bits, mas não há checagem de
  pertencimento à conversa.
- Um membro removido de um grupo para de receber eventos quando o cliente
  processa `conversation.removed` (o servidor não derruba o stream à força).
- O lobby não envia "digitando…" (tem todo mundo).
