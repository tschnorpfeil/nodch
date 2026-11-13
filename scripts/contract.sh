#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
cache="${TMPDIR:-/tmp}/nodch-contract"
nod="$cache/nod"
revision=915e4f1f0f5ee6e3af422bcc2814dc4c6a851cc1
mkdir -p "$cache"
if [[ ! -d "$nod/.git" ]]; then git clone https://github.com/n8n-io/nod.git "$nod"; fi
if [[ -n $(git -C "$nod" status --porcelain) ]]; then echo 'Refusing to use a modified Nod checkout.' >&2; exit 1; fi
git -C "$nod" checkout --detach "$revision"
(cd "$nod" && CI=true npm_config_cache="$cache/npm" npx -y pnpm@10.34.5 install --frozen-lockfile --store-dir "$cache/pnpm-store")
run=$(mktemp -d "$cache/run.XXXXXX")
pg="nodch-contract-pg-$$"
# Nod only runs commands in containers named nod-workspace(-*) (src/providers/docker/command.ts).
workspace="nod-workspace-nodch-contract-$$"
server_pid=''
stub_pid=''
cleanup() {
  [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true
  [[ -z "$stub_pid" ]] || kill "$stub_pid" 2>/dev/null || true
  for ((i=0;i<50;i++)); do
    if { [[ -z "$server_pid" ]] || ! kill -0 "$server_pid" 2>/dev/null; } && \
       { [[ -z "$stub_pid" ]] || ! kill -0 "$stub_pid" 2>/dev/null; }; then break; fi
    sleep 0.1
  done
  [[ -z "$server_pid" ]] || kill -KILL "$server_pid" 2>/dev/null || true
  [[ -z "$stub_pid" ]] || kill -KILL "$stub_pid" 2>/dev/null || true
  [[ -z "$server_pid" ]] || wait "$server_pid" 2>/dev/null || true
  [[ -z "$stub_pid" ]] || wait "$stub_pid" 2>/dev/null || true
  docker rm -fv "$pg" "$workspace" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export NOD_URL="http://127.0.0.1:${NODCH_CONTRACT_PORT:-14310}"
export NOD_DATA_ROOT="$run/data"
unset NOD_AUTH_TOKEN
export NODCH_STUB_PORT="${NODCH_STUB_PORT:-14311}"
mkdir -p "$NOD_DATA_ROOT/workspaces" "$run/tmp"
# PostgreSQL is disposable; no host or existing Nod database is touched.
docker run -d --name "$pg" -e POSTGRES_USER=nod -e POSTGRES_PASSWORD=nodch-contract -e POSTGRES_DB=nod -p 127.0.0.1::5432 postgres:17-alpine >/dev/null
for ((i=0;i<60;i++)); do
  if docker exec "$pg" pg_isready -U nod >/dev/null 2>&1; then break; fi
  sleep 1
done
pg_port=$(docker port "$pg" 5432/tcp | sed 's/.*://')
# The chosen tool changes only Nod preferences. A minimal isolated workspace is sufficient;
# no browser, credentials, connected apps or paid services are used.
docker run -d --name "$workspace" --network none -v "$NOD_DATA_ROOT/workspaces:/workspace" python:3.13-slim sleep infinity >/dev/null
node "$repo/scripts/stub-model.mjs" >"$run/model.log" 2>&1 &
stub_pid=$!
for ((i=0;i<20;i++)); do
  if ! kill -0 "$stub_pid" 2>/dev/null; then cat "$run/model.log"; exit 1; fi
  if curl -sf "http://127.0.0.1:$NODCH_STUB_PORT/v1/models" >/dev/null; then break; fi
  sleep 0.1
done
(
  cd "$nod"
  exec env -i PATH="$PATH" HOME="$run" TMPDIR="$run/tmp" \
    DOTENV_CONFIG_PATH=/dev/null \
    PORT="${NODCH_CONTRACT_PORT:-14310}" NOD_HOST=127.0.0.1 NOD_DATA_ROOT="$NOD_DATA_ROOT" \
    DATABASE_URL="postgres://nod:nodch-contract@127.0.0.1:$pg_port/nod" \
    NOD_VAULT_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
    LLM_PROVIDER=compatible OPENAI_COMPATIBLE_BASE_URL="http://127.0.0.1:$NODCH_STUB_PORT/v1" LLM_MODEL=nodch-contract \
    NOD_TRUST_MODEL=selected NOD_ANALYTICS_ENABLED=false NOD_FEEDBACK_ENABLED=false \
    WORKSPACE_CONTAINER="$workspace" \
    node --import tsx src/server/index.ts
) >"$run/nod.log" 2>&1 &
server_pid=$!
ready=0
for ((i=0;i<90;i++)); do
  if ! kill -0 "$server_pid" 2>/dev/null; then cat "$run/nod.log"; exit 1; fi
  if [[ -f "$NOD_DATA_ROOT/access-key" ]] && curl -sf -H "Cookie: nod-access-${NODCH_CONTRACT_PORT:-14310}=$(cat "$NOD_DATA_ROOT/access-key")" "$NOD_URL/api/health" >/dev/null; then ready=1; break; fi
  sleep 1
done
if [[ "$ready" != 1 ]]; then cat "$run/nod.log"; exit 1; fi
printf 'Nod checkout: %s\nLogs: %s\n' "$nod" "$run"
if [[ "${1:-}" == '--serve' ]]; then
  printf 'Live Nod: %s/#access=%s\n' "$NOD_URL" "$(cat "$NOD_DATA_ROOT/access-key")"
  printf 'Launch nodch with NOD_URL=%s NOD_DATA_ROOT=%s\n' "$NOD_URL" "$NOD_DATA_ROOT"
  printf 'Send any prompt in Nod to show a pending approval; Ctrl-C stops the fixture.\n'
  wait "$server_pid"
else
  if ! swift run --package-path "$repo/app" NodchContract; then
    cat "$run/model.log" "$run/nod.log"
    exit 1
  fi
  printf 'PASS Nod pinned revision -> %s\n' "$(git -C "$nod" rev-parse HEAD)"
  test -z "$(git -C "$nod" status --porcelain)"
  printf 'PASS Nod git status --porcelain -> clean\n'
fi
