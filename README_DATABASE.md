# EHS Enforcement Database Setup

## Why Docker?

This app uses Docker for PostgreSQL (like sertantai) to avoid local installation conflicts and ensure consistent development environments. The container runs on port 5433 to avoid conflicts with other PostgreSQL instances.

**If you get "Cannot connect to the Docker daemon" error**, see the Docker troubleshooting section below.

## Troubleshooting Connection Issues

### Most Common Issue: Container Not Running
```bash
# Check if container is running
docker ps | grep ehs_enforcement_postgres

# If not running, start it
docker compose up -d postgres

# Check logs if there are issues
docker logs ehs_enforcement_postgres
```

### Docker Compose Issues

If you get `Command 'docker-compose' not found` or Python distutils errors:

**Root Cause**: There are two Docker Compose versions:
- `docker-compose` (older, Python-based, often broken)
- `docker compose` (newer, built into Docker, reliable)

**Solution**: Use the newer `docker compose` (without hyphen)

**Check which version works:**
```bash
# Test older version
docker-compose version

# Test newer version (recommended)
docker compose version
```

Our scripts now use `docker compose` (newer version).

### Clean Start (Fixes Most Issues)
```bash
# Stop and remove everything
docker compose down -v

# Start fresh
ehs-dev
```

### Docker Context Issues

If you get `Cannot connect to the Docker daemon at unix:///home/jason/.docker/desktop/docker.sock`:

**Root Cause**: Your system has system Docker running, but Docker is trying to connect to Docker Desktop.

**Quick Fix**:
```bash
# Check current context
docker context ls

# Switch to system Docker (default context)
docker context use default

# Test that it works
docker ps
```

**Why This Happens**: 
- System Docker uses socket: `/var/run/docker.sock`
- Docker Desktop uses socket: `/home/jason/.docker/desktop/docker.sock` 
- Docker was configured to use Desktop context but you're running system Docker

**Verify Fix**: 
- `docker ps` should work without errors
- `sertantai-dev` should still work (it was already using correct context)

### Port Conflicts
If port 5433 is already in use, update `docker-compose.yml`:
```yaml
ports:
  - "5434:5432"  # Use different port
```

Then update `config/dev.exs` to match:
```elixir
port: 5434,
```

## Quick Start

### 1. Add Development Alias

Add this alias to your shell for easy startup:

```bash
echo 'ehs-dev() {
    cd /home/jason/Desktop/ehs-enforcement

    # Stop any existing container first to avoid conflicts
    docker compose stop postgres 2>/dev/null
    
    # Check if PostgreSQL container is running
    if ! docker ps --format "table {{.Names}}" | grep -q "ehs_enforcement_postgres"; then
        echo "🐳 Starting PostgreSQL container..."
        docker compose up -d postgres
        echo "⏳ Waiting for PostgreSQL to be ready..."
        sleep 8  # Give more time for PostgreSQL to fully start
        
        # Wait for PostgreSQL to accept connections
        echo "🔍 Checking PostgreSQL connection..."
        timeout=30
        while ! docker exec ehs_enforcement_postgres pg_isready -U postgres >/dev/null 2>&1; do
            timeout=$((timeout - 1))
            if [ $timeout -eq 0 ]; then
                echo "❌ PostgreSQL failed to start within 30 seconds"
                return 1
            fi
            sleep 1
        done
    else
        echo "✅ PostgreSQL container already running"
    fi
    
    # Create database if it doesn't exist
    echo "📦 Setting up database..."
    mix ecto.create
    
    # Start Phoenix server or iex based on argument
    if [ "$1" = "iex" ]; then
        echo "🚀 Starting EHS Enforcement in iex mode..."
        iex -S mix phx.server
    else
        echo "🚀 Starting EHS Enforcement development server..."
        mix phx.server
    fi
}' >> ~/.bashrc

source ~/.bashrc
```

### 2. Usage

**Start development server:**
```bash
ehs-dev
```

**Start with iex (interactive mode):**
```bash
ehs-dev iex
```

**Stop server:**
```bash
Ctrl+C  # Press twice to stop
```

**Stop PostgreSQL container:**
```bash
docker compose down
```

## Manual Setup

If you prefer manual control:

1. **Start PostgreSQL:**
   ```bash
   docker compose up -d postgres
   ```

2. **Create database:**
   ```bash
   mix ecto.create
   ```

3. **Run migrations (when available):**
   ```bash
   mix ecto.migrate
   ```

4. **Start Phoenix:**
   ```bash
   mix phx.server
   # OR for interactive mode:
   iex -S mix phx.server
   ```

## Database Configuration

- **Host:** localhost
- **Port:** 5434 (Docker container port, avoids conflicts)
- **Database:** sertantai_enforcement_dev
- **Username:** postgres
- **Password:** postgres
- **Container:** ehs_enforcement_postgres
- **Docker Compose:** `docker compose` (newer version without hyphen)

## Docker Commands

**View logs:**
```bash
docker logs ehs_enforcement_postgres
```

**Access PostgreSQL shell:**
```bash
docker exec -it ehs_enforcement_postgres psql -U postgres -d sertantai_enforcement_dev
```

**Stop and remove container:**
```bash
docker compose down
```

**Stop but keep data:**
```bash
docker compose stop postgres
```

**Remove everything including data:**
```bash
docker compose down -v
```

## Testing HSE Scrapers Without Database Errors

Once the database is running, you can test the HSE scrapers in iex:

```elixir
# Start with: ehs-dev iex

# Test HSE Notices
EhsEnforcement.Agencies.Hse.Notices.api_get_hse_notices([pages: "1", country: "England"])

# Test HSE Cases
EhsEnforcement.Agencies.Hse.Cases.api_get_hse_cases([pages: "1"])

# Test by Case ID
EhsEnforcement.Agencies.Hse.Cases.api_get_hse_case_by_id()
```

The Postgrex errors should now be gone!