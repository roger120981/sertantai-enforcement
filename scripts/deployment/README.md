# Sertantai Enforcement Deployment Scripts

Automated deployment scripts for building, testing, and deploying the Sertantai Enforcement application.

## Architecture Overview

This application uses a modern full-stack architecture:

| Component | Technology | Port | Deployment |
|-----------|------------|------|------------|
| **Frontend** | Svelte 5 + TanStack | - | Static files via nginx |
| **Backend** | Phoenix API | 4003 | Docker container |
| **Real-time** | ElectricSQL | 3000 | Docker container |
| **Auth** | sertantai-auth (JWT SSO) | 4001 | Separate service |
| **Database** | PostgreSQL 16 | 5432 | Shared infrastructure |

**Production URL:** https://enforcement.sertantai.com

## Quick Start

```bash
# Complete full-stack deployment
./scripts/deployment/build.sh
./scripts/deployment/push.sh
./scripts/deployment/deploy-prod.sh --all --migrate --logs
```

## Available Scripts

| Script | Purpose | Time |
|--------|---------|------|
| **build.sh** | Build frontend + backend | 5-10 min |
| **build-frontend.sh** | Build Svelte frontend only | 1-2 min |
| **push.sh** | Push backend image to GHCR | 1-2 min |
| **deploy-prod.sh** | Deploy to production | 30-60 sec |
| **deploy-frontend.sh** | Deploy frontend via rsync | 10-30 sec |
| **test-container.sh** | Test builds locally | 2-5 min |

## Script Details

### build.sh

Build production artifacts (frontend and/or backend).

```bash
./scripts/deployment/build.sh [options] [tag]

# Options:
#   --backend-only   Build only Docker image (Phoenix)
#   --frontend-only  Build only Svelte frontend
#   --no-cache       Build Docker image without cache
#   --check          Run type checks before building

# Examples:
./scripts/deployment/build.sh                    # Build full stack
./scripts/deployment/build.sh --backend-only     # Backend only
./scripts/deployment/build.sh --frontend-only    # Frontend only
./scripts/deployment/build.sh --check v1.2.3     # Full stack with checks + version tag
```

**What it does:**
- Builds Svelte frontend to `frontend/build/` (static files)
- Builds Phoenix backend Docker image
- Tags image for GitHub Container Registry

---

### build-frontend.sh

Build only the Svelte frontend for production.

```bash
./scripts/deployment/build-frontend.sh [options]

# Options:
#   --clean   Remove node_modules and reinstall
#   --check   Run type checking and linting

# Examples:
./scripts/deployment/build-frontend.sh           # Standard build
./scripts/deployment/build-frontend.sh --clean   # Clean install first
./scripts/deployment/build-frontend.sh --check   # Build with checks
```

**Output:** `frontend/build/` (static files for nginx)

**Requires:** `frontend/.env.production` with:
```bash
PUBLIC_API_URL=https://enforcement.sertantai.com
PUBLIC_ELECTRIC_URL=https://enforcement.sertantai.com/electric
PUBLIC_ENV=production
```

---

### push.sh

Push the backend Docker image to GitHub Container Registry.

```bash
./scripts/deployment/push.sh [tag]

# Examples:
./scripts/deployment/push.sh           # Push 'latest' tag
./scripts/deployment/push.sh v1.2.3    # Push version tag
```

**Prerequisites:**
```bash
# One-time GHCR login
echo $GITHUB_PAT | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

---

### deploy-prod.sh

Deploy to production server.

```bash
./scripts/deployment/deploy-prod.sh [options]

# Options:
#   --all              Deploy both frontend and backend (default)
#   --frontend         Deploy frontend only
#   --backend          Deploy backend only
#   --electric         Restart ElectricSQL only (safe restart)
#   --with-electric    Also restart ElectricSQL when deploying backend
#   --electric-clear-cache  Restart Electric and clear shape cache
#   --migrate          Run database migrations
#   --check-only       Check status without deploying
#   --logs             Follow logs after deployment
#   --help             Show help message

# Examples:
./scripts/deployment/deploy-prod.sh                         # Deploy full stack
./scripts/deployment/deploy-prod.sh --frontend              # Frontend only
./scripts/deployment/deploy-prod.sh --backend --migrate     # Backend with migrations
./scripts/deployment/deploy-prod.sh --all --migrate --logs  # Full deploy + watch
./scripts/deployment/deploy-prod.sh --check-only            # Check status only
./scripts/deployment/deploy-prod.sh --electric              # Restart Electric only
./scripts/deployment/deploy-prod.sh --backend --with-electric --migrate  # Backend + Electric
./scripts/deployment/deploy-prod.sh --electric-clear-cache  # Electric with cache clear
```

**What it does:**
1. **Frontend**: Calls `deploy-frontend.sh` to rsync static files to nginx
2. **Backend**: Pulls Docker image, optionally migrates, restarts container
3. **Electric**: Safe restart using `docker restart` (never `docker compose up`!)
4. Validates health endpoints
5. Shows deployment status

**ElectricSQL Safety:**
- Uses `docker restart` for safe restarts (preserves database)
- Uses `--no-deps` when recreating container (prevents PostgreSQL recreation)
- NEVER uses `docker compose up electric` directly (can wipe database!)
- Use `--electric-clear-cache` after schema changes or when shapes are stale

---

### deploy-frontend.sh

Deploy frontend static files to production via rsync.

```bash
./scripts/deployment/deploy-frontend.sh [options]

# Options:
#   --build        Build frontend before deploying
#   --dry-run      Show what would be transferred
#   --check-only   Check server status only

# Examples:
./scripts/deployment/deploy-frontend.sh              # Deploy existing build
./scripts/deployment/deploy-frontend.sh --build      # Build then deploy
./scripts/deployment/deploy-frontend.sh --dry-run    # Preview changes
```

**Server:** `sertantai-hz`
**Deploy path:** `/var/www/enforcement-frontend`

---

### test-container.sh

Test production builds locally before deployment.

```bash
./scripts/deployment/test-container.sh [options]

# Options:
#   --backend-only   Test only Docker image
#   --frontend-only  Test only frontend build
#   --skip-electric  Skip ElectricSQL in tests
#   --clean          Clean up test containers

# Examples:
./scripts/deployment/test-container.sh                 # Test full stack
./scripts/deployment/test-container.sh --backend-only  # Backend only
./scripts/deployment/test-container.sh --clean         # Clean up
```

**Note:** For development, use `./scripts/development/sert-enf-start` instead.

---

## Typical Workflows

### Full Stack Deployment

```bash
# 1. Build everything
./scripts/deployment/build.sh

# 2. Push backend image
./scripts/deployment/push.sh

# 3. Deploy full stack
./scripts/deployment/deploy-prod.sh --all --migrate --logs
```

### Frontend-Only Deployment

When only frontend changes were made:

```bash
# Option A: Build and deploy in one command
./scripts/deployment/deploy-frontend.sh --build

# Option B: Separate steps
./scripts/deployment/build-frontend.sh
./scripts/deployment/deploy-frontend.sh
```

### Backend-Only Deployment

When only backend changes were made:

```bash
./scripts/deployment/build.sh --backend-only
./scripts/deployment/push.sh
./scripts/deployment/deploy-prod.sh --backend --migrate
```

### Pre-deployment Testing

```bash
# 1. Build
./scripts/deployment/build.sh

# 2. Test locally
./scripts/deployment/test-container.sh

# 3. Clean up
./scripts/deployment/test-container.sh --clean

# 4. Deploy
./scripts/deployment/push.sh
./scripts/deployment/deploy-prod.sh --all --migrate
```

### Version Release

```bash
# Build with version tag
./scripts/deployment/build.sh --check v1.2.3

# Test
./scripts/deployment/test-container.sh

# Push versioned image
./scripts/deployment/push.sh v1.2.3

# Deploy (update SERTANTAI_ENFORCEMENT_VERSION in .env first)
./scripts/deployment/deploy-prod.sh --all --migrate --logs
```

---

## Environment Variables

### Frontend (`frontend/.env.production`)

```bash
PUBLIC_API_URL=https://enforcement.sertantai.com
PUBLIC_ELECTRIC_URL=https://enforcement.sertantai.com/electric
PUBLIC_ENV=production
PUBLIC_ENABLE_DEBUG=false
```

### Backend (infrastructure `.env`)

```bash
SERTANTAI_ENFORCEMENT_VERSION=latest
SERTANTAI_ENFORCEMENT_PORT=4003
SERTANTAI_ENFORCEMENT_PHX_HOST=enforcement.sertantai.com
SERTANTAI_ENFORCEMENT_SECRET_KEY_BASE=<generate with mix phx.gen.secret>
SERTANTAI_ENFORCEMENT_POOL_SIZE=10
SHARED_TOKEN_SECRET=<must match sertantai-auth>
```

---

## Prerequisites

### For Building
- Docker installed and running
- Node.js 18+ and npm (for frontend)
- `frontend/.env.production` configured

### For Pushing
- GHCR authentication configured
- Image built locally

### For Deploying
- SSH access to `sertantai-hz` server
- SSH key configured
- Image pushed to GHCR (for backend)

---

## Infrastructure Requirements

The production infrastructure (managed in `~/Desktop/infrastructure`) needs:

1. **PostgreSQL** with logical replication enabled (`wal_level=logical`)
2. **ElectricSQL** container for real-time sync
3. **nginx** configured to:
   - Serve frontend static files at root
   - Proxy `/api/` to Phoenix backend
   - Proxy `/electric/` to ElectricSQL
4. **sertantai-auth** for JWT SSO

See `~/Desktop/infrastructure/.claude/sessions/2025-12-15-sertantai-enforcement-deployment.md` for full infrastructure setup instructions.

---

## Troubleshooting

### Build fails
```bash
# Check Docker is running
docker info

# Check Node.js version (need 18+)
node --version

# Check frontend .env exists
cat frontend/.env.production
```

### Push fails
```bash
# Login to GHCR
echo $GITHUB_PAT | docker login ghcr.io -u YOUR_USERNAME --password-stdin

# Verify image exists
docker images | grep sertantai-enforcement
```

### Frontend deploy fails
```bash
# Test SSH connection
ssh sertantai-hz

# Check build exists
ls -la frontend/build/

# Try dry run
./scripts/deployment/deploy-frontend.sh --dry-run
```

### Backend deploy fails
```bash
# Check status
./scripts/deployment/deploy-prod.sh --check-only

# SSH and check logs
ssh sertantai-hz
cd ~/infrastructure/docker
docker compose logs sertantai-enforcement
```

### ElectricSQL not syncing
```bash
# Check Electric health
curl https://enforcement.sertantai.com/electric/v1/health

# Check PostgreSQL replication
ssh sertantai-hz
docker exec shared_postgres psql -U postgres -c "SHOW wal_level;"
# Should return: logical
```

---

## Production Details

| Item | Value |
|------|-------|
| **Server** | sertantai-hz (Hetzner) |
| **URL** | https://enforcement.sertantai.com |
| **Infrastructure Path** | `~/infrastructure/docker` |
| **Frontend Path** | `/var/www/enforcement-frontend` |
| **Backend Container** | `sertantai_enforcement_app` |
| **Electric Container** | `sertantai_enforcement_electric` |
| **Database** | `sertantai_enforcement_prod` |
| **Backend Port** | 4003 |

---

## Related Documentation

- [Infrastructure Setup](~/Desktop/infrastructure/.claude/sessions/2025-12-15-sertantai-enforcement-deployment.md)
- [Development Scripts](../development/README.md)
- [Getting Started](../../docs-dev/GETTING_STARTED.md)

---

**Last Updated:** 2025-12-15
**Scripts Version:** 2.0 (Full-stack architecture)
