#!/bin/bash

# Sertantai Enforcement Development Environment Startup Script

# Resolve symlink to get the actual script path
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/../.." && pwd)"
cd "$PROJECT_ROOT"

# Stop any existing container first to avoid conflicts
docker compose -f docker-compose.dev.yml stop postgres 2>/dev/null

# Check if PostgreSQL container is running
if ! docker ps --format "table {{.Names}}" | grep -q "sertantai_enforcement_postgres"; then
    echo "🐳 Starting PostgreSQL container..."
    docker compose -f docker-compose.dev.yml up -d postgres
    echo "⏳ Waiting for PostgreSQL to be ready..."
    sleep 8  # Give more time for PostgreSQL to fully start

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
else
    echo "✅ PostgreSQL container already running"
fi

# Create database if it doesn't exist
echo "📦 Setting up database..."
mix ecto.create

# Start Phoenix server or iex based on argument
if [ "$1" = "iex" ]; then
    echo "🚀 Starting Sertantai Enforcement in iex mode..."
    iex -S mix phx.server
else
    echo "🚀 Starting Sertantai Enforcement development server..."
    mix phx.server
fi
