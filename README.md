# EHS Enforcement

UK Environmental, Health, and Safety enforcement agency activity data collection and publishing system.

**Production:** https://legal.sertantai.com

## Overview

This Phoenix LiveView application collects and manages enforcement data from UK regulatory agencies (HSE, EA, SEPA, NRW). Built with:

- **Phoenix 1.7+** - Web framework with LiveView
- **Ash Framework 3.0+** - Declarative data modeling and business logic
- **PostgreSQL 16** - Primary database
- **Docker** - Containerized deployment

## Development Setup

### Prerequisites

- **Elixir 1.18.2** / **OTP 27**
- **Docker** and **Docker Compose**
- **PostgreSQL 16** (via Docker)
- **Git** for version control

### Quick Start

1. **Clone and install dependencies:**
   ```bash
   git clone https://github.com/shotleybuilder/ehs_enforcement.git
   cd ehs_enforcement
   mix deps.get
   ```

2. **Create development environment file:**
   ```bash
   cp .env.dev.example .env.dev
   # Edit .env.dev with your values (GitHub OAuth, etc.)
   ```

3. **Start development environment:**
   ```bash
   # Mode 1: Fast development (recommended for daily work)
   docker compose -f docker-compose.dev.yml up -d postgres redis
   export $(grep -v '^#' .env.dev | xargs)
   mix ecto.create
   mix ecto.migrate
   mix phx.server

   # Mode 2: Container testing (test production builds)
   docker compose -f docker-compose.dev.yml up --build app
   ```

4. **Access application:**
   - **Phoenix app:** http://localhost:4002
   - **PostgreSQL:** localhost:5434
   - **Redis:** localhost:6379

### Development Modes

This project supports three development modes:

#### Mode 1: Fast Development (Hot Reload) ⚡
**Phoenix runs on host, services in Docker**

Best for: Daily development with instant code reloading

```bash
docker compose -f docker-compose.dev.yml up -d postgres redis
export $(grep -v '^#' .env.dev | xargs)
mix phx.server
```

#### Mode 2: Container Testing 🐳
**Full stack in Docker (matches production)**

Best for: Testing Docker builds before deployment

```bash
docker compose -f docker-compose.dev.yml up --build app
```

#### Mode 3: Integration Testing 🔗
**Includes Baserow for data sync testing**

Best for: Testing database integrations

```bash
docker compose -f docker-compose.dev.yml --profile integration up -d
# Baserow: http://localhost:8080
```

### Configuration

- **Port:** 4002 (matches production)
- **Database:** sertantai_enforcement_dev
- **Environment:** .env.dev (create from .env.dev.example)
- **API Keys:** Configure GitHub OAuth in .env.dev

See [DOCKER_DEV_GUIDE.md](./docs-dev/dev/deployment/current/DOCKER_DEV_GUIDE.md) for detailed setup instructions.

## Testing

### Run Test Suite

```bash
mix test                    # Run all tests
mix test test/path/file.exs # Run specific test file
mix test --failed           # Run only failed tests
```

### Testing HSE Scrapers

Once database is running, test in iex:

```elixir
# Start IEx
iex -S mix phx.server

# Test HSE Notices
EhsEnforcement.Agencies.Hse.Notices.api_get_hse_notices([pages: "1"])

# Test HSE Cases
EhsEnforcement.Agencies.Hse.Cases.api_get_hse_cases([pages: "1"])
```

## Deployment

### Production Deployment

The application is deployed to a Digital Ocean droplet using Docker Compose.

**Production URL:** https://legal.sertantai.com

### Deployment Workflow

```bash
# 1. Build production Docker image
./scripts/deployment/build.sh

# 2. Test locally (optional but recommended)
./scripts/deployment/test-container.sh

# 3. Push to GitHub Container Registry
./scripts/deployment/push.sh

# 4. Deploy to production
./scripts/deployment/deploy-prod.sh

# With migrations
./scripts/deployment/deploy-prod.sh --migrate --logs
```

### Deployment Scripts

All deployment scripts are in `scripts/deployment/`:

- **`build.sh`** - Build production Docker image
- **`test-container.sh`** - Test container locally before deployment
- **`push.sh`** - Push image to GitHub Container Registry
- **`deploy-prod.sh`** - Deploy to production server

### Pre-Deployment Checklist

- [ ] All tests passing: `mix test`
- [ ] Ash codegen complete: `mix ash.codegen --check`
- [ ] Migrations tested locally: `mix ash.migrate`
- [ ] Container tested: `./scripts/deployment/test-container.sh`
- [ ] Resource snapshots committed: `git status priv/resource_snapshots/`

See [Deployment Documentation](./docs-dev/dev/deployment/current/DEPLOYMENT_CURRENT.md) for detailed deployment procedures.

## Architecture

### Tech Stack

- **Backend:** Elixir/Phoenix with Ash Framework
- **Frontend:** Phoenix LiveView + Tailwind CSS
- **Database:** PostgreSQL 16
- **Cache:** Redis 7
- **Deployment:** Docker + Docker Compose
- **CI/CD:** GitHub Actions + GHCR
- **Hosting:** Digital Ocean

### Key Components

- **Ash Resources:** Declarative data models in `lib/ehs_enforcement/*/resources/`
- **LiveView Pages:** Real-time UI in `lib/ehs_enforcement_web/live/`
- **Scrapers:** Agency data collection in `lib/ehs_enforcement/scraping/`
- **Integrations:** External API integrations in `lib/ehs_enforcement/integrations/`

### Ash Framework

This project uses [Ash Framework](https://ash-hq.org/) for data modeling. **Important:**

- ✅ Use `Ash.create/2`, `Ash.read/2`, `Ash.update/2`, `Ash.destroy/2`
- ✅ Use `AshPhoenix.Form` for form handling
- ❌ Never use Ecto changesets directly
- ❌ Never use `Repo.insert/update/delete`

See [CLAUDE.md](./CLAUDE.md) for full Ash framework guidelines.

## Documentation

### Development Guides
- [Docker Development Guide](./docs-dev/dev/deployment/current/DOCKER_DEV_GUIDE.md) - Quick reference for docker-compose.dev.yml
- [Database Setup](./README_DATABASE.md) - PostgreSQL configuration
- [Ash Framework Rules](./CLAUDE.md) - Critical Ash patterns and conventions

### Deployment Documentation
- [Deployment Documentation Index](./docs-dev/dev/deployment/README.md) - Overview of all deployment docs
- [Current Deployment Guide](./docs-dev/dev/deployment/current/DEPLOYMENT_CURRENT.md) - Production deployment
- [Deployment Migration Plan](./docs-dev/dev/deployment/current/DEPLOYMENT_MIGRATION_PLAN.md) - Infrastructure setup
- [Deployment Scripts README](./scripts/deployment/README.md) - Script documentation

### Planning Documents
- [Implementation Plan](./docs/IMPLEMENTATION_PLAN.md) - Project roadmap

## Project Structure

```
ehs_enforcement/
├── lib/
│   ├── ehs_enforcement/          # Business logic
│   │   ├── accounts/             # User authentication (Ash)
│   │   ├── agencies/             # Agency-specific scrapers
│   │   ├── enforcement/          # Core enforcement resources (Ash)
│   │   ├── integrations/         # External API integrations
│   │   └── scraping/             # Web scraping coordination
│   └── ehs_enforcement_web/      # Web interface
│       ├── live/                 # LiveView pages
│       └── components/           # Reusable UI components
├── priv/
│   ├── repo/migrations/          # Database migrations
│   └── resource_snapshots/       # Ash resource snapshots
├── scripts/
│   └── deployment/               # Deployment automation
├── docker-compose.dev.yml        # Development environment
└── Dockerfile                    # Production container
```

## Common Commands

```bash
# Development
mix phx.server                    # Start server
iex -S mix phx.server            # Start with IEx

# Database
mix ecto.create                   # Create database
mix ecto.migrate                  # Run Ecto migrations
mix ash.migrate                   # Run Ash migrations (preferred)
mix ecto.reset                    # Drop, create, migrate, seed

# Ash Framework
mix ash.codegen --check          # Generate Ash migrations
mix ash.migrate                  # Apply Ash migrations

# Testing
mix test                         # Run tests
mix test --failed                # Run failed tests only

# Docker
docker compose -f docker-compose.dev.yml up -d postgres redis
docker compose -f docker-compose.dev.yml logs -f
docker compose -f docker-compose.dev.yml down -v

# Deployment
./scripts/deployment/build.sh
./scripts/deployment/test-container.sh
./scripts/deployment/push.sh
./scripts/deployment/deploy-prod.sh
```

## Contributing

1. Create feature branch: `git checkout -b feature/my-feature`
2. Follow Ash Framework patterns (see [CLAUDE.md](./CLAUDE.md))
3. Write tests for new features
4. Test in container mode: `./scripts/deployment/test-container.sh`
5. Create pull request

## Support & Resources

### Documentation
- **Phoenix Framework:** https://phoenixframework.org/
- **Ash Framework:** https://ash-hq.org/
- **LiveView:** https://hexdocs.pm/phoenix_live_view

### Project Links
- **Repository:** https://github.com/shotleybuilder/ehs_enforcement
- **Production:** https://legal.sertantai.com
- **Issues:** https://github.com/shotleybuilder/ehs_enforcement/issues

## License

[Add license information]
