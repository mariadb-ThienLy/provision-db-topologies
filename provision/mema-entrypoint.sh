#!/usr/bin/env bash
# Boots mariadbd and the mema-agent in one container. mariadbd runs in the
# background via the stock docker-entrypoint.sh; the agent runs in the
# foreground via `mema-agent run` (no systemd needed). If either child dies
# the wrapper exits, so compose's `restart: always` brings the whole thing
# back together.

set -u

cleanup() {
  [ -n "${AGENT_PID:-}" ]   && kill -TERM "$AGENT_PID"   2>/dev/null || true
  [ -n "${MARIADB_PID:-}" ] && kill -TERM "$MARIADB_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup TERM INT

# Hand mariadbd args ($@) to the original entrypoint.
docker-entrypoint.sh "$@" &
MARIADB_PID=$!

# Wait via UNIX socket — works regardless of mariadbd's TCP port.
echo "[mema-bootstrap] waiting for mariadbd socket..."
for i in $(seq 1 120); do
  if mariadb-admin ping -uroot -p"${MARIADB_ROOT_PASSWORD}" --silent 2>/dev/null; then
    echo "[mema-bootstrap] mariadbd is up"
    break
  fi
  if [ "$i" -eq 120 ]; then
    echo "[mema-bootstrap] mariadbd never came up" >&2
    cleanup
    exit 1
  fi
  sleep 1
done

# Idempotent: setup once per container fs lifetime.
if [ ! -f /var/lib/mema-agent/mema-agent-otelcol.yaml ]; then
  # Derive endpoint from MEMA_HOSTNAME by stripping a trailing :port (e.g.
  # https://host:8090 -> https://host). Pattern only matches numeric ports
  # so a portless URL passes through unchanged.
  MEMA_ENDPOINT="${MEMA_HOSTNAME%:[0-9]*}"
  echo "[mema-bootstrap] running mema-agent setup (endpoint=${MEMA_ENDPOINT})..."
  mema-agent setup --skip-start \
    --endpoint="${MEMA_ENDPOINT}" \
    --cluster-name="${MEMA_CLUSTER_NAME}" \
    --host-name="${MEMA_HOST_NAME}" \
    --mariadb \
    --mariadb-port="${MEMA_DB_PORT:-3306}" \
    --mariadb-user="${MEMA_DB_USER:-root}" \
    --mariadb-password="${MEMA_DB_PASSWORD:-${MARIADB_ROOT_PASSWORD}}" \
    --otlp-insecure
fi

echo "[mema-bootstrap] starting mema-agent run..."
mema-agent run --verbose &
AGENT_PID=$!

# Exit when either child exits, propagate status.
wait -n
EXIT=$?
echo "[mema-bootstrap] child exited (status=${EXIT}); shutting down"
cleanup
exit "$EXIT"
