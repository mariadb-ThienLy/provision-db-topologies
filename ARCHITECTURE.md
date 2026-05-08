# Architecture

How the topologies are wired, how `mema-agent` registration and server discovery work, and how environment variables flow through the stack.

## mema-agent

The mema-agent is installed and registered on three servers — `standalone`, `primary`, and `maxscale`. It reports metrics to EM via OTLP. The remaining servers (`replica`, Galera nodes, `mxs-server-1`/`-2`/`-3`) run without the agent.

Agent installation is independent of topology registration in EM: the agent reports metrics, but the server still needs to be added as a topology in EM UI separately.

## Adding topologies to EM

All topologies are added through the EM UI (or programmatically via e2e tests). Note that topologies added via e2e tests are scoped to the test session — closing the terminal wipes them out, so for persistent setups use the UI. Once added:

- **Standalone, Primary/Replica, Galera** — each node listed in the topology is added explicitly; no further auto-discovery happens.
- **MaxScale** — once the MaxScale topology is added, the EM backend reaches out to MaxScale's REST API to enumerate the backends:
  - `mxs-server-1` (port 3312) and `mxs-server-2` (port 3313) — discovered as Up.
  - `mxs-server-3` — configured at the RFC 5737 TEST-NET-3 address `192.0.2.3:3314` with no matching service. `mariadbmon` always reports it as Down, exercising EM's handling of an unreachable backend.

## `MEMA_HOSTNAME`

`MEMA_HOSTNAME` is the canonical EM URL used by both EM components and the topology agents. It must resolve to an address reachable from inside Docker containers — **not** `localhost` or `127.0.0.1`, which inside a container resolve to the container itself, not the host. Use the host's LAN IP (e.g. `https://192.168.1.116:8090`).

It flows through the stack as:

- **`mema-agent` endpoint** — derived from `MEMA_HOSTNAME` by stripping the trailing `:port`. Agents in the topology containers connect back to this endpoint to register and report.
- **Keycloak realm template** — substituted at container start into the realm's `rootUrl`, `redirectUris`, and `webOrigins` so the OIDC client matches the EM deployment.

## `ENTERPRISE_TOKEN`

Consumed at image build time to fetch the enterprise repositories, then scrubbed from the final image. It does not appear in any running container's environment.

## GUI override mount strategy

`docker-compose.override.yml` defines a bind mount for the EM frontend, controlled by `SUPERMAX_GUI_DIR`:

- **`SUPERMAX_GUI_DIR` set** → bind-mounts the host directory (e.g. a locally-built `enterprise-manager-frontend/dist/`) read-only into the frontend container.
- **`SUPERMAX_GUI_DIR` unset** → falls back to the `supermax-original-gui` named volume, which Docker auto-populates from the image's shipped GUI on first start.

### Current architecture (combined backend/frontend)

The `supermax` image serves both the backend and the frontend from `/usr/share/supermax/gui`. The override is wired in this repo:

```yaml
services:
  supermax:
    volumes:
      - ${SUPERMAX_GUI_DIR:-supermax-original-gui}:/usr/share/supermax/gui:ro
```

### New architecture (separated backend/frontend)

In the `enterprise-manager-distrib` distribution, `supermax` is the backend only and a separate `nginx` service (image: `enterprise-manager-frontend`) serves the GUI from `/usr/share/nginx/html`. Extend the `nginx` service in `docker-compose.override.yml`:

```yaml
services:
  nginx:
    volumes:
      - ${SUPERMAX_GUI_DIR}:/usr/share/nginx/html:ro
```

When building the frontend for this architecture, set `VITE_API_BASE_URL=/api` before running the build:

```bash
export VITE_API_BASE_URL=/api && npm run build-only
```


For running e2e tests locally, configure the env vars via `.env.development` in the `enterprise-manager-frontend` repo:

**Against the new backend:**
The `VITE_API_BASE_URL` override is only needed for the new backend, since the old combined `supermax` image serves the REST API at the root.
```
VITE_API_BASE_URL=/api
VITE_PLAYWRIGHT_BASE_URL=<your MEMA_HOSTNAME>    # e.g. https://192.168.1.116:8090
USERNAME=admin
PASSWORD=mariadb
```

**Against the old backend:**

```
VITE_PLAYWRIGHT_BASE_URL=<your MEMA_HOSTNAME>    # e.g. https://192.168.1.116:8090
USERNAME=admin
PASSWORD=mariadb
```
