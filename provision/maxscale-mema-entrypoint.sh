#!/usr/bin/env bash
# Boots MaxScale and the mema-agent in one container. MaxScale runs in the
# foreground (`maxscale --nodaemon`); the agent runs in the foreground via
# `mema-agent run`. If either child dies the wrapper exits, so compose's
# `restart: always` brings the whole thing back together.

set -u

cleanup() {
  [ -n "${AGENT_PID:-}" ]    && kill -TERM "$AGENT_PID"    2>/dev/null || true
  [ -n "${MAXSCALE_PID:-}" ] && kill -TERM "$MAXSCALE_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup TERM INT

# /run is a tmpfs and gets remounted at container start, so the package's
# /run/maxscale (created by postinst) doesn't survive. Recreate it here —
# the systemd unit relies on `RuntimeDirectory=maxscale` for the same
# effect, which we don't have outside systemd.
install -d -m 0755 -o maxscale -g maxscale /run/maxscale

maxscale --user=maxscale --nodaemon &
MAXSCALE_PID=$!

# REST API has to be live before mema-agent setup can authenticate.
echo "[maxscale-mema] waiting for MaxScale REST API on :8989..."
for i in $(seq 1 120); do
  if curl -sf -o /dev/null -u admin:mariadb http://127.0.0.1:8989/v1/maxscale; then
    echo "[maxscale-mema] MaxScale REST API is up"
    break
  fi
  if [ "$i" -eq 120 ]; then
    echo "[maxscale-mema] MaxScale never came up" >&2
    cleanup
    exit 1
  fi
  sleep 1
done

# Idempotent: setup once per container fs lifetime.
if [ ! -f /var/lib/mema-agent/mema-agent-otelcol.yaml ]; then
  MEMA_ENDPOINT="${MEMA_HOSTNAME%:[0-9]*}"
  echo "[maxscale-mema] running mema-agent setup (endpoint=${MEMA_ENDPOINT})..."
  mema-agent setup --skip-start \
    --endpoint="${MEMA_ENDPOINT}" \
    --cluster-name="${MEMA_CLUSTER_NAME}" \
    --host-name="${MEMA_HOST_NAME}" \
    --maxscale \
    --maxscale-host="http://127.0.0.1:8989" \
    --maxscale-user="admin" \
    --maxscale-password="mariadb" \
    --maxscale-insecure \
    --otlp-interval="10s" \
    --otlp-insecure
fi

echo "[maxscale-mema] starting mema-agent run..."
mema-agent run --verbose &
AGENT_PID=$!

wait -n
EXIT=$?
echo "[maxscale-mema] child exited (status=${EXIT}); shutting down"
cleanup
exit "$EXIT"
