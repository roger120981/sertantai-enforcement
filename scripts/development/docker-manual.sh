#!/bin/bash

# Sertantai Enforcement Development - Manual Docker Commands
# Use this if docker-compose isn't available

# Resolve symlink to get the actual script path
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/../.." && pwd)"
cd "$PROJECT_ROOT"

echo "🐳 Starting PostgreSQL with manual Docker commands..."

# Stop any existing container
docker stop sertantai_enforcement_postgres 2>/dev/null
docker rm sertantai_enforcement_postgres 2>/dev/null

# Create and start PostgreSQL container manually
docker run -d \
  --name sertantai_enforcement_postgres \
  -e POSTGRES_DB=sertantai_enforcement_dev \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5434:5432 \
  -v sertantai_enforcement_postgres_data:/var/lib/postgresql/data \
  --restart unless-stopped \
  postgres:16 \
  -c wal_level=logical \
  -c max_replication_slots=10 \
  -c max_wal_senders=10 \
  -c max_connections=200

echo "⏳ Waiting for PostgreSQL to be ready..."
sleep 8

# Wait for PostgreSQL to accept connections
echo "🔍 Checking PostgreSQL connection..."
timeout=30
while ! docker exec sertantai_enforcement_postgres pg_isready -U postgres >/dev/null 2>&1; do
    timeout=$((timeout - 1))
    if [ $timeout -eq 0 ]; then
        echo "❌ PostgreSQL failed to start within 30 seconds"
        exit 1
    fi
    sleep 1
done

echo "✅ PostgreSQL container running on port 5434"

# Create database
echo "📦 Setting up database..."
mix ecto.create

# Start based on argument
if [ "$1" = "iex" ]; then
    echo "🚀 Starting in iex mode..."
    iex -S mix phx.server
else
    echo "🚀 Starting development server..."
    mix phx.server
fi
