# Provision DB Topologies for Enterprise Manager

Docker-based MariaDB topologies for testing Enterprise Manager. The `mema-agent` is preinstalled and registered on two servers: `standalone` and `primary`. The replica is auto-discovered by EM via `SHOW SLAVE HOSTS` on the primary; Galera nodes run without the agent and are added to EM manually.

## Adding to Existing enterprise-manager Directory

1. **Copy the provisioning files:**
   ```bash
   cp -r provision/ <path-to-enterprise-manager>/
   cp docker-compose.override.yml <path-to-enterprise-manager>/
   ```

2. **Add the required variables to `.env`:**

   Get your enterprise token from https://customers.mariadb.com/downloads/token/

   ```bash
   cat >> <path-to-enterprise-manager>/.env <<'EOF'
   ENTERPRISE_TOKEN=your_token_here
   MEMA_HOSTNAME=https://your-em-host:8090
   EOF
   ```

3. **Start the containers:**
   ```bash
   cd <path-to-enterprise-manager>
   docker compose up -d --wait
   ```

## Available Topologies

- **Standalone** — Single MariaDB server on port 3306 (mema-agent registered)
- **Primary/Replica** — Primary on port 3307 (mema-agent registered), replica on port 3308 (auto-discovered via `SHOW SLAVE HOSTS`)
- **Galera Cluster** — Three-node cluster on ports 3309-3311 (no agent; add manually in EM)
- **Primary/Replica with MaxScale** — MaxScale REST API on port 8989 (mema-agent registered) with SQL listener on port 4006; backends `mxs-server-1` (3312) and `mxs-server-2` (3313) auto-discovered by EM via MaxScale. A third backend `mxs-server-3` is configured at the RFC 5737 TEST-NET-3 address `192.0.2.3:3314` with no matching service — `mariadbmon` always reports it as Down, exercising EM's handling of an unreachable backend.

## Configuration

`ENTERPRISE_TOKEN` is consumed at build time and scrubbed from the final image. The agent endpoint is derived from `MEMA_HOSTNAME` in `.env` (the existing Enterprise Manager URL with the trailing `:port` stripped).