# Development Scripts

Scripts for starting and managing your local development environment.

## Quick Start

```bash
# Most common: Start dev with Docker
./scripts/development/ehs-dev.sh

# Or without Docker
./scripts/development/ehs-dev-no-docker.sh
```

## Available Scripts

### 🌟 sert-enf-start (Recommended)

**Start complete development environment (Backend + Frontend + Docker)**

```bash
# Start servers only (assumes Docker already running)
./scripts/development/sert-enf-start

# Start everything including Docker
./scripts/development/sert-enf-start --docker
```

**What it does:**
- Checks if Docker services are running (optional)
- Starts Docker containers if `--docker` flag used
- Opens Phoenix backend in new terminal (port 4002)
- Opens SvelteKit frontend in new terminal (port 5173)
- Opens console terminal with quick commands

**When to use:**
- **Recommended for daily development**
- Working on both backend and frontend
- Need separate terminals for each service
- Want quick access to logs

**URLs after start:**
- Backend: http://localhost:4002
- Frontend: http://localhost:5173
- Electric: http://localhost:3001

---

### 🔄 sert-enf-restart (New!)

**Forcefully restart development servers**

```bash
# Restart servers only
./scripts/development/sert-enf-restart

# Restart servers + Docker
./scripts/development/sert-enf-restart --docker

# Force immediate kill (skip graceful shutdown)
./scripts/development/sert-enf-restart --force
```

**What it does:**
- Stops all Phoenix and SvelteKit processes
- Waits for ports 4002 and 5173 to be freed (up to 10s)
- Force kills if graceful shutdown times out
- Optionally restarts Docker containers
- Starts fresh servers in new terminals

**When to use:**
- **Phoenix won't stop or restart properly**
- Port conflicts or "already running" errors
- After significant code changes
- Need clean slate without manual process killing

**Key Features:**
- ✅ Handles stubborn BEAM VM processes
- ✅ Waits for ports to be freed
- ✅ Force kill option (`--force`) for immediate restart
- ✅ Comprehensive process cleanup

---

### 🛑 sert-enf-stop

**Stop development servers**

```bash
# Stop servers only
./scripts/development/sert-enf-stop

# Stop servers + Docker
./scripts/development/sert-enf-stop --docker
```

**What it does:**
- Stops Phoenix backend processes
- Stops SvelteKit frontend processes
- Optionally stops Docker containers

**When to use:**
- End of development session
- Before switching branches
- Freeing up system resources

---

### ehs-dev.sh

**Start complete development environment with Docker PostgreSQL**

```bash
./scripts/development/ehs-dev.sh
```

**What it does:**
- Stops any existing PostgreSQL containers
- Starts PostgreSQL 14 in Docker on port 5434
- Creates database if needed
- Runs migrations
- Starts Phoenix server on port 4002

**When to use:**
- Daily development startup
- Fresh environment setup
- You don't have PostgreSQL installed locally

---

### ehs-dev-no-docker.sh

**Start development environment without Docker**

```bash
./scripts/development/ehs-dev-no-docker.sh
```

**What it does:**
- Creates database using local PostgreSQL
- Runs migrations
- Starts Phoenix server

**When to use:**
- Docker not available
- Using local PostgreSQL installation
- Prefer native database

**Prerequisites:**
- PostgreSQL installed locally
- Database configured in `config/dev.exs`

---

### start-dev.sh

**Quick start Phoenix server (assumes database running)**

```bash
./scripts/development/start-dev.sh
```

**What it does:**
- Starts Phoenix server only
- No database setup or checks

**When to use:**
- Database already running
- Quick restart after code changes
- Environment already set up

---

### docker-manual.sh

**Manual Docker PostgreSQL management**

```bash
./scripts/development/docker-manual.sh
```

**What it does:**
- Creates PostgreSQL container manually (no docker-compose)
- Provides manual container control

**When to use:**
- docker-compose not available
- Need manual container management
- Troubleshooting container issues

---

### setup_database.sh

**Database setup and connectivity helper**

```bash
./scripts/development/setup_database.sh
```

**What it does:**
- Checks PostgreSQL connectivity
- Creates database if missing
- Tests connection

**When to use:**
- Initial database setup
- Database connection issues
- Verifying database access

---

## Common Workflows

### First Time Setup

```bash
# 1. Start development environment (recommended)
./scripts/development/sert-enf-start --docker

# 2. Import sample data (optional)
./scripts/data/airtable_import.sh dev --cases --limit 100
```

### Daily Development

```bash
# Recommended: Start both backend + frontend
./scripts/development/sert-enf-start

# Or start with Docker containers
./scripts/development/sert-enf-start --docker

# Legacy: Backend only
./scripts/development/ehs-dev.sh
```

### Restart After Code Changes

```bash
# Quick restart (most common)
./scripts/development/sert-enf-restart

# Restart with Docker
./scripts/development/sert-enf-restart --docker

# Force restart (if servers won't stop)
./scripts/development/sert-enf-restart --force
```

### Troubleshooting

```bash
# Phoenix won't stop or restart?
./scripts/development/sert-enf-restart --force

# Port conflicts or "already running" errors?
./scripts/development/sert-enf-restart

# Database won't connect?
./scripts/development/setup_database.sh

# Need manual control?
./scripts/development/docker-manual.sh

# Check what's using a port:
lsof -i :4002  # Find process on port 4002
lsof -i :5173  # Find process on port 5173

# Manual force kill if needed:
pkill -9 -f "mix phx.server"
pkill -9 -f "vite dev.*5173"
```

---

## Configuration

All scripts respect environment variables and `config/dev.exs` settings:

- **Database Port**: Default 5434 (Docker), 5432 (local)
- **Phoenix Port**: 4002
- **Database Name**: sertantai_enforcement_dev
- **Database User**: postgres
- **Database Password**: postgres

To customize, edit `config/dev.exs` or set environment variables.

---

## Related Documentation

- **[docs-dev/GETTING_STARTED.md](../../docs-dev/GETTING_STARTED.md)** - Initial setup guide
- **[docs-dev/DEVELOPMENT_WORKFLOW.md](../../docs-dev/DEVELOPMENT_WORKFLOW.md)** - Day-to-day workflow
- **[docs-dev/TROUBLESHOOTING.md](../../docs-dev/TROUBLESHOOTING.md)** - Common issues

---

**Parent README**: [scripts/README.md](../README.md)
