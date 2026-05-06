#!/usr/bin/env bash
# Galera entrypoint: decides whether to bootstrap a new cluster, join an
# existing one, or wait for a peer — based on grastate.dat and live peer
# reachability. Avoids the trap of hardcoding `--wsrep-new-cluster` in
# `command:` (which forces a fresh cluster on every restart) and the trap of
# starting mariadbd when no primary view is possible (which would crash, get
# auto-restarted, and on each retry rewrite `seqno: -1` into grastate.dat,
# destroying the information needed for manual recovery).
#
#   - No grastate.dat AND GALERA_PREFER_BOOTSTRAP=1                 → bootstrap
#   - safe_to_bootstrap: 1                                          → bootstrap
#   - GALERA_PREFER_BOOTSTRAP=1 AND no peer after the deadline      → bootstrap
#   - Otherwise                                                     → wait for
#                                                                     any peer
#                                                                     on tcp:4567
#                                                                     then join
#
# Why the timed force-bootstrap: docker compose stop (and OS shutdown) often
# fail to leave any node with safe_to_bootstrap=1, because dockerd's parallel
# SIGTERM doesn't give mariadbd time to register "I'm the last node" and write
# the flag. Without a fallback, the cluster would refuse to start on every
# reboot. Only galera-1 (PREFER_BOOTSTRAP=1) is allowed to force-bootstrap, so
# there's no split-brain risk.

set -u

GRASTATE=/var/lib/mysql/grastate.dat
PREFER_BOOTSTRAP="${GALERA_PREFER_BOOTSTRAP:-0}"
PEERS="${GALERA_PEERS:-galera-1 galera-2 galera-3}"
FORCE_BOOTSTRAP_AFTER_SEC="${GALERA_FORCE_BOOTSTRAP_AFTER:-30}"

# 1. Immediate bootstrap if grastate says so, or if there's no state at all.
bootstrap=0
if [ ! -f "$GRASTATE" ]; then
  if [ "$PREFER_BOOTSTRAP" = "1" ]; then
    echo "[galera-entrypoint] no grastate.dat — bootstrapping new cluster"
    bootstrap=1
  fi
elif grep -qE '^safe_to_bootstrap:[[:space:]]*1' "$GRASTATE"; then
  echo "[galera-entrypoint] safe_to_bootstrap=1 — bootstrapping new cluster"
  bootstrap=1
fi

if [ "$bootstrap" = "1" ]; then
  exec docker-entrypoint.sh "$@" --wsrep-new-cluster
fi

# 2. Otherwise, wait for a peer. galera-1 force-bootstraps after a deadline so
#    the cluster can recover even when no node carries safe_to_bootstrap=1.
echo "[galera-entrypoint] not bootstrapping — probing peers on tcp:4567 (galera-1 will force-bootstrap after ${FORCE_BOOTSTRAP_AFTER_SEC}s)"
elapsed=0
while :; do
  for peer in $PEERS; do
    if timeout 1 bash -c "exec 3<>/dev/tcp/$peer/4567" 2>/dev/null; then
      echo "[galera-entrypoint] peer $peer reachable — joining cluster"
      exec docker-entrypoint.sh "$@"
    fi
  done

  if [ "$PREFER_BOOTSTRAP" = "1" ] && [ "$elapsed" -ge "$FORCE_BOOTSTRAP_AFTER_SEC" ]; then
    echo "[galera-entrypoint] no peer after ${elapsed}s — force-bootstrapping"
    [ -f "$GRASTATE" ] && sed -i 's/^safe_to_bootstrap:.*$/safe_to_bootstrap: 1/' "$GRASTATE"
    exec docker-entrypoint.sh "$@" --wsrep-new-cluster
  fi

  sleep 5
  elapsed=$((elapsed + 5))
done
