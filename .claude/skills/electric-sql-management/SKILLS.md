---
name: ElectricSQL Safe Management
description: Safe procedures for restarting, troubleshooting, and managing ElectricSQL sync service without wiping the PostgreSQL database. Includes critical warnings about Docker Compose dependency chains and proper restart commands.
---

# ElectricSQL Safe Management

## Overview

ElectricSQL provides real-time PostgreSQL sync via HTTP Shape API. This guide covers safe restart procedures and troubleshooting to **prevent accidental database wipes**.

## Development vs Production Environments

The project uses different Docker Compose files for dev and production:

**Development** (`docker-compose.dev.yml`):
```bash
# Container names: ehs_dev_postgres, ehs_dev_electric, ehs_dev_redis
docker-compose -f docker-compose.dev.yml up -d postgres electric
```

**Production** (`docker-compose.yml`):
```bash
# Container names: ehs_enforcement_postgres, ehs_enforcement_electric
docker-compose up -d
```

**Key Difference**: Dev uses `ehs_dev_*` naming, production uses `ehs_enforcement_*`. Adjust commands accordingly.

## Critical Warning: Never Use docker-compose to Restart Electric

⚠️ **DANGER**: Using `docker-compose up -d electric` will recreate both Electric AND PostgreSQL containers due to dependency chain, **wiping all database data**.

### Wrong (Data Loss):
```bash
# ❌ NEVER DO THIS - Wipes database!
docker-compose up -d electric
```

### Correct (Safe):
```bash
# ✅ Safe restart - preserves database
docker restart ehs_enforcement_electric
```

## Safe Restart Procedures

### 1. Restart Electric Only (Most Common)

When Electric is unhealthy, not responding, or has stale shape cache:

```bash
# Stop Electric container
docker stop ehs_enforcement_electric

# Remove container (preserves Postgres)
docker rm ehs_enforcement_electric

# Recreate Electric container ONLY
docker-compose up -d electric --no-deps

# Verify it's running
docker ps | grep electric
```

The `--no-deps` flag prevents recreating dependent services (Postgres).

### 2. Quick Restart (No Cache Clear)

For simple restarts without removing cached shapes:

```bash
docker restart ehs_enforcement_electric
```

### 3. Full Reset with Cache Clear

When shape cache is corrupted or needs clearing:

```bash
# Stop and remove Electric container
docker stop ehs_enforcement_electric
docker rm ehs_enforcement_electric

# Remove Electric volume (clears shape cache)
docker volume rm sertantai-enforcement_electric_data 2>/dev/null || true

# Recreate Electric without touching Postgres
docker-compose up -d electric --no-deps
```

## Verification Steps

### Check Electric is Running

```bash
# Container status
docker ps | grep electric

# Should show:
# ehs_enforcement_electric   electricsql/electric:latest   Up X minutes (healthy)   3001->3000/tcp
```

### Test Shape API Endpoint

```bash
# Test cases table shape
curl http://localhost:3001/v1/shape?table=cases&offset=-1

# Should return JSON with shape data
# Bad response: "Not found" or connection refused means Electric isn't working
```

### Check Logs

```bash
# View Electric logs
docker logs ehs_enforcement_electric --tail=50

# Look for:
# ✅ "Electric is running on http://0.0.0.0:3000"
# ❌ "Database connection failed" or panic errors
```

## Exposing Tables to Electric

Electric only syncs tables explicitly added to the Postgres publication.

### Check Current Publication

```bash
PGPASSWORD=postgres psql -h localhost -p 5434 -U postgres -d sertantai_enforcement_dev -c \
  "SELECT * FROM pg_publication_tables WHERE pubname = 'electric_publication_default';"
```

### Add Tables to Publication

When adding new tables, recreate the publication:

```bash
# Drop and recreate publication with all tables
PGPASSWORD=postgres psql -h localhost -p 5434 -U postgres -d sertantai_enforcement_dev -c \
  "DROP PUBLICATION IF EXISTS electric_publication_default;
   CREATE PUBLICATION electric_publication_default FOR TABLE legislation, offenders, cases, notices, agencies;"

# Restart Electric to pick up changes
docker restart ehs_dev_electric  # or ehs_enforcement_electric for production
```

### Verify Table is Exposed

```bash
# Test API endpoint (should return data or empty snapshot, not "Not found")
curl "http://localhost:3001/v1/shape?table=TABLE_NAME&offset=-1"
```

## Common Issues and Fixes

### Issue: "Table does not exist" Error

**Cause**: Database schema is missing (migrations not run).

**Fix**:
```bash
# Run migrations
cd /home/jason/Desktop/sertantai-enforcement
MIX_ENV=dev mix ecto.migrate
```

### Issue: "Not found" on Shape Endpoint

**Cause 1**: Table not exposed in Postgres publication.

**Cause 2**: Incorrect port mapping in docker-compose.yml or wrong API format.

**Check**: Electric runs on port 3000 inside container, mapped to 3001 on host.

**Correct Configuration**:
```yaml
electric:
  ports:
    - "3001:3000"  # ✅ Correct: host:container
```

**Wrong Configuration**:
```yaml
electric:
  ports:
    - "3001:3001"  # ❌ Wrong - Electric runs on 3000
```

**Fix for Cause 1 (Missing publication)**:
See [Exposing Tables to Electric](#exposing-tables-to-electric) section above.

**Fix for Cause 2 (Port mapping)**:
```bash
# Edit docker-compose.yml to fix port mapping
# Then restart Electric safely:
docker restart ehs_enforcement_electric
```

**Correct API Format**:
```bash
# ✅ Correct - uses query parameters
curl "http://localhost:3001/v1/shape?table=cases&offset=-1"

# ❌ Wrong - missing query parameters
curl "http://localhost:3001/v1/shape/cases"
```

### Issue: Electric Container Unhealthy

**Symptoms**: `docker ps` shows "(unhealthy)" status.

**Diagnosis**:
```bash
# Check health check logs
docker inspect ehs_enforcement_electric | grep -A 10 Health

# Check Electric logs
docker logs ehs_enforcement_electric --tail=100
```

**Fix**:
```bash
# Restart Electric
docker restart ehs_enforcement_electric

# If still unhealthy, check database connection:
docker exec -it ehs_enforcement_postgres psql -U postgres -d sertantai_enforcement_dev -c "SELECT 1;"
```

### Issue: Browser Shows "Offline" or "No Data"

**Cause**: ElectricSQL sync not working or shape cache stale.

**Fix**:
```bash
# 1. Verify Electric is accessible
curl http://localhost:3001/v1/shape?table=cases&offset=-1

# 2. If working, refresh browser (Ctrl+Shift+R)

# 3. If still offline, restart Electric with cache clear:
docker stop ehs_enforcement_electric
docker rm ehs_enforcement_electric
docker-compose up -d electric --no-deps
```

## Complete Stack Restart (Safe)

When you need to restart everything (e.g., config changes):

```bash
# Use the project's safe start script
./scripts/development/sert-enf-start

# Or manual restart (safe):
docker-compose down        # Stops all, preserves volumes
docker-compose up -d       # Recreates all containers safely
```

**Why Safe**: `docker-compose down` + `docker-compose up -d` preserves named volumes (database data persists).

**Unsafe**: `docker-compose down -v` (removes volumes, wipes data).

## Port Configuration Reference

### Current Setup:
- **PostgreSQL**: Host 5434 → Container 5432
- **ElectricSQL**: Host 3001 → Container 3000
- **Phoenix**: Host 4002 → Container 4002 (no Docker)
- **Frontend**: Host 5173 → Container 5173 (no Docker)

### Environment Variables:
```yaml
electric:
  environment:
    DATABASE_URL: postgresql://postgres:postgres@postgres:5432/sertantai_enforcement_dev
    ELECTRIC_INSECURE: "true"  # Dev only!
    PG_PROXY_PASSWORD: proxy_password
```

## Database Recovery (If Accidentally Wiped)

If database was wiped, recover with these steps:

```bash
# 1. Run all migrations
cd /home/jason/Desktop/sertantai-enforcement
MIX_ENV=dev mix ecto.migrate

# 2. Import production data (if available)
./scripts/copy-prod-data.sh

# Or SSH to production and dump data:
ssh sertantai-hz "docker exec infrastructure-postgres-1 pg_dump -U postgres -d ehs_enforcement_prod -t cases -t offenders -t agencies --data-only --column-inserts" > /tmp/prod_data.sql

# Import to dev:
PGPASSWORD=postgres psql -h localhost -p 5434 -U postgres -d sertantai_enforcement_dev < /tmp/prod_data.sql
```

## Quick Reference Card

| Task | Safe Command |
|------|--------------|
| Restart Electric (dev) | `docker restart ehs_dev_electric` |
| Restart Electric (prod) | `docker restart ehs_enforcement_electric` |
| Electric + cache clear | `docker stop CONTAINER && docker rm CONTAINER && docker-compose up -d electric --no-deps` |
| Check Electric status | `docker ps \| grep electric` |
| Test shape API | `curl "http://localhost:3001/v1/shape?table=TABLE&offset=-1"` |
| View logs | `docker logs CONTAINER --tail=50` |
| Check publication | `psql -c "SELECT * FROM pg_publication_tables WHERE pubname = 'electric_publication_default';"` |
| Add table to Electric | Recreate publication + `docker restart ELECTRIC_CONTAINER` |
| Full stack restart | `docker-compose down && docker-compose up -d` |
| **NEVER DO** | `docker-compose up -d electric` (wipes database!) |

Replace `CONTAINER` with `ehs_dev_electric` (dev) or `ehs_enforcement_electric` (prod).

## Related Documentation

- ElectricSQL HTTP API: https://electric-sql.com/docs/api/http
- Docker Compose docs: https://docs.docker.com/compose/
- Project docker-compose.yml: `/home/jason/Desktop/sertantai-enforcement/docker-compose.yml`
- Development scripts: `/home/jason/Desktop/sertantai-enforcement/scripts/development/`
