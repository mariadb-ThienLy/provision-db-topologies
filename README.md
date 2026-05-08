# Provision DB Topologies for Enterprise Manager

Docker-based MariaDB topologies for testing Enterprise Manager. The `mema-agent` is preinstalled on `standalone`, `primary`, and `maxscale` (reporting metrics via OTLP). Topologies are added through the EM UI; once a MaxScale topology is added, EM auto-discovers its backends. A Keycloak instance is included to test EM's OIDC SSO integration.

For how the topologies discover servers, how `MEMA_HOSTNAME` flows through the stack, and how the GUI override mount works, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Setup

1. **Copy the provisioning files into your existing `enterprise-manager` directory:**

   ```bash
   cp -r provision/ <path-to-enterprise-manager>/
   cp docker-compose.override.yml <path-to-enterprise-manager>/
   ```

2. **Add `ENTERPRISE_TOKEN` to `.env`.** Get your enterprise token from https://customers.mariadb.com/downloads/token/

   ```bash
   cat >> <path-to-enterprise-manager>/.env <<'EOF'
   ENTERPRISE_TOKEN=your_token_here
   EOF
   ```

3. **Update `MEMA_HOSTNAME` in `.env`** (it already exists from the EM setup) to a host-reachable address — not `localhost` or `127.0.0.1`. Use your host's LAN IP, e.g.:

   ```
   MEMA_HOSTNAME=https://192.168.1.116:8090
   ```

4. **Start the containers:**

   ```bash
   cd <path-to-enterprise-manager>
   docker compose up -d --wait
   ```

## Available Topologies

- **Standalone** — Single MariaDB server on port 3306
- **Primary/Replica** — Primary on port 3307, replica on port 3308
- **Galera Cluster** — Three-node cluster on ports 3309–3311
- **Primary/Replica with MaxScale** — MaxScale REST API on port 8989, SQL listener on port 4006, backends on ports 3312–3314

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

## Running E2E Tests Locally

Override the bundled GUI with a locally-built `enterprise-manager-frontend/dist/` to run Playwright/E2E suites against a known frontend revision.

1. **Clone and build the frontend** by following the README in the enterprise manager frontend` repository.

2. **Set `SUPERMAX_GUI_DIR` in `.env`:**

   ```bash
   cat >> <path-to-enterprise-manager>/.env <<'EOF'
   SUPERMAX_GUI_DIR=/home/user/workspace/enterprise-manager-frontend/dist
   EOF
   ```

3. **Bring up and restart after each `vite build`:**

   ```bash
   docker compose up -d supermax
   docker compose restart supermax
   ```

For the upcoming separated backend/frontend architecture, see [ARCHITECTURE.md](ARCHITECTURE.md#new-architecture-separated-backendfrontend).

### Reverting to the original GUI

Leave `SUPERMAX_GUI_DIR` unset (or remove it from `.env`) and bring the service back up:

```bash
docker compose up -d supermax
```
