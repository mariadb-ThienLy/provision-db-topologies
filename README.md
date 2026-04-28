# Provision DB Topologies for Enterprise Manager

This directory provides Docker-based MariaDB topologies with the mema-agent pre-installed.

## Adding to Existing enterprise-manager Directory

1. **Copy the provisioning files:**
   ```bash
   cp -r provision/ <path-to-enterprise-manager>/
   cp docker-compose.override.yml <path-to-enterprise-manager>/
   ```

2. **Add the enterprise token to `.env`:**

   Get your token from https://customers.mariadb.com/downloads/token/

   ```bash
   echo "ENTERPRISE_TOKEN=your_token_here" >> <path-to-enterprise-manager>/.env
   ```

3. **Start the containers:**
   ```bash
   cd <path-to-enterprise-manager>
   docker compose up -d --wait
   ```

## Available Topologies

- **Standalone** — Single MariaDB server on port 3306
- **Primary/Replica** — Primary on port 3307, replica on port 3308
- **Galera Cluster** — Three-node cluster on ports 3309-3311

## Configuration

The `ENTERPRISE_TOKEN` argument is consumed at build time and scrubbed from the final image. The agent endpoint is derived from `MEMA_HOSTNAME` in `.env` (the existing Enterprise Manager URL with the `:port` suffix stripped).