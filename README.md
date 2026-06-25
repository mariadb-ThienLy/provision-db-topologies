# Provision DB Topologies for Enterprise Manager

Docker-based MariaDB topologies for testing Enterprise Manager. The `mema-agent` is preinstalled on `standalone`, `primary`, and `maxscale` (reporting metrics via OTLP). Topologies are added through the EM UI; once a MaxScale topology is added, EM auto-discovers its backends. A Keycloak instance is included to test EM's OIDC SSO integration.

This repo holds two pieces that deploy to **different directories**:

- **`docker-compose.yml` + `provision/`** — the self-contained topology stack (standalone, primary/replica, Galera, the MaxScale pair, and Keycloak). Copied into a working dir and run on its own.
- **`docker-compose.override.yml`** — a small overlay that mounts a locally-built EM frontend into the `supermax` container. Copied into the **EM deployment dir**, where it overlays that deployment's own `docker-compose.yml`. Only needed for running e2e tests against the **old (combined) backend** with a custom FE build.

For how the topologies discover servers, how `MEMA_HOSTNAME` flows through the stack, and how the GUI override mount works, see [ARCHITECTURE.md](ARCHITECTURE.md).

## 1. Bring up the topology stack

Copy the stack into your working dir (e.g. `em-test-topologies/`) and switch into it:

```bash
cd /home/thien/workspace/em-space/provision-db-topologies && \
  cp docker-compose.yml provision .env -r -t /home/thien/workspace/em-space/em-test-topologies/ && \
  cd /home/thien/workspace/em-space/em-test-topologies/
```

Edit the copied `.env` (committed alongside the stack in the working dir) with two values:

```
MEMA_HOSTNAME=https://192.168.1.116:8090   # host LAN IP — not localhost / 127.0.0.1
ENTERPRISE_TOKEN=your_token_here           # from https://customers.mariadb.com/downloads/token/
```

- `MEMA_HOSTNAME` must resolve to an address reachable from inside the containers — see [ARCHITECTURE.md#mema_hostname](ARCHITECTURE.md#mema_hostname) for why `localhost` fails.
- `ENTERPRISE_TOKEN` is consumed at image build time to pull the enterprise repositories, then scrubbed from the image — see [ARCHITECTURE.md#enterprise_token](ARCHITECTURE.md#enterprise_token).

Start everything:

```bash
docker compose up -d --wait
```

## 2. (Optional) Mount a custom frontend build

Skip this unless you need a locally-built GUI — e.g. running e2e tests against the **old combined backend** (whose bundled GUI lacks e2e test support), or developing/extending the frontend before opening a PR. You build the frontend locally and mount its `dist/` into the GUI-serving container via `docker-compose.override.yml`.

Which container is the GUI-serving one depends on the backend (see [ARCHITECTURE.md#gui-override-mount-strategy](ARCHITECTURE.md#gui-override-mount-strategy)):

- **Old (combined) backend** → `supermax` serves the GUI from `/usr/share/supermax/gui`. This is what the shipped override targets.
- **New (separated) backend** → `nginx` serves the GUI from `/usr/share/nginx/html`. Edit the override: change the service to `nginx` and the mount path accordingly (the override file documents this inline).

**Build the frontend** (see the `enterprise-manager-frontend` repo README for prerequisites). The frontend now targets the **new (separated) backend** by default — it calls the REST API at `/api`, so no extra configuration is needed:

```bash
cd /home/thien/workspace/em-space/enterprise-manager-frontend
npm ci
npm run build-only
```

For the **old (combined) backend**, the API is served at the root, so point the frontend at `/` instead of `/api` by editing three source files before building:

- `e2e/api.ts` — drop the `/api` suffix:
  ```ts
  export const API_URL = `${process.env.VITE_PLAYWRIGHT_BASE_URL ?? ''}`
  ```
- `src/apiClient.js` — change `baseURL: '/api'` to `baseURL: '/'`
- `src/components/workspace/setupMariaDBWorkspace.ts` — change `baseURL: '/api'` to `baseURL: '/'`

Then run `npm run build-only`. The `refactor/support-tests-against-old-be` branch already carries these edits and can still be used, but it's no longer maintained (won't receive new commits) — applying the edits on the latest branch is preferred.

`npm run build-only` writes the build into `dist/` inside the frontend repo (`enterprise-manager-frontend/dist`). Move it outside the repo so a subsequent rebuild for the other backend doesn't overwrite it — e.g. the old-backend build to `old_fe_dist`:

```bash
mv /home/thien/workspace/em-space/enterprise-manager-frontend/dist \
   /home/thien/workspace/em-space/old_fe_dist
```

**Copy the override into the EM deployment dir and point `SUPERMAX_GUI_DIR` at the build** (edit the service/path for the new backend first):

```bash
cp /home/thien/workspace/em-space/provision-db-topologies/docker-compose.override.yml \
   /home/thien/workspace/em-space/enterprise-manager/

cat >> /home/thien/workspace/em-space/enterprise-manager/.env <<'EOF'
SUPERMAX_GUI_DIR=/home/thien/workspace/em-space/old_fe_dist
EOF
```

**Restart the EM deployment** so the override takes effect:

```bash
cd /home/thien/workspace/em-space/enterprise-manager && docker compose up -d --wait
```

The mount is read-only and reflects subsequent `vite build` runs on the next page reload. After a rebuild, refresh the running container without a full restart (`supermax` for the old backend, `nginx` for the new):

```bash
docker compose restart supermax   # or: nginx
```

To revert to the bundled GUI later, remove `SUPERMAX_GUI_DIR` from the EM deployment's `.env` and run `docker compose up -d`.

## 3. Run the e2e tests

Configure `.env.development` in the `enterprise-manager-frontend` repo:

```
VITE_PLAYWRIGHT_BASE_URL=<MEMA_HOSTNAME>    # e.g. https://192.168.1.116:8090
USERNAME=admin
PASSWORD=mariadb
```

(The backend the tests run against is fixed by the frontend build, not by `.env.development` — see [step 2](#2-optional-mount-a-custom-frontend-build).)

> **Reset the admin password first.** The e2e suite hard-codes the app credentials `admin` / `mariadb`. Enterprise Manager generates a long random admin password on first start, so before running the tests you must change it back to `mariadb` — otherwise login fails and every spec errors.

Install Playwright browsers once (needed for Firefox/WebKit):

```bash
npx playwright install
```

Then run the suite:

```bash
npm run test:e2e        # headless, all browsers (chromium, firefox, webkit)
npm run test:e2e:ui     # UI mode — recommended for inspecting failures
```

Scope a run by passing a spec path: `npm run test:e2e -- e2e/specs/profile.spec.ts`.

Narrow the browser set with `E2E_BROWSERS` — a comma-separated list of `chromium`, `firefox`, and/or `webkit`; unset runs all three. For example, chromium only:

```bash
E2E_BROWSERS=chromium npm run test:e2e
```

CI runs one browser per matrix job: `run_e2e` runs **chromium** only, while the all-browsers matrix runs on the nightly schedule or with the `run_e2e_all_browsers` PR label. A manual run (Actions → E2E Tests → Run workflow) picks the browser from a dropdown, defaulting to `chromium`.

## Available Topologies

- **Standalone** — Single MariaDB server on port 3306
- **Primary/Replica** — Primary on port 3307, replica on port 3308
- **Galera Cluster** — Three-node cluster on ports 3309–3311
- **Primary/Replica with MaxScale** — MaxScale REST API on port 8989, SQL listener on port 4006, backends on ports 3312–3314. A second MaxScale (`maxscale-2`) fronts the same backends on ports 8999 (REST) and 4007 (SQL), forming a cooperative-monitoring pair — see [ARCHITECTURE.md](ARCHITECTURE.md#second-maxscale-cooperative-monitoring)

## Keycloak (OIDC SSO)

A Keycloak instance is started on port 8080 with the `enterprise-manager` realm preimported.

- **Admin console:** http://localhost:8080 — `admin` / `admin`
- **Realm:** `enterprise-manager`
- **Client ID:** `enterprise-manager`
- **Test user:** `keycloak-user` / `mariadb`

### Configure OIDC in Enterprise Manager

Navigate to `https://<MEMA_HOSTNAME>/#/settings/identity-provider/oidc` and enter:

- **Authentication URL:** `http://127.0.0.1:8080/realms/enterprise-manager`
- **Client ID:** `enterprise-manager`
- **Authentication Flow:** `auto`
- **Client Secret:** `mariadb`

After saving, log out and press F5 to reveal the **Sign In With SSO** button. Clicking it redirects to the Keycloak login page — sign in with `keycloak-user` / `mariadb`.
