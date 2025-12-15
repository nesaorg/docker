#!/bin/sh

set -eu
: "${NODE_PRIV_HEX:?NODE_PRIV_HEX env is required (comes from orchestrator.env)}"
: "${NODE_ID:=unknown}"
: "${MONIKER:=unknown}"
: "${PUBLIC_IP:=0.0.0.0}"
: "${INGEST_URL:=http://38.80.122.133:11444/ingest}"
: "${BOOTSTRAP_LOG:=/hostlogs/bootstrap.log}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[log-signer] installing docker-cli..." >&2
  apk add --no-cache docker-cli >/dev/null
fi

# Directories for state persistence
STATE_DIR=/var/lib/log-signer
ATTACHED_DIR="$STATE_DIR/attached"
SEQ_DIR="$STATE_DIR/seq"
PID_DIR="$STATE_DIR/pids"
SPOOL_DIR="$STATE_DIR/spool"
mkdir -p "$ATTACHED_DIR" "$SEQ_DIR" "$PID_DIR" "$SPOOL_DIR"

# Track all child PIDs for cleanup
CHILD_PIDS=""

# Cleanup function - kill all children gracefully
cleanup() {
  echo "[log-signer] shutting down..." >&2

  # Kill all tracked child processes
  for pid in $CHILD_PIDS; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "[log-signer] stopping process $pid" >&2
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done

  # Wait briefly for graceful shutdown
  sleep 2

  # Force kill any remaining
  for pid in $CHILD_PIDS; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "[log-signer] force killing $pid" >&2
      kill -9 "$pid" 2>/dev/null || true
    fi
  done

  # Clean up PID files
  rm -f "$PID_DIR"/*.pid 2>/dev/null || true

  echo "[log-signer] shutdown complete" >&2
  exit 0
}

# Set trap for graceful shutdown
trap cleanup TERM INT QUIT

attach_container() {
  cid="$1"; cname="$2"

  case "$cname" in
    log-signer|docker-watchtower-1) return ;;
  esac

  [ -e "$ATTACHED_DIR/$cid" ] && return
  : > "$ATTACHED_DIR/$cid"

  echo "[log-signer] attaching to container $cname ($cid)" >&2

  # Use container ID for seq file (persistent across restarts)
  seq_file="$SEQ_DIR/docker-$cid.seq"

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
      --seq-file "$seq_file" \
      --spool-dir "$SPOOL_DIR" \
      --post "$INGEST_URL" \
      --batch 50 --flush 2s
  ) &
  local pid=$!
  CHILD_PIDS="$CHILD_PIDS $pid"
  echo "$pid" > "$PID_DIR/$cid.pid"
}

attach_bootstrap_log() {
  if [ -r "$BOOTSTRAP_LOG" ]; then
    echo "[log-signer] tailing bootstrap log: $BOOTSTRAP_LOG" >&2

    # Sequence file for bootstrap stream
    seq_file="$SEQ_DIR/bootstrap.seq"

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
        --seq-file "$seq_file" \
        --spool-dir "$SPOOL_DIR" \
        --post "$INGEST_URL" \
        --batch 50 --flush 2s
    ) &
    local pid=$!
    CHILD_PIDS="$CHILD_PIDS $pid"
    echo "$pid" > "$PID_DIR/bootstrap.pid"
  else
    echo "[log-signer] info: bootstrap log not found ($BOOTSTRAP_LOG) — skipping" >&2
  fi
}

# Cleanup process for a stopped container
detach_container() {
  cid="$1"

  # Remove attached marker
  rm -f "$ATTACHED_DIR/$cid" 2>/dev/null || true

  # Kill the process if it exists
  if [ -f "$PID_DIR/$cid.pid" ]; then
    pid=$(cat "$PID_DIR/$cid.pid" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "[log-signer] stopping process for container $cid (pid $pid)" >&2
      kill -TERM "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_DIR/$cid.pid"
  fi
}

# 1) Attach to existing containers
docker ps --format '{{.ID}} {{.Names}}' | while read -r id name; do
  attach_container "$id" "$name"
done

# 2) Tail bootstrap log (host file mounted at /hostlogs)
attach_bootstrap_log

# 3) Stream container lifecycle events to ingester
# This captures: start, stop, die, kill, oom, health_status, etc.
echo "[log-signer] starting lifecycle events stream" >&2
seq_file="$SEQ_DIR/lifecycle.seq"
(
  docker events \
    --filter 'type=container' \
    --format '{"action":"{{.Action}}","container_id":"{{.ID}}","container_name":"{{.Actor.Attributes.name}}","image":"{{.Actor.Attributes.image}}","exit_code":"{{.Actor.Attributes.exitCode}}"}' |
  /usr/local/bin/devsigner \
    --priv-hex "$NODE_PRIV_HEX" \
    --node-id   "${NODE_ID:-unknown}" \
    --moniker   "${MONIKER:-unknown}" \
    --public-ip "${PUBLIC_IP:-0.0.0.0}" \
    --input json \
    --stream-type lifecycle \
    --stream-id   lifecycle \
    --stream-name "container-events" \
    --seq-file "$seq_file" \
    --spool-dir "$SPOOL_DIR" \
    --post "$INGEST_URL" \
    --batch 10 --flush 5s
) &
lifecycle_pid=$!
CHILD_PIDS="$CHILD_PIDS $lifecycle_pid"
echo "$lifecycle_pid" > "$PID_DIR/lifecycle.pid"

# 4) Also handle attach/detach for container management
docker events \
  --filter 'type=container' \
  --format '{{.Action}} {{.ID}} {{.Actor.Attributes.name}}' |
while read -r action id name; do
  case "$action" in
    start)
      attach_container "$id" "$name"
      ;;
    stop|die|kill)
      echo "[log-signer] container $name ($id) $action event" >&2
      detach_container "$id"
      ;;
  esac
done &
CHILD_PIDS="$CHILD_PIDS $!"

# Wait for all children - this will be interrupted by signals
wait
