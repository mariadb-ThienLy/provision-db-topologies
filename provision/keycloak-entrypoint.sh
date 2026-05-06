#!/bin/sh
# Templating wrapper around the keycloak image entrypoint. Keycloak's `${env.X}`
# substitution works in `keycloak.conf` but NOT in realm JSON imports, so we
# expand `${MEMA_HOSTNAME}` ourselves before kc.sh starts.
#
# The realm template is mounted read-only at /tmp/keycloak-realm.json (via
# compose `configs:`); the rendered file is written into the import dir where
# Keycloak's DirImportProvider picks it up.
set -e

mkdir -p /opt/keycloak/data/import
sed "s|\${MEMA_HOSTNAME}|${MEMA_HOSTNAME}|g" \
  /tmp/keycloak-realm.json \
  > /opt/keycloak/data/import/enterprise-manager-realm.json

exec /opt/keycloak/bin/kc.sh "$@"
