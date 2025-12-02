# EHS Enforcement - Future Deployment Enhancements

**Status:** Optional improvements and future development tools
**Last Updated:** 2025-10-15

This document contains optional enhancements and future improvements that can be implemented to further streamline the development and deployment workflow. The core infrastructure is complete and functional without these additions.

---

## Overview

The current deployment infrastructure is **complete and production-ready**. This document captures optional developer convenience scripts and long-term infrastructure improvements that may be implemented in the future based on team needs.

**Current Status:**
- ✅ Production deployed and running
- ✅ Docker Compose development environment complete
- ✅ Deployment scripts implemented
- ✅ Documentation complete

**This Document Contains:**
- Optional development wrapper scripts
- Integration testing enhancements
- Long-term CI/CD improvements
- Future monitoring and tooling

---

## Optional Development Wrapper Scripts

**Note:** The core docker-compose.dev.yml infrastructure is complete. These wrapper scripts provide convenience commands but are **not required**. All functionality is available via `docker compose` commands (see DOCKER_DEV_GUIDE.md).

### dev.sh - Fast Development Mode (Optional)

**Purpose:** Convenience wrapper for Mode 1 development (Phoenix on host)

**Location:** `scripts/dev.sh`

**Alternative:** Use direct docker compose commands:
```bash
docker compose -f docker-compose.dev.yml up -d postgres redis
export $(grep -v '^#' .env.dev | xargs)
mix phx.server
```

**Script Content (if implementing):**

```bash
#!/bin/bash
# Development Mode 1: Fast development with hot reload
# Phoenix runs on host, services in Docker

set -e

echo "🚀 Starting EHS Enforcement - Fast Development Mode"
echo "===================================================="
echo ""

# Check if docker-compose.dev.yml exists
if [ ! -f "docker-compose.dev.yml" ]; then
    echo "❌ Error: docker-compose.dev.yml not found"
    exit 1
fi

# Check if .env.dev exists
if [ ! -f ".env.dev" ]; then
    echo "❌ Error: .env.dev not found"
    echo "   Create from template: cp .env.dev.example .env.dev"
    exit 1
fi

# Start Docker services (postgres, redis)
echo "📦 Starting Docker services (PostgreSQL, Redis)..."
docker compose -f docker-compose.dev.yml up -d postgres redis

# Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if docker compose -f docker-compose.dev.yml exec -T postgres pg_isready -U postgres > /dev/null 2>&1; then
        echo "✅ PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Timeout waiting for PostgreSQL"
        exit 1
    fi
    sleep 1
done

# Load environment variables
echo "🔧 Loading environment variables from .env.dev..."
export $(grep -v '^#' .env.dev | xargs)

# Setup database
echo "🗄️  Setting up database..."
mix ecto.create 2>/dev/null || echo "   (database already exists)"
mix ecto.migrate

# Install dependencies if needed
if [ ! -d "deps" ] || [ ! -d "_build" ]; then
    echo "📚 Installing dependencies..."
    mix deps.get
    mix deps.compile
fi

# Start Phoenix server
echo ""
echo "✅ Starting Phoenix server on http://localhost:4002"
echo "   Press Ctrl+C to stop"
echo ""

iex -S mix phx.server
```

### dev-container.sh - Container Testing Mode (Optional)

**Purpose:** Convenience wrapper for Mode 2 development (full Docker stack)

**Location:** `scripts/dev-container.sh`

**Alternative:** Use direct docker compose command:
```bash
docker compose -f docker-compose.dev.yml up --build app
```

**Script Content (if implementing):**

```bash
#!/bin/bash
# Development Mode 2: Production-like container testing
# All services including Phoenix run in Docker

set -e

echo "🐳 Starting EHS Enforcement - Container Mode"
echo "============================================="
echo ""

# Check if docker-compose.dev.yml exists
if [ ! -f "docker-compose.dev.yml" ]; then
    echo "❌ Error: docker-compose.dev.yml not found"
    exit 1
fi

# Load environment variables if .env.dev exists
if [ -f ".env.dev" ]; then
    export $(grep -v '^#' .env.dev | xargs)
fi

# Build and start all services
echo "🔨 Building Docker image and starting services..."
docker compose -f docker-compose.dev.yml up --build app

# Logs will stream automatically
```

### dev-stop.sh - Stop Services (Optional)

**Purpose:** Convenience wrapper to stop all development services

**Location:** `scripts/dev-stop.sh`

**Alternative:** Use direct docker compose command:
```bash
docker compose -f docker-compose.dev.yml down
```

**Script Content (if implementing):**

```bash
#!/bin/bash
# Stop all development services

set -e

echo "🛑 Stopping EHS Enforcement development services..."

if [ -f "docker-compose.dev.yml" ]; then
    docker compose -f docker-compose.dev.yml down
    echo "✅ Development services stopped"
else
    echo "⚠️  docker-compose.dev.yml not found"
fi
```

### dev-integration.sh - Integration Testing Mode (Optional)

**Purpose:** Convenience wrapper for Mode 3 development (with Baserow)

**Location:** `scripts/dev-integration.sh`

**Alternative:** Use direct docker compose command:
```bash
docker compose -f docker-compose.dev.yml --profile integration up -d
```

**Script Content (if implementing):**

```bash
#!/bin/bash
# Start development environment with Baserow for integration testing

set -e

echo "🔗 Starting EHS Enforcement with Baserow - Integration Mode"
echo "============================================================"
echo ""

# Check if docker-compose.dev.yml exists
if [ ! -f "docker-compose.dev.yml" ]; then
    echo "❌ Error: docker-compose.dev.yml not found"
    exit 1
fi

# Load environment variables
if [ -f ".env.dev" ]; then
    export $(grep -v '^#' .env.dev | xargs)
fi

# Start all services including Baserow
echo "📦 Starting services (this may take a few minutes)..."
docker compose -f docker-compose.dev.yml --profile integration up -d

echo ""
echo "✅ Services started:"
echo "   - Phoenix app: http://localhost:4002"
echo "   - Baserow: http://localhost:8080"
echo "   - PostgreSQL: localhost:5434"
echo "   - Redis: localhost:6379"
echo ""
echo "📋 View logs with:"
echo "   docker compose -f docker-compose.dev.yml logs -f"
echo ""
```

### Implementation Steps (If Desired)

```bash
cd /home/jason/Desktop/ehs-enforcement

# Create the scripts
# (Copy content from above into respective files)

# Make executable
chmod +x scripts/dev.sh
chmod +x scripts/dev-container.sh
chmod +x scripts/dev-stop.sh
chmod +x scripts/dev-integration.sh
```

---

## Optional Integration Testing Enhancements

The Baserow integration infrastructure is ready via `--profile integration`. These are optional testing enhancements:

### Test Baserow Integration

**Status:** Infrastructure ready, testing optional

**Steps:**
1. Start with Baserow profile:
   ```bash
   docker compose -f docker-compose.dev.yml --profile integration up -d
   ```

2. Access Baserow at http://localhost:8080

3. Create PostgreSQL database sync:
   - Connect to: `postgres:5432` (Docker network)
   - Database: `sertantai_enforcement_dev`
   - User/Password: `postgres/postgres`

4. Verify data synchronization:
   - Create records in Phoenix app
   - Check they appear in Baserow
   - Test bidirectional sync if needed

### Integration Test Checklist

- [ ] Baserow connects to dev database
- [ ] Data flows Phoenix → Baserow
- [ ] Data flows Baserow → Phoenix (if needed)
- [ ] Performance is acceptable
- [ ] Error handling works correctly

---

## Long-term Infrastructure Improvements

These are future enhancements that can improve the deployment pipeline but are not required for current operations.

### 1. CI/CD Pipeline Automation

**Status:** Not implemented
**Priority:** Medium
**Estimated Time:** 4-8 hours

**Goal:** Automate Docker builds and deployments via GitHub Actions

**Implementation:**

```yaml
# .github/workflows/deploy.yml
name: Build and Deploy

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18.2'
          otp-version: '27'
      - name: Run tests
        run: |
          mix deps.get
          mix test

  build:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build Docker image
        run: docker build -t ghcr.io/shotleybuilder/ehs-enforcement:latest .
      - name: Push to GHCR
        run: |
          echo ${{ secrets.GITHUB_TOKEN }} | docker login ghcr.io -u ${{ github.actor }} --password-stdin
          docker push ghcr.io/shotleybuilder/ehs-enforcement:latest

  deploy:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to production
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.PRODUCTION_HOST }}
          username: ${{ secrets.PRODUCTION_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: |
            cd ~/infrastructure/docker
            docker compose pull ehs-enforcement
            docker compose up -d ehs-enforcement
```

**Benefits:**
- Automatic builds on push to main
- Automatic testing before deployment
- No manual build/push steps required

### 2. Automated Container Testing

**Status:** Not implemented
**Priority:** Medium
**Estimated Time:** 2-4 hours

**Goal:** Run integration tests in container before deployment

**Implementation:**

```bash
# .github/workflows/test-container.yml
- name: Test container
  run: |
    docker compose -f docker-compose.dev.yml up -d
    # Wait for services
    sleep 10
    # Run health checks
    curl http://localhost:4002/health
    # Run integration tests
    docker compose -f docker-compose.dev.yml exec -T app mix test
    # Cleanup
    docker compose -f docker-compose.dev.yml down -v
```

**Benefits:**
- Catch container-specific issues before production
- Verify migrations run correctly
- Test production-like environment

### 3. Staging Environment

**Status:** Not implemented
**Priority:** Low-Medium
**Estimated Time:** 4-6 hours

**Goal:** Create a staging environment that mirrors production

**Implementation:**
- Add staging subdomain (staging.legal.sertantai.com)
- Create `ehs_enforcement_staging` database
- Update nginx configuration
- Create separate deployment workflow

**Benefits:**
- Test deployments before production
- Demo features to stakeholders
- Isolate testing from production data

### 4. Monitoring and Metrics

**Status:** Not implemented
**Priority:** Medium
**Estimated Time:** 6-10 hours

**Goal:** Add comprehensive monitoring and logging

**Options:**

**4a. Prometheus + Grafana**
- Add telemetry metrics export
- Set up Prometheus scraping
- Create Grafana dashboards
- Alert on errors/performance issues

**4b. Log Aggregation**
- Centralize logs with Loki or ELK
- Add structured logging
- Create log-based alerts

**4c. Application Performance Monitoring**
- Integrate AppSignal or similar
- Track slow requests
- Monitor memory/CPU usage
- Track database query performance

**Benefits:**
- Proactive issue detection
- Performance optimization insights
- Better debugging capabilities

### 5. Database Backup Automation

**Status:** Manual backups only
**Priority:** High (when production data is critical)
**Estimated Time:** 2-3 hours

**Goal:** Automate regular database backups

**Implementation:**

```bash
# Cron job on production server
# /etc/cron.d/ehs-enforcement-backup

# Daily backup at 2 AM
0 2 * * * root cd /root/infrastructure/docker && docker compose exec -T postgres pg_dump -U postgres ehs_enforcement_prod | gzip > /root/infrastructure/backups/ehs_$(date +\%Y\%m\%d).sql.gz

# Cleanup old backups (keep 30 days)
0 3 * * * root find /root/infrastructure/backups -name "ehs_*.sql.gz" -mtime +30 -delete
```

**Enhanced:** Upload to S3 or backup service

**Benefits:**
- Automatic backup schedule
- Data loss prevention
- Easy recovery process

### 6. Health Check Dashboard

**Status:** Not implemented
**Priority:** Low
**Estimated Time:** 3-5 hours

**Goal:** Simple dashboard showing system health

**Implementation:**
- Create simple web page polling health endpoints
- Show status of all services
- Display recent deployments
- Link to logs and metrics

**Benefits:**
- Quick system overview
- Team visibility
- External status page potential

---

## Implementation Priorities

### High Priority (If Needed)
1. Database backup automation (when production data is critical)
2. Basic monitoring/alerting (when system reliability is crucial)

### Medium Priority
1. CI/CD pipeline (reduces manual deployment effort)
2. Automated container testing (improves deployment confidence)
3. Staging environment (useful for larger teams)

### Low Priority
1. Advanced monitoring (nice to have)
2. Health dashboard (cosmetic improvement)
3. Development wrapper scripts (convenience only)

---

## Decision Criteria

**Implement these features when:**

- **CI/CD:** Manual deployments become frequent (>2/week)
- **Staging:** Team size grows or deployment risk increases
- **Monitoring:** Production issues are hard to diagnose
- **Backups:** Production data becomes business-critical
- **Scripts:** Team requests convenience wrappers
- **Container Tests:** Integration bugs reach production

**Current Assessment:** Core infrastructure complete. These enhancements are optional based on team growth and operational needs.

---

## Resources

### Documentation References
- [DEPLOYMENT_CURRENT.md](../current/DEPLOYMENT_CURRENT.md) - Current deployment guide
- [DOCKER_DEV_GUIDE.md](../current/DOCKER_DEV_GUIDE.md) - Development environment
- [README.md](../../../../README.md) - Project overview

### External Resources
- GitHub Actions Documentation: https://docs.github.com/actions
- Prometheus Monitoring: https://prometheus.io/
- Phoenix Telemetry: https://hexdocs.pm/phoenix/telemetry.html

---

**Last Updated:** 2025-10-15
**Status:** Optional enhancements - implement based on team needs
**Maintainer:** Update this document as improvements are implemented
