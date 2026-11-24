# BRAINDUMP — Mistral Vibe gateway: finish GHCR pipeline + deploy

Handoff brief. Written 2026-11-24. For the next agent. Repo: `~/apps/mistral-gateway-docker` on this host (maneuro, user `ansible`; docker requires `sudo -n`).

## ⚠️ Critical constraint (user-confirmed)

**The gateway serves THIS agent's own inference.** The Hermes session that did this work runs zai-glm-5-3 via a custom provider hitting `http://127.0.0.1:8788` (the gateway). Rebuilding/restarting container `mistral-gateway` mid-session can sever the live agent. Deploy only when no agent session depends on it, or accept the risk knowingly. This is why deployment was deferred to the user/next agent.

## What this is

OpenAI-compatible proxy (upstream `Classic298/mistral-gateway`) exposing a Mistral **Vibe** plan key. Deployed as docker container `mistral-gateway`, host port 8788. Dec 1 2026: Mistral starts metering third-party Vibe-key usage against the small free API pool ($15/mo on this EDU plan) instead of the Vibe pool ($150/mo). Current usage: vibe 37.6%, api 0.1%, both reset 2026-12-01.

Skill with full operating procedures: `skill_view(name='mistral-vibe-gateway')` (procedures: verify, upstream sync; fingerprint reference included).

## State — DONE (verified)

1. **Upstream merge complete**: repo was 41 commits behind; `gateway.py` was pristine upstream v1.0.3, taken to v1.0.7 wholesale (`git merge upstream/main --allow-unrelated-histories`, conflicts resolved: gateway.py + gateway.env.example = theirs; README/.gitignore = ours; Dockerfile/compose = ours, no conflict). Commit `3d3b9cb`. `py_compile` passed.
2. **Deployed and live**: rebuilt container 2026-11-24, `sudo -n docker compose up -d --build`. `/health` → `{"ok": true, "version": "1.0.7", "accounts": 1, "serving": 1}`. A real streaming request (tool calls, GLM reasoning-snap retry observed in logs) served during verification. `/quota` endpoint works and shows both budget pools.
3. **Fork pushed**: `https://github.com/manawenuz/mistral-gateway-docker` (origin). Remote `main` = `3d3b9cb` (v1.0.7 code, NO workflow file). Local `main` = `6fa6249`, one commit ahead: adds `.github/workflows/docker.yml`.
4. GH iris repo actions: already enabled (API returned 204/`enabled: true`).

## State — BLOCKED (this is your work)

- **Pushing the workflow file fails**: the only credential is `GITHUB_TOKEN` in `~/.hermes/.env` (40-char classic PAT, has repo scope). GitHub rejects pushes containing `.github/workflows/*` without `workflow` scope: "refusing to allow a Personal Access Token to create or update workflow `.github/workflows/docker.yml` without `workflow` scope". Never print the token; source the env file inside bash: `bash -c 'set -a; source ~/.hermes/.env; …'`.
- **Two unblock paths** (user was offered these; do whichever is available):
  - (a) User swaps in a new PAT with `repo,workflow` scopes. Swap one-liner for the user to run themselves: `read -s -p "Paste GitHub token: " T && sed -i '/^GITHUB_TOKEN=/d' ~/.hermes/.env && echo "GITHUB_TOKEN=$T" >> ~/.hermes/.env && unset T`
  - (b) User pushes `6fa6249` from their laptop.
- After push: watch the Actions run (no `gh` CLI installed on this host; use the GitHub API with the PAT: `GET /repos/manawenuz/mistral-gateway-docker/actions/runs`).

## Remaining tasks, in order

1. Push workflow commit `6fa6249` (see unblock paths).
2. Verify Actions run green → image at `ghcr.io/manawenuz/mistral-gateway-docker:latest` plus `:1.0.7` and `:sha-…` tags.
3. **GHCR package visibility**: new ghcr.io packages default to private. On maneuro, either make the package public (web UI) or `sudo docker login ghcr.io` with a PAT having `read:packages`.
4. Switch `docker-compose.yml` (or the override) from `build:` to `image: ghcr.io/manawenuz/mistral-gateway-docker:latest`. Read `docker-compose.yml` + `docker-compose.override.yml` first — env/secrets come from `gateway.env` (`VIBE_KEY`, `GATEWAY_KEY`, `BIND=0.0.0.0`, `PORT=8788`); do NOT print the file's secrets.
5. Redeploy **respecting the critical constraint above** (ideally user-triggered): `sudo -n docker compose pull && sudo -n docker compose up -d`. Note: `docker compose up` gets blocked if run as a foreground terminal command — run with `terminal(background=true)` and wait via `process_manage`.
6. Verify: `curl -H "Authorization: Bearer $(grep '^GATEWAY_KEY=' gateway.env | cut -d= -f2)" http://127.0.0.1:8788/health` shows the new version; logs show a served request.

## Optional follow-up approved earlier, never started

Fingerprint/faithfulness patch on `gateway.py` (local diff vs upstream — NOT for upstream submission). Today the gateway is wire-faithful on body shape but cheaply identifiable. Add to every upstream request:
- `User-Agent: mistral-client-python/Mistral-Vibe/<version>` (gateway had none; stdlib urllib sends `Python-urllib/3.x`)
- `x-affinity: <stable per-session id>` header
- `metadata: {session_id, purpose, iteration}` body field
Ground truth for the real client's signals: skill file `references/client-fingerprint.md` (and re-verify against a fresh clone of `mistralai/mistral-vibe`, currently at v3.1.4 — check `harness/runtimes/python/python/mistralai_vibe_local_harness/vibe/adapters/mistral.py` for exact request kwargs: `temperature`, `parallel_tool_calls: true` with tools, `reasoning_effort`, replaying assistant reasoning as `{"type": "thinking", …}` content chunks, image cap of 8 per request).

## Recurring-update procedure (after GHCR is live)

```
cd ~/apps/mistral-gateway-docker
git fetch upstream
git merge upstream/main --allow-unrelated-histories --no-edit
# conflicts: gateway.py + gateway.env.example -> theirs; README/.gitignore -> ours  (repo-local git user.name/email already set)
# re-check gateway.env against gateway.env.example for NEW required vars
python3 -m py_compile gateway.py
git push origin main                     # triggers GHCR build
sudo -n docker compose pull && sudo -n docker compose up -d   # careful: self-serving (see constraint)
```

## Verification commands

```
KEY=$(grep '^GATEWAY_KEY=' ~/apps/mistral-gateway-docker/gateway.env | cut -d= -f2)
curl -H "Authorization: Bearer $KEY" http://127.0.0.1:8788/health   # ok/version/serving
curl -H "Authorization: Bearer $KEY" http://127.0.0.1:8788/quota    # vibe vs api budget pools
sudo -n docker logs mistral-gateway --tail 20
```

## Gotchas learned

- Repo merge histories are unrelated → need `--allow-unrelated-histories`.
- `git diff v1.0.3 …` in a shell loop: a doubled-v typo made every tag "differ"; check stderr when per-tag loops misbehave.
- Terminal guard blocks `docker compose up` as foreground; use background + `process_manage`.
- Vault-stored GitHub PATs are origin-bound browser-fill only; for shell use the token must be in `~/.hermes/.env`.
- `memory` tool: target= goes at the top level for single ops, and batch ops must fit the 2,200-char budget (patch stale entries to free room in the same batch).
