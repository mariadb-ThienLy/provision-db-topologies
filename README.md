# Provision DB Topologies for Enterprise Manager

Docker-based MariaDB topologies (standalone, primary/replica, Galera, a MaxScale pair) plus a Keycloak instance for testing Enterprise Manager (EM) — its server discovery, metrics agent, and OIDC SSO. Topologies are registered through the EM UI.

The repo has two deployable pieces:

- **`docker-compose.yml` + `topologies/` + `provision/`** — the self-contained topology stack, brought up as a whole. Copied into a working dir and run from there ([step 1](#1-bring-up-the-topology-stack)).
- **`gui-override/docker-compose.override.yml`** — optional overlay to mount a locally-built EM frontend; copied into the EM deployment dir ([step 2](#2-optional-mount-a-custom-frontend-build)).

See [ARCHITECTURE.md](ARCHITECTURE.md) for how everything is wired.

## 1. Bring up the topology stack

`em-test-topologies/` is git-ignored, so keep the working copy inside this repo and use relative paths. From the repo root:

```bash
mkdir -p em-test-topologies && \
  cp -r docker-compose.yml topologies provision .env -t em-test-topologies/ && \
  cd em-test-topologies/
```

Edit the copied `.env`:

```
MEMA_HOSTNAME=https://192.168.1.116:8090   # host LAN IP — not localhost / 127.0.0.1
ENTERPRISE_TOKEN=your_token_here           # from https://customers.mariadb.com/downloads/token/
```

What these do, and why `localhost` fails inside containers: see [ARCHITECTURE.md#mema_hostname](ARCHITECTURE.md#mema_hostname) and [#enterprise_token](ARCHITECTURE.md#enterprise_token).

Start everything:

```bash
docker compose up -d --wait
```

## 2. (Optional) Mount a custom frontend build

Needed only to serve a locally-built GUI — e.g. e2e tests against the old combined backend, or testing unmerged frontend changes. See [GUI_OVERRIDE.md](GUI_OVERRIDE.md).

## 3. Run the e2e tests

In the `enterprise-manager-frontend` repo, set `.env.development`:

```
VITE_PLAYWRIGHT_BASE_URL=<MEMA_HOSTNAME>    # e.g. https://192.168.1.116:8090
USERNAME=admin
PASSWORD=mariadb
```

> **Reset the admin password to `mariadb` first.** EM generates a random admin password on first start; the suite hard-codes `admin` / `mariadb`, so every spec fails to log in otherwise.

Install Playwright browsers once, then run the suite:

```bash
npx playwright install
npm run test:e2e        # headless, all browsers (chromium, firefox, webkit)
npm run test:e2e:ui     # UI mode — recommended for inspecting failures
```

- Scope to a spec: `npm run test:e2e -- e2e/specs/profile.spec.ts`
- Pick browsers: `E2E_BROWSERS=chromium npm run test:e2e` (comma-separated; unset runs all three)

CI runs chromium on PRs; all browsers run on the nightly schedule or with the `run_e2e_all_browsers` PR label.

## Available Topologies

All ports bind to `127.0.0.1`. MariaDB servers use `root` / `mariadb`; MaxScale (REST + SQL) uses `admin` / `mariadb`.

| Topology | Node | Address | Credentials |
|---|---|---|---|
| Standalone | server | `127.0.0.1:3306` | `root` / `mariadb` |
| Primary/Replica | primary | `127.0.0.1:3307` | `root` / `mariadb` |
| | replica | `127.0.0.1:3308` | `root` / `mariadb` |
| Galera Cluster | galera-1 | `127.0.0.1:3309` | `root` / `mariadb` |
| | galera-2 | `127.0.0.1:3310` | `root` / `mariadb` |
| | galera-3 | `127.0.0.1:3311` | `root` / `mariadb` |
| Primary/Replica + MaxScale | maxscale REST API | `127.0.0.1:8989` | `admin` / `mariadb` |
| | maxscale SQL listener | `127.0.0.1:4006` | `admin` / `mariadb` |
| | mxs-server-1 | `127.0.0.1:3312` | `root` / `mariadb` |
| | mxs-server-2 | `127.0.0.1:3313` | `root` / `mariadb` |
| | mxs-server-3 | `192.0.2.3:3314` | always Down (intentional) |
| | maxscale-2 REST API | `127.0.0.1:8999` | `admin` / `mariadb` |
| | maxscale-2 SQL listener | `127.0.0.1:4007` | `admin` / `mariadb` |

`maxscale-2` fronts the same backends for cooperative monitoring; `mxs-server-3` is an unroutable TEST-NET-3 address that always reports Down to exercise EM's handling — see [ARCHITECTURE.md](ARCHITECTURE.md#second-maxscale-cooperative-monitoring).

## Keycloak (OIDC SSO)

A Keycloak instance runs on port 8080 with the `enterprise-manager` realm preimported.

- **Admin console:** http://localhost:8080 — `admin` / `admin`
- **Realm / Client ID:** `enterprise-manager`
- **Test user:** `keycloak-user` / `mariadb`

To configure OIDC in EM, navigate to `https://<MEMA_HOSTNAME>/#/settings/identity-provider/oidc` and enter:

- **Authentication URL:** `http://127.0.0.1:8080/realms/enterprise-manager`
- **Client ID:** `enterprise-manager`
- **Authentication Flow:** `auto`
- **Client Secret:** `mariadb`

After saving, log out and press F5 to reveal the **Sign In With SSO** button, then sign in with `keycloak-user` / `mariadb`.
