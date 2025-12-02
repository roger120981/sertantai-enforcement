# Getting Started - Developer Guide

Welcome to the EHS Enforcement project! This guide will help you set up your development environment and start contributing.

## Prerequisites

Before you begin, ensure you have the following installed:

- **Elixir 1.15+** and **Erlang/OTP 26+**
- **PostgreSQL 14+** (or Docker to run it in a container)
- **Node.js 18+** (for asset compilation)
- **Git** (for version control)
- **Docker** (optional, recommended for easier database setup)

## Quick Start (5 minutes)

### 1. Clone and Install Dependencies

```bash
# Clone the repository
git clone <repository-url>
cd ehs_enforcement

# Install Elixir dependencies
mix deps.get

# Install Node.js dependencies for assets
cd assets && npm install && cd ..
```

### 2. Start the Database

**Option A: Using Docker (Recommended)**
```bash
# Start PostgreSQL in Docker
./scripts/development/ehs-dev.sh
```

**Option B: Using Local PostgreSQL**
```bash
# If you have PostgreSQL installed locally
./scripts/development/ehs-dev-no-docker.sh
```

**Option C: Manual Database Setup**
```bash
# Configure your database in config/dev.exs, then:
mix ecto.create
mix ash.migrate
```

### 3. Seed the Database (Optional)

```bash
# Load initial data
mix run priv/repo/seeds.exs
```

### 4. Start the Application

```bash
# Start Phoenix server
mix phx.server

# Or start with IEx for interactive development
iex -S mix phx.server
```

Visit `http://localhost:4002` in your browser!

## Project Structure Overview

```
ehs_enforcement/
├── lib/
│   ├── ehs_enforcement/           # Core application logic
│   │   ├── accounts/              # User authentication (Ash resources)
│   │   ├── agencies/              # Agency-specific data processors
│   │   ├── enforcement/           # Core domain: Cases, Notices, Offenders
│   │   ├── integrations/          # External APIs (Airtable, etc.)
│   │   ├── scraping/              # Web scraping modules
│   │   └── config/                # Configuration management
│   └── ehs_enforcement_web/       # Phoenix web interface
│       ├── live/                  # LiveView modules
│       ├── controllers/           # HTTP controllers
│       └── components/            # Reusable UI components
├── test/                          # Test files (mirrors lib/ structure)
├── priv/
│   ├── repo/migrations/           # Database migrations
│   └── resource_snapshots/        # Ash resource snapshots
├── config/                        # Application configuration
├── scripts/                       # Helper scripts (see scripts/README.md)
└── docs-dev/                      # Developer documentation
```

## Understanding the Ash Framework

**⚠️ IMPORTANT**: This project uses the Ash Framework for data modeling and business logic.

### Key Concepts

1. **Resources**: Data models with actions, validations, and policies (in `lib/ehs_enforcement/`)
2. **Actions**: CRUD operations defined on resources (`:create`, `:read`, `:update`, `:destroy`)
3. **Policies**: Authorization rules enforced automatically
4. **Forms**: Use `AshPhoenix.Form` for all form handling

### Critical Rules

**NEVER use standard Ecto patterns. ALWAYS use Ash patterns:**

```elixir
# ❌ WRONG - Standard Ecto
user = Repo.get(User, id)
changeset = Ecto.Changeset.change(user, %{name: "New Name"})
Repo.update(changeset)

# ✅ CORRECT - Ash Framework
{:ok, user} = Ash.get(User, id, actor: current_user)
{:ok, updated_user} = Ash.update(user, %{name: "New Name"}, actor: current_user)
```

**See CLAUDE.md for complete Ash usage rules.**

## Common Development Tasks

### Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/ehs_enforcement/enforcement/case_test.exs

# Run specific test by line number
mix test test/ehs_enforcement/enforcement/case_test.exs:23

# Run with coverage
mix test --cover
```

### Database Operations

```bash
# Create database
mix ecto.create

# Run Ash migrations (preferred for Ash resources)
mix ash.codegen --check  # Check for needed migrations
mix ash.migrate          # Apply Ash migrations

# Run standard Ecto migrations (for non-Ash tables)
mix ecto.migrate

# Reset database (drop, create, migrate, seed)
mix ecto.reset
```

### Code Quality

```bash
# Format code
mix format

# Run static analysis
mix credo

# Check for compile warnings
mix compile --warnings-as-errors

# Run dialyzer (type checking)
mix dialyzer
```

### Interactive Development

```bash
# Start IEx with the application
iex -S mix phx.server

# In IEx, you can:
# - Test functions directly
# - Reload modules: recompile()
# - Access application state
# - Query data using Ash
```

## Development Scripts

The `scripts/` directory contains helpful automation. Key scripts:

| Script | Purpose |
|--------|---------|
| `ehs-dev.sh` | Start dev environment with Docker |
| `ehs-dev-no-docker.sh` | Start dev without Docker |
| `airtable_import.sh` | Import data from Airtable |
| `deploy.sh` | Deploy to production |

**See `scripts/README.md` for complete reference.**

## Configuration

### Environment Variables

Create a `.env` file (not tracked in Git):

```bash
# Airtable Integration
AT_UK_E_API_KEY=your_airtable_api_key

# Database (if not using defaults)
DATABASE_URL=postgresql://postgres:postgres@localhost:5434/sertantai_enforcement_dev

# Secret key (for sessions)
SECRET_KEY_BASE=your_secret_key_here
```

### Configuration Files

- `config/dev.exs` - Development environment
- `config/test.exs` - Test environment
- `config/runtime.exs` - Runtime configuration (reads env vars)

## Next Steps

1. **Read the workflow guide**: See [DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md) for day-to-day development
2. **Learn testing**: See [TESTING_GUIDE.md](TESTING_GUIDE.md) for testing patterns
3. **Explore the API docs**: Open `docs_dev/exdoc/index.html` in your browser
4. **Read Ash usage rules**: See `deps/ash/usage-rules.md` and CLAUDE.md
5. **Join the team**: Ask questions, review PRs, and contribute!

## Getting Help

- **CLAUDE.md**: Critical Ash Framework rules and conventions
- **docs-dev/**: Developer documentation and guides
- **scripts/README.md**: Helper scripts reference
- **Issue Tracker**: Report bugs and request features

## Common First-Time Issues

### Database Connection Errors

```bash
# Check if PostgreSQL is running
docker ps | grep postgres

# Or check local PostgreSQL
pg_isready
```

### Port Already in Use

The app runs on port 4002. If it's in use:

```bash
# Find process using port 4002
lsof -i :4002

# Kill the process
kill -9 <PID>
```

### Asset Compilation Errors

```bash
# Rebuild assets
cd assets
rm -rf node_modules
npm install
cd ..
mix assets.build
```

For more troubleshooting tips, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

**Ready to code?** Continue to [DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md) to learn the day-to-day development process.
