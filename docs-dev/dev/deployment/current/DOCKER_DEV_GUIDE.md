# Docker Development Environment - Quick Start Guide

This guide explains how to use the local container testing environment for EHS Enforcement.

## Prerequisites

- Docker and Docker Compose installed
- Elixir 1.18.2+ / OTP 27+ (for Mode 1 only)
- `.env.dev` file configured (see `.env.dev.example`)

## Three Development Modes

### Mode 1: Fast Development (Recommended for Daily Work)

**Phoenix runs on host, services in Docker**

Best for: Daily development with hot reload

```bash
# 1. Start backing services
docker compose -f docker-compose.dev.yml up -d postgres redis

# 2. Load environment variables
cp .env.dev.example .env.dev
# Edit .env.dev with your values
export $(grep -v '^#' .env.dev | xargs)

# 3. Setup database
mix ecto.create
mix ecto.migrate

# 4. Start Phoenix
mix phx.server

# Access: http://localhost:4002
```

### Mode 2: Container Testing (Before Deployment)

**Everything runs in Docker (matches production)**

Best for: Testing Docker builds before pushing to production

```bash
# Test production container build
docker compose -f docker-compose.dev.yml up --build app

# Or run in background
docker compose -f docker-compose.dev.yml up -d --build app

# Watch logs
docker compose -f docker-compose.dev.yml logs -f app

# Access: http://localhost:4002
```

### Mode 3: Integration Testing (With Baserow)

**Full stack including Baserow for data sync testing**

Best for: Testing database integrations and data workflows

```bash
# Start all services including Baserow
docker compose -f docker-compose.dev.yml --profile integration up -d

# Access:
#   Phoenix: http://localhost:4002
#   Baserow: http://localhost:8080
```

## Common Commands

### Status and Logs

```bash
# Check running services
docker compose -f docker-compose.dev.yml ps

# View logs (all services)
docker compose -f docker-compose.dev.yml logs -f

# View logs (specific service)
docker compose -f docker-compose.dev.yml logs -f app
docker compose -f docker-compose.dev.yml logs -f postgres
```

### Database Operations

```bash
# Connect to PostgreSQL
docker compose -f docker-compose.dev.yml exec postgres psql -U postgres -d sertantai_enforcement_dev

# Or from host
psql postgresql://postgres:postgres@localhost:5434/sertantai_enforcement_dev

# Run migrations (in container)
docker compose -f docker-compose.dev.yml exec app /app/bin/ehs_enforcement eval "EhsEnforcement.Release.migrate"
```

### Cleanup

```bash
# Stop services (keep volumes)
docker compose -f docker-compose.dev.yml down

# Stop and remove volumes (clean slate)
docker compose -f docker-compose.dev.yml down -v

# Remove just app container (keep data)
docker compose -f docker-compose.dev.yml rm -f app
```

## Service Ports

| Service    | Port | Access                           |
|------------|------|----------------------------------|
| Phoenix    | 4002 | http://localhost:4002            |
| PostgreSQL | 5434 | localhost:5434                   |
| Redis      | 6379 | localhost:6379                   |
| Baserow    | 8080 | http://localhost:8080 (Mode 3)   |

## Key Differences: Development vs Production

Understanding these differences helps ensure smooth deployments:

| Aspect | Development | Production |
|--------|-------------|------------|
| **Port** | 4002 (host accessible) | 4002 (internal, proxied) |
| **Database** | `sertantai_enforcement_dev` | `ehs_enforcement_prod` |
| **Database Host** | `localhost:5434` (Mode 1) or `postgres` (Mode 2) | `postgres` (Docker network) |
| **Domain** | `localhost:4002` | `legal.sertantai.com` |
| **SSL** | HTTP only | HTTPS via Let's Encrypt |
| **Image Source** | Build locally | Pull from GHCR |
| **Network** | `dev_network` | `infra_network` |
| **Hot Reload** | Yes (Mode 1) | No |
| **Secrets** | `.env.dev` | Infrastructure `.env` |
| **OAuth Redirect** | `http://localhost:4002/auth/...` | `https://legal.sertantai.com/auth/...` |

## Environment Variables

Create `.env.dev` from the template:

```bash
cp .env.dev.example .env.dev
```

Edit `.env.dev` with your values. Key variables:

- `DATABASE_URL` - Database connection (use localhost:5434 for Mode 1)
- `SECRET_KEY_BASE` - Generate with `mix phx.gen.secret`
- `GITHUB_CLIENT_ID` - GitHub OAuth (create dev app)
- `GITHUB_CLIENT_SECRET` - GitHub OAuth secret
- `AT_UK_E_API_KEY` - Airtable API key

**Never commit `.env.dev` to git!** (It's already in .gitignore)

## Troubleshooting

### Port Already in Use

```bash
# Check what's using port 4002
lsof -i :4002

# Or use different port in docker-compose.dev.yml
```

### Database Connection Issues

```bash
# Ensure postgres is running
docker compose -f docker-compose.dev.yml ps postgres

# Check logs
docker compose -f docker-compose.dev.yml logs postgres

# Restart postgres
docker compose -f docker-compose.dev.yml restart postgres
```

### Container Build Fails

```bash
# View build logs
docker compose -f docker-compose.dev.yml build --no-cache app

# Or use the build script
./scripts/deployment/build.sh
```

### GitHub OAuth Not Working

1. Create separate dev OAuth app at https://github.com/settings/applications/new
2. Set **Authorization callback URL** to `http://localhost:4002/auth/user/github/callback`
3. Copy Client ID and Secret to `.env.dev`
4. Restart Phoenix server

### Hot Reload Not Working (Mode 1)

1. Check `config/dev.exs` has `code_reloader: true`
2. Verify file watchers are configured
3. Check Phoenix LiveReload is enabled
4. Restart Phoenix server

### Clean Slate

```bash
# Nuclear option - remove everything and start fresh
docker compose -f docker-compose.dev.yml down -v
docker system prune -a
docker compose -f docker-compose.dev.yml up -d postgres redis
```

## Integration with Deployment Workflow

The container testing mode mirrors production exactly, allowing you to test before deployment:

```bash
# Full pre-deployment test workflow
./scripts/deployment/build.sh           # Build production image
./scripts/deployment/test-container.sh  # Test locally
./scripts/deployment/push.sh            # Push to GHCR
./scripts/deployment/deploy-prod.sh     # Deploy to production
```

## Related Documentation

- **Deployment docs index**: [README.md](../README.md)
- **Full deployment guide**: [DEPLOYMENT_CURRENT.md](./DEPLOYMENT_CURRENT.md)
- **Future enhancements**: [DEPLOYMENT_FUTURE.md](../plan/DEPLOYMENT_FUTURE.md)
- **Deployment scripts**: `scripts/deployment/README.md`
- **Project README**: [README.md](../../../../README.md)

## Quick Tips

1. **Use Mode 1 for daily development** - Fast hot reload
2. **Use Mode 2 before creating PRs** - Test container builds
3. **Use Mode 3 for integration testing** - Test with Baserow
4. **Always test locally before pushing** - Catch issues early
5. **Clean up volumes occasionally** - `docker compose down -v`

---

**Questions?** Check the main deployment documentation or deployment scripts README.
