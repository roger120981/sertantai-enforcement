#!/bin/bash

# Sertantai Enforcement Development Starter

# Resolve symlink to get the actual script path
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/../.." && pwd)"
cd "$PROJECT_ROOT"

echo "🐳 Starting Sertantai Enforcement PostgreSQL..."

# Start container
docker compose -f docker-compose.dev.yml up -d postgres

echo "⏳ Waiting for PostgreSQL to be ready..."
sleep 5

# Test if container is actually running
if docker ps | grep -q "sertantai_enforcement_postgres"; then
    echo "✅ PostgreSQL container running"
else
    echo "❌ PostgreSQL container failed to start"
    echo "Checking logs:"
    docker logs sertantai_enforcement_postgres
    exit 1
fi

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
