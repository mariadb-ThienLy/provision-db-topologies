# Mount a custom frontend build

Optional. Only needed to serve a locally-built GUI — e.g. e2e tests against the old combined backend (its bundled GUI lacks test support), or testing unmerged frontend changes. The override (`gui-override/docker-compose.override.yml`) bind-mounts a `dist/` build into the GUI-serving container.

For the mount strategy and the old-vs-new backend differences, see [ARCHITECTURE.md#gui-override-mount-strategy](ARCHITECTURE.md#gui-override-mount-strategy).

## Build the frontend

The new/separated backend is the default and needs no extra config:

```bash
cd /home/thien/workspace/em-space/enterprise-manager-frontend
npm ci && npm run build-only
```

For the **old combined backend**, the override and build need extra edits (target the `supermax` service; point the API at `/` instead of `/api`) — see [ARCHITECTURE.md#gui-override-mount-strategy](ARCHITECTURE.md#gui-override-mount-strategy).

## Apply the override

Copy the override into the EM deployment dir and point `SUPERMAX_GUI_DIR` at the build:

```bash
cp gui-override/docker-compose.override.yml \
   /home/thien/workspace/em-space/enterprise-manager/

echo 'SUPERMAX_GUI_DIR=/home/thien/workspace/em-space/enterprise-manager-frontend/dist' \
  >> /home/thien/workspace/em-space/enterprise-manager/.env
```

Restart the EM deployment so the override takes effect:

```bash
cd /home/thien/workspace/em-space/enterprise-manager && docker compose up -d --wait
```

The mount is read-only. After a rebuild, `docker compose restart nginx` (or `supermax` for the old backend) picks it up — no full restart needed. To revert, remove `SUPERMAX_GUI_DIR` from the deployment's `.env` and re-run `docker compose up -d`.
