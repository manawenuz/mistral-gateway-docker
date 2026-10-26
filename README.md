# mistral-gateway-docker

Run [mistral-gateway](https://github.com/Classic298/mistral-gateway) (a local
OpenAI-compatible proxy for a **Mistral Vibe** subscription) with docker-compose.

Your Vibe plan key stays on your machine, in the container. Any OpenAI-compatible
client (editors, scripts, chat UIs, agents like [Hermes](https://github.com/NousResearch/hermes-agent))
can then use the models included in your Vibe plan.

> **Unofficial.** Not affiliated with Mistral. Personal use only — one person,
> one account. Read the [upstream README](https://github.com/Classic298/mistral-gateway)
> (Terms of service section) before use. Mistral consumer terms forbid sharing
> your account or keys with anyone else; keep this on loopback/private networks.

## What's in this repo

- `gateway.py` — the gateway itself, vendored from upstream (single file, stdlib only)
- `Dockerfile` — python:3.12-slim, no pip deps
- `docker-compose.yml` — one service, **no published ports** (private by default)
- `gateway.env.example` — template for your secrets

## Requirements

- Docker + docker compose
- A Mistral Vibe plan with coding included (**Pro**, Team or Enterprise —
  the Free plan's key does not work for this)

## Setup

### 1. Get your Vibe key (once, on any machine)

```sh
curl -LsSf https://mistral.ai/vibe/install.sh | bash
vibe --setup          # pick browser login
grep MISTRAL_API_KEY ~/.vibe/.env
```

Or skip the CLI: open https://chat.mistral.ai/code/extensions →
Vibe CLI card → **Advanced** → copy the **Vibe API Key**. The same panel shows
your monthly usage and lets you rotate the key.

### 2. Clone and configure

```sh
git clone https://github.com/manawenuz/mistral-gateway-docker.git
cd mistral-gateway-docker
cp gateway.env.example gateway.env
openssl rand -hex 32     # use this as GATEWAY_KEY
```

Edit `gateway.env`:
- `VIBE_KEY=` → key from step 1
- `GATEWAY_KEY=` → the random string you just generated
- leave `BIND=0.0.0.0` — it binds *inside* the container only; compose
  publishes nothing, so it stays private

`GATEWAY_KEY` is mandatory in docker: without it the gateway answers only
loopback callers, and other containers reach it by hostname, not by
`127.0.0.1`.

### 3. Start

```sh
docker compose up -d --build
docker compose logs -f mistral-gateway
```

A working start looks like:

```
INFO vibe plan: ... (...)
INFO mistral gateway on 0.0.0.0:8788 (keys: vibe)
```

### 4. Point a client at it

From *inside* the docker network (another container attached to
`mistral-gateway_default`):

- Base URL: `http://mistral-gateway:8788/v1`
- API key: your `GATEWAY_KEY`
- Model: any ID from the models list

```sh
docker network connect mistral-gateway_default my-other-container
docker exec my-other-container curl -s http://mistral-gateway:8788/v1/models \
  -H "Authorization: Bearer $GATEWAY_KEY"
```

From the *host*, publish nothing — instead add a loopback-only port mapping
if you need host access:

```yaml
    ports:
      - "127.0.0.1:8788:8788"
```

then use `http://127.0.0.1:8788/v1`. This stays on the host's loopback —
safe — but do **not** remove the `127.0.0.1:` prefix and do not expose it
to the internet or share it with anyone.

Requests must be `Content-Type: application/json`. Browsers cannot call the
gateway directly.

### 5. Hermes Agent example

Hermes supports named OpenAI-compatible endpoints natively:

```yaml
# in Hermes' config.yaml
providers:
  mistral-gateway:
    name: mistral-gateway
    api: http://mistral-gateway:8788/v1
    key_env: HERMES_MISTRAL_GATEWAY_KEY
    transport: chat_completions
    default_model: zai-glm-5-3

model:
  provider: custom:mistral-gateway
  default: zai-glm-5-3
```

with the key in Hermes' `.env`:

```
HERMES_MISTRAL_GATEWAY_KEY=<your GATEWAY_KEY>
```

## Operating notes

- **429** → gateway retries the same key every 10s for up to 60s, then cools
  it down for 60s. **401/402** → 6h cooldown (budget spent / key revoked).
- **Usage tracking**: local `usage.db` inside the container, readable at
  `GET /usage` with the same Bearer key.
- **Prompt-cache friendly**: all traffic goes through one key, which keeps
  Mistral's upstream prompt cache warm (cached input bills much cheaper).
  Don't add more keys.
- **Update**: re-vendor `gateway.py` from upstream when models change:
  ```sh
  curl -fsSL -o gateway.py https://raw.githubusercontent.com/Classic298/mistral-gateway/main/gateway.py
  docker compose up -d --build
  ```

## Safety rules

1. **One person, one account.** Never share your Vibe key or GATEWAY_KEY.
2. Keep it on loopback or a private docker network. Never publish a port to
   the internet, never put it behind a public reverse proxy.
3. Treat `gateway.env` like a password: chmod 600, never commit, never paste
   anywhere.
4. Mistral can change its terms at any time — re-check the upstream README's
   ToS section when Mistral announces changes.

## License / credits

- `gateway.py` is [PolyForm Noncommercial 1.0.0](https://github.com/Classic298/mistral-gateway/blob/main/LICENSE),
  © its upstream author. This repo vendors it unmodified.
- Everything else here: MIT.
