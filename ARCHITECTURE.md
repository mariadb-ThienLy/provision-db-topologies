# Architecture

How the topologies are wired, how `mema-agent` registration and server discovery work, and how environment variables flow through the stack.

## mema-agent

The mema-agent is installed and registered on three servers — `standalone`, `primary`, and `maxscale`. It reports metrics to EM via OTLP. The remaining servers (`replica`, Galera nodes, `mxs-server-1`/`-2`/`-3`) and the second MaxScale (`maxscale-2`) run without the agent.

Agent installation is independent of topology registration in EM: the agent reports metrics, but the server still needs to be added as a topology in EM UI separately.

## Adding topologies to EM

All topologies are added through the EM UI (or programmatically via e2e tests). Note that topologies added via e2e tests are scoped to the test session — closing the terminal wipes them out, so for persistent setups use the UI. Once added:

- **Standalone, Primary/Replica, Galera** — each node listed in the topology is added explicitly; no further auto-discovery happens.
- **MaxScale** — once the MaxScale topology is added, the EM backend reaches out to MaxScale's REST API to enumerate the backends:
  - `mxs-server-1` (port 3312) and `mxs-server-2` (port 3313) — discovered as Up.
  - `mxs-server-3` — configured at the RFC 5737 TEST-NET-3 address `192.0.2.3:3314` with no matching service. `mariadbmon` always reports it as Down, exercising EM's handling of an unreachable backend.

## Second MaxScale (cooperative monitoring)

`maxscale-2` is a second MaxScale fronting the same backends as `maxscale`, exposed on different host ports — REST/GUI on `8999`, SQL on `4007` (vs. `8989`/`4006` for the first). It runs no `mema-agent` and is not registered in EM; it exists to exercise MaxScale's cooperative monitoring.

Both instances share the `maxscale-cnf` config, so their monitors carry the same name and `cooperative_monitoring_locks=majority_of_running`. The two MaxScales then elect a single active monitor that holds the lock — only that instance runs `auto_failover`/`auto_rejoin`, while the other stays passive. This mirrors a production HA setup where two MaxScales front one cluster without both attempting failover.

## `MEMA_HOSTNAME`

`MEMA_HOSTNAME` is the canonical EM URL used by both EM components and the topology agents. It must resolve to an address reachable from inside Docker containers — **not** `localhost` or `127.0.0.1`, which inside a container resolve to the container itself, not the host. Use the host's LAN IP (e.g. `https://192.168.1.116:8090`).

It flows through the stack as:

- **`mema-agent` endpoint** — derived from `MEMA_HOSTNAME` by stripping the trailing `:port`. Agents in the topology containers connect back to this endpoint to register and report.
- **Keycloak realm template** — substituted at container start into the realm's `rootUrl`, `redirectUris`, and `webOrigins` so the OIDC client matches the EM deployment.

## `ENTERPRISE_TOKEN`

Consumed at image build time to fetch the enterprise repositories, then scrubbed from the final image. It does not appear in any running container's environment.

## GUI override mount strategy

`gui-override/docker-compose.override.yml` is a standalone overlay, separate from the topology stack (`docker-compose.yml`). It lives in its own `gui-override/` dir precisely so it does **not** auto-merge into the topology stack on a bare `docker compose up`. It is copied into the **EM deployment dir**, where Compose merges it with that deployment's own `docker-compose.yml` (the one defining the `supermax`/`nginx` services). It defines a bind mount for the EM frontend, controlled by `SUPERMAX_GUI_DIR`:

- **`SUPERMAX_GUI_DIR` set** → bind-mounts the host directory (e.g. a locally-built `enterprise-manager-frontend/dist/`) read-only into the frontend container.
- **`SUPERMAX_GUI_DIR` unset** → falls back to the `supermax-original-gui` named volume, which Docker auto-populates from the image's shipped GUI on first start.

### Old architecture (combined backend/frontend)

The `supermax` image serves both the backend and the frontend from `/usr/share/supermax/gui`. This is the case the shipped `docker-compose.override.yml` targets:

```yaml
services:
  supermax:
    volumes:
      - ${SUPERMAX_GUI_DIR:-supermax-original-gui}:/usr/share/supermax/gui:ro
```

### New architecture (separated backend/frontend)

In the `enterprise-manager-distrib` distribution, `supermax` is the backend only and a separate `nginx` service (image: `enterprise-manager-frontend`) serves the GUI from `/usr/share/nginx/html`. The bundled image already supports the new backend, so running the latest e2e tests against it requires no override.

To run a locally-built frontend against the new backend — e.g. when developing new features or extending tests before opening a PR (so unmerged tests aren't yet in the bundled image) — extend the `nginx` service in `docker-compose.override.yml`:

```yaml
services:
  nginx:
    volumes:
      - ${SUPERMAX_GUI_DIR}:/usr/share/nginx/html:ro
```

The frontend targets this architecture by default — it calls the REST API at `/api`, so no build-time configuration is needed:

```bash
npm run build-only
```

For running e2e tests locally, configure the env vars via `.env.development` in the `enterprise-manager-frontend` repo:

**Against the new backend (default):**
```
VITE_PLAYWRIGHT_BASE_URL=<your MEMA_HOSTNAME>    # e.g. https://192.168.1.116:8090
USERNAME=admin
PASSWORD=mariadb
```

**Against the old backend:**
The old combined `supermax` image serves the REST API at the root, so point the frontend at `/` instead of `/api` by editing three source files before building:

- `e2e/api.ts` — drop the `/api` suffix from `API_URL`
- `src/apiClient.js` — change `baseURL: '/api'` to `baseURL: '/'`
- `src/components/workspace/setupMariaDBWorkspace.ts` — change `baseURL: '/api'` to `baseURL: '/'`

The `.env.development` is identical to the new-backend case. The `refactor/support-tests-against-old-be` branch already carries these edits but is no longer maintained.
