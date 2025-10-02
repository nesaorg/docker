
#!/bin/sh
set -eu

: "${INGEST_URL:=http://host.docker.internal:8080/ingest}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[log-signer] installing docker-cli..." >&2
  apk add --no-cache docker-cli >/dev/null
fi

ATTACHED_DIR=/var/lib/log-signer/attached
mkdir -p "$ATTACHED_DIR"

attach() {
  cid="$1"; cname="$2"

  case "$cname" in
    log-signer|docker-watchtower-1) return ;;
  esac

  [ -e "$ATTACHED_DIR/$cid" ] && return
  : > "$ATTACHED_DIR/$cid"

  echo "[log-signer] attaching to $cname ($cid)" >&2

  (
    docker logs -f --since 0 "$cid" 2>&1 | \
    /usr/local/bin/devsigner \
      --priv-hex "$NODE_PRIV_HEX" \
      --node-id   "$NODE_ID" \
      --moniker   "$MONIKER" \
      --public-ip "$PUBLIC_IP" \
      --input text \
      --stream-type docker \
      --stream-id   "$cname" \
      --stream-name "$cname" \
      --post "$INGEST_URL" \
      --batch 50 --flush 2s
  ) &
}

docker ps --format '{{.ID}} {{.Names}}' |
while read -r id name; do attach "$id" "$name"; done

docker events \
  --filter 'type=container' \
  --filter 'event=start' \
  --format '{{.ID}} {{.Actor.Attributes.name}}' |
while read -r id name; do attach "$id" "$name"; done

wait
