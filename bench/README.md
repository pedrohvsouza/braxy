# Benchmark do Braxy

Mede quantas requisições por segundo e quantos usuários simultâneos o Braxy
aguenta com recursos fixos: **backend + Postgres + Redis nos núcleos 0–3, com
2 GB no total** (backend 1 GB, Postgres 768 MB, Redis 256 MB). O gerador de
carga roda num container separado nos núcleos 4–15, dentro da rede do compose
(sem passar pelo docker-proxy).

## Preparar

```sh
export COMPOSE_FILE=docker-compose.yml:docker-compose.bench.yml

# 1. Infra + gerador de carga (o frontend fica de fora).
docker compose up -d pg redis s3 loadgen

# 2. Usuários de teste: bench_00001..bench_20000 (senha password123, bcrypt
#    custo 4), todos no lobby, e 400 salas de 50 membros. Idempotente.
docker compose exec -T pg psql -U braxy -d braxy_development < bench/seed.sql

# 3. Binários release. O compilador precisa de mais de 1 GB, então o build
#    roda SEM o override de limites.
COMPOSE_FILE=docker-compose.yml docker compose run --rm --no-deps backend \
  sh -c 'crystal build --release src/backend.cr -o tmp/bench-backend-st2'
# multithread (preview): acrescente -Dexecution_context e rode com SACI_MT=1
```

## Rodar

Uma configuração (varredura HTTP e rampa de WebSocket, cada uma num processo
recém-iniciado e com o Redis zerado):

```sh
bench/run-config.sh st1opt "./tmp/bench-backend-st2"              # 1 processo
bench/run-config.sh st4opt "bin/multi ./tmp/bench-backend-st2"    # 4 processos
```

Os resultados ficam em `bench/results/` (ignorado pelo git):
`http-sweep-<slug>.txt`, `ws-<slug>.txt` e os CSVs de CPU/memória dos
containers. `node bench/summarize.mjs` junta tudo em `http_sweep.json` e
`ws_ramp.json`, que alimentam o dashboard.

## O que cada teste faz

- **`http-sweep.mjs`**: para cada endpoint (`/up`, `/api/session`,
  `/api/sidebar`, página de mensagens, envio de mensagem distribuído em 400
  salas) sobe a concorrência em 8, 16, 32, 64, 128, 256 e 512 conexões, 10 s
  cada, e registra req/s, p50, p90, p99 e erros.
- **`ws.mjs`**: abre sockets em degraus (500 → 20.000 usuários), cada um
  logado e assinando o `ChatChannel`, com heartbeat a cada 30 s. Em cada
  degrau mede o tempo do envio pela API até a chegada em cada socket, em
  dois cenários:
  - **lobby**: 1 mensagem por segundo para todos os conectados (pior caso de
    fan-out);
  - **salas**: cada grupo de 50 usuários recebe 1 mensagem por segundo ao
    mesmo tempo.

  Para no primeiro degrau com mais de 1% de falha (conexão ou entrega).

## Armadilhas encontradas

- **`retry_delay` do crystal-db**: com o pool cheio, o `crystal-db` dorme
  `retry_delay` (padrão 0,2 s) antes da primeira tentativa. A URL do banco usa
  `retry_delay=0.001`.
- **Multithread (`-Dexecution_context`)**: sob carga, uma conexão do Postgres
  foi usada por duas threads ao mesmo tempo (protocolo dessincronizado, login
  correto devolvendo 401) e houve um crash do GC. Em investigação; use
  single-thread, com vários processos se precisar de mais núcleos.
- **Memória por conexão**: cerca de 130 KiB por socket, a maior parte em
  buffers de I/O de 32 KiB (leitura e escrita do socket e a saída da resposta
  HTTP retida após o upgrade). É isso que limita os usuários simultâneos com
  1 GB.
