# Deploy do Braxy (um servidor)

Stack em `infra/docker-compose.prod.yml`:

| Serviço | O que faz |
|---|---|
| `web` | Caddy: HTTPS automático (Let's Encrypt), serve o SPA e faz proxy de `/api`, `/cable` e `/up` para o backend. Único serviço com portas publicadas (80, 443 e 443/udp), exceto atrás do kamal-proxy (ver "Servidor compartilhado"). |
| `backend` | Binário release single-thread, `WEB_CONCURRENCY` processos na mesma porta (`bin/multi`, `SO_REUSEPORT`). Sem portas publicadas. |
| `migrate` | Roda `saci-migrate up` uma vez; o backend só sobe depois que ele termina com sucesso. |
| `pg`, `redis` | Postgres 16 e Redis 7 com volumes próprios. |
| `backup` | `pg_dump` diário (formato custom) no volume `backups`, mantendo `BACKUP_KEEP_DAYS` dias. |

As imagens saem de `infra/prod.Dockerfile` (alvos `backend` e `web`).

## Primeira vez

1. DNS: aponte `BRAXY_DOMAIN` para o servidor e libere as portas 80 e 443.
2. Configuração:
   ```sh
   cp infra/prod.env.example .env.prod   # fora do git (.env* não deve ser commitado)
   ```
   Preencha `BRAXY_DOMAIN`, `ACME_EMAIL`, `SECRET_KEY_BASE` (`saci secret` ou
   `openssl rand -hex 64`), `POSTGRES_PASSWORD` e as variáveis `S3_*` do bucket
   de uploads. Sem `S3_BUCKET`, os uploads ficam no volume `uploads`
   (`/app/storage`): sobrevivem aos deploys, mas ficam só neste servidor e
   fora dos backups do Postgres.
3. Subir:
   ```sh
   docker compose -f infra/docker-compose.prod.yml --env-file .env.prod up -d --build --wait
   ```

## Deploy de uma versão nova

```sh
git pull
docker compose -f infra/docker-compose.prod.yml --env-file .env.prod up -d --build --wait
```

O `migrate` roda antes do backend novo. As migrações precisam ser compatíveis
com a versão anterior, que segue no ar até o backend novo ficar saudável.
O `SIGTERM` drena as conexões (até 15 s, `stop_grace_period` de 20 s).

## Servidor compartilhado (kamal-proxy na frente)

Quando o servidor também hospeda outros apps, quem fica nas portas 80 e 443 é o
[kamal-proxy](https://github.com/basecamp/kamal-proxy): ele termina o TLS
(Let's Encrypt) e escolhe o app pelo domínio. O `web` do Braxy passa a servir
HTTP puro na rede Docker `kamal`, sem publicar portas. Basta somar o override
`infra/docker-compose.edge.yml` em **todos** os comandos do compose:

```sh
docker compose -f infra/docker-compose.prod.yml -f infra/docker-compose.edge.yml \
  --env-file .env.prod up -d --build --wait
```

Sem o override, o `web` tenta publicar 80/443, que já estão com o kamal-proxy, e não sobe.

A rota do Braxy é registrada uma vez no kamal-proxy (ele guarda as rotas entre
reinícios):

```sh
docker exec kamal-proxy kamal-proxy deploy braxy --target braxy-web:80 \
  --host "$BRAXY_DOMAIN" --tls --health-check-path /up
```

Como o `--tls` está ligado e o `--forward-headers` não, o kamal-proxy
**sobrescreve** `X-Forwarded-For` com o IP do cliente e manda
`X-Forwarded-Proto: https`. O Caddy confia nele (`BRAXY_TRUSTED_PROXIES`) e
repassa esse IP ao backend, então o rate limit e o `force_ssl` continuam
corretos. Não ligue `--forward-headers` nessa rota: com ele, um
`X-Forwarded-For` enviado pelo cliente chegaria ao backend.

**Saci:** o build usa o contexto `saci` (padrão: `master` do GitHub). Para um
build reproduzível, fixe um commit em `SACI_CONTEXT`
(`https://github.com/pedrohvsouza/saci.git#<sha>`). Para usar o checkout local:
`SACI_CONTEXT=../../saci` (relativo a `infra/`; o build leva o que estiver
no working tree, inclusive mudanças não commitadas).

Com registry: gere as imagens no CI, defina `BRAXY_IMAGE` e `BRAXY_WEB_IMAGE`
e troque o `--build` por `docker compose ... pull && docker compose ... up -d --wait`.

## Segurança

- **O backend não pode ficar exposto sem o proxy.** O rate limit identifica o
  cliente pelo primeiro valor de `X-Forwarded-For`. O Caddy **sobrescreve** esse
  cabeçalho com o IP real (`header_up X-Forwarded-For {client_ip}`: o IP de
  quem conectou, ou o que um proxy confiável em `BRAXY_TRUSTED_PROXIES` informou). Se o
  cliente chegar direto no backend, ou por outro proxy que só acrescente ao
  cabeçalho recebido, qualquer um fura o limite do login falsificando o
  `X-Forwarded-For`. Por isso o `backend` não publica portas. Se houver um load
  balancer na frente do Caddy, ele também precisa sobrescrever o cabeçalho, e
  o Caddy deve confiar nele (`BRAXY_TRUSTED_PROXIES`). É o caso do kamal-proxy
  (ver "Servidor compartilhado").
- Cookies: em produção a sessão é cifrada e sai com `Secure; HttpOnly;
  SameSite=Lax`. O `force_ssl` redireciona para HTTPS conforme o
  `X-Forwarded-Proto` que o Caddy envia.
- Cabeçalhos: o Caddy só define HSTS. CSP, `X-Frame-Options` e
  `Referrer-Policy` são responsabilidade da aplicação (B6).
- `SECRET_KEY_BASE` assina e cifra as sessões; trocá-lo desloga todo mundo.

## Backups

- Automático: todo dia às `BACKUP_AT` (UTC) em `/backups/braxy-<data>.dump`.
- Na hora: `docker compose -f infra/docker-compose.prod.yml --env-file .env.prod exec backup sh /usr/local/bin/pg-backup now`
- Os dumps ficam no mesmo servidor. Copie o volume `backups` para outro lugar
  (por exemplo, `aws s3 sync` ou `restic` num cron do host).
- Restaurar (com o backend parado):
  ```sh
  docker compose -f infra/docker-compose.prod.yml --env-file .env.prod stop backend
  docker compose -f infra/docker-compose.prod.yml --env-file .env.prod exec backup \
    pg_restore --clean --if-exists --no-owner -d braxy_production /backups/<arquivo>.dump
  docker compose -f infra/docker-compose.prod.yml --env-file .env.prod start backend
  ```

## Capacidade

- `WEB_CONCURRENCY` (processos) × `DB_POOL` (conexões por processo) deve ficar
  perto do número de núcleos (benchmark: 4 processos × 8).
- `SACI_MEMORY_LIMIT` é o orçamento de heap de cada processo para o GC
  (limite do container ÷ processos, com folga para sockets).
- Mais de um servidor: aponte todos para o mesmo Postgres e Redis (o Redis já
  leva o fan-out do Cable, a presença e os rate limits entre processos).

## Observabilidade

- **Logs:** JSON, um objeto por linha no stdout (`SACI_LOG_FORMAT=json`;
  `docker compose ... logs backend`). Em produção o nível é `warn`;
  `LOG_LEVEL=info` acrescenta uma linha por requisição (método, caminho,
  status, duração, request id, IP). Erros 500 não tratados saem como
  `level: ERROR` com a exceção (o binário é `--no-debug`, então o backtrace
  vem sem nomes de função). O Caddy também loga em JSON.
- **Métricas:** com `METRICS_TOKEN` definido, `GET http://backend:3000/metrics`
  (Prometheus) dentro da rede do compose; o Caddy não encaminha `/metrics`.
  O scraper precisa mandar `Authorization: Bearer <METRICS_TOKEN>` e
  `X-Forwarded-Proto: https` (senão o `force_ssl` redireciona). Séries:
  `saci_requests_total`, por status e por rota (contagem e soma da duração),
  e por processo `braxy_cable_connections`, `braxy_gc_heap_bytes`,
  `braxy_gc_free_bytes`, `braxy_process_rss_bytes`, `braxy_uptime_seconds`.
- **Limite:** cada processo do `bin/multi` tem seus contadores, e cada scrape
  cai num processo qualquer (`SO_REUSEPORT`), identificado pelo rótulo `pid`.
  Some ou tire a média por `pid` no Prometheus; uma visão agregada por
  container depende do Saci (ver o relatório da frente D).
