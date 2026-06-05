# Provision DB Topologies for Enterprise Manager

Docker-based MariaDB topologies for testing Enterprise Manager. The `mema-agent` is preinstalled on `standalone`, `primary`, and `maxscale` (reporting metrics via OTLP). Topologies are added through the EM UI; once a MaxScale topology is added, EM auto-discovers its backends. A Keycloak instance is included to test EM's OIDC SSO integration.

For how the topologies discover servers, how `MEMA_HOSTNAME` flows through the stack, and how the GUI override mount works, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Quick Setup

**1. Copy provisioning files**

```bash
cp -r provision/ <em-dir>/
cp docker-compose.override.yml <em-dir>/
```

**2. Configure `<em-dir>/.env` before the first bring-up**

Add `ENTERPRISE_TOKEN` — get one from https://customers.mariadb.com/downloads/token/:

```bash
cat >> <em-dir>/.env <<'EOF'
ENTERPRISE_TOKEN=your_token_here
EOF
```

Update `MEMA_HOSTNAME` (already present from the EM setup) to a host-reachable address — not `localhost` or `127.0.0.1`. Use your host's LAN IP, e.g.:

```
MEMA_HOSTNAME=https://192.168.1.116:8090
```

See [ARCHITECTURE.md#mema_hostname](ARCHITECTURE.md#mema_hostname) for why `localhost` fails from inside containers.

For e2e against the **old backend**, first build the FE locally (see the `enterprise-manager-frontend` repo README for prerequisites):

```bash
cd /path/to/enterprise-manager-frontend
npm ci
npm run build-only
```

Then point `SUPERMAX_GUI_DIR` at the resulting `dist/` (see [ARCHITECTURE.md#gui-override-mount-strategy](ARCHITECTURE.md#gui-override-mount-strategy) for how the bind mount and fallback volume work):

```bash
cat >> <em-dir>/.env <<'EOF'
SUPERMAX_GUI_DIR=/path/to/enterprise-manager-frontend/dist
EOF
```

**3. Start the stack**

```bash
cd <em-dir> && docker compose up -d --wait
```

**4. Configure `.env.development` in the `enterprise-manager-frontend` repo**

Against the **new backend** (bundled FE image):

```
VITE_API_BASE_URL=/api
VITE_PLAYWRIGHT_BASE_URL=<MEMA_HOSTNAME>
USERNAME=admin
PASSWORD=mariadb
```

Against the **old backend** (locally-built FE via `SUPERMAX_GUI_DIR`):

```
VITE_PLAYWRIGHT_BASE_URL=<MEMA_HOSTNAME>
USERNAME=admin
PASSWORD=mariadb
```

**5. Run the tests from the FE repo**

Install Playwright browsers once:

```bash
npx playwright install
```

Then run the suite:

```bash
npm run test:e2e        # headless
npm run test:e2e:ui     # UI mode — recommended for inspecting failures
```

For the old-backend path, restart `supermax` after each `vite build` so it picks up the new bundle:

```bash
docker compose restart supermax
```

To revert to the bundled GUI later, remove `SUPERMAX_GUI_DIR` from `.env` and run `docker compose up -d supermax`.

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
