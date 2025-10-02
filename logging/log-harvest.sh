
#!/bin/sh

set -eu
: "${NODE_PRIV_HEX:?NODE_PRIV_HEX env is required (comes from orchestrator.env)}"
: "${NODE_ID:=unknown}"
: "${MONIKER:=unknown}"
: "${PUBLIC_IP:=0.0.0.0}"
: "${INGEST_URL:=http://host.docker.internal:8080/ingest}"
: "${BOOTSTRAP_LOG:=/hostlogs/bootstrap.log}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[log-signer] installing docker-cli..." >&2
  apk add --no-cache docker-cli >/dev/null
fi

ATTACHED_DIR=/var/lib/log-signer/attached
mkdir -p "$ATTACHED_DIR"

attach_container() {
  cid="$1"; cname="$2"

  case "$cname" in
    log-signer|docker-watchtower-1) return ;;
  esac

  [ -e "$ATTACHED_DIR/$cid" ] && return
  : > "$ATTACHED_DIR/$cid"

  echo "[log-signer] attaching to container $cname ($cid)" >&2

  (
    docker logs -f --since 0 "$cid" 2>&1 | \
    /usr/local/bin/devsigner \
      --priv-hex "$NODE_PRIV_HEX" \
      --node-id   "${NODE_ID:-unknown}" \
      --moniker   "${MONIKER:-unknown}" \
      --public-ip "${PUBLIC_IP:-0.0.0.0}" \
      --input text \
      --stream-type docker \
      --stream-id   "$cid" \
      --stream-name "$cname" \
      --post "$INGEST_URL" \
      --batch 50 --flush 2s
  ) &
}

attach_bootstrap_log() {
  if [ -r "$BOOTSTRAP_LOG" ]; then
    echo "[log-signer] tailing bootstrap log: $BOOTSTRAP_LOG" >&2
    (
      tail -n +1 -F "$BOOTSTRAP_LOG" 2>&1 | \
      /usr/local/bin/devsigner \
        --priv-hex "$NODE_PRIV_HEX" \
        --node-id   "${NODE_ID:-unknown}" \
        --moniker   "${MONIKER:-unknown}" \
        --public-ip "${PUBLIC_IP:-0.0.0.0}" \
        --input text \
        --stream-type bootstrap \
        --stream-id   bootstrap \
        --stream-name bootstrap \
        --post "$INGEST_URL" \
        --batch 50 --flush 2s
    ) &
  else
    echo "[log-signer] info: bootstrap log not found ($BOOTSTRAP_LOG) — skipping" >&2
  fi
}

# 1) Attach to existing containers
docker ps --format '{{.ID}} {{.Names}}' | while read -r id name; do
  attach_container "$id" "$name"
done

# 2) Tail bootstrap log (host file mounted at /hostlogs)
attach_bootstrap_log

# 3) Attach to future container starts
docker events \
  --filter 'type=container' \
  --filter 'event=start' \
  --format '{{.ID}} {{.Actor.Attributes.name}}' |
while read -r id name; do
  attach_container "$id" "$name"
done

wait
