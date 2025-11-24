# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## DEVELOPER DOCUMENTATION

**📚 Comprehensive developer guides are available in `docs-dev/`:**

- **[docs-dev/GETTING_STARTED.md](docs-dev/GETTING_STARTED.md)** - Initial setup and prerequisites
- **[docs-dev/DEVELOPMENT_WORKFLOW.md](docs-dev/DEVELOPMENT_WORKFLOW.md)** - Day-to-day development process
- **[docs-dev/TESTING_GUIDE.md](docs-dev/TESTING_GUIDE.md)** - Testing patterns and best practices
- **[docs-dev/TROUBLESHOOTING.md](docs-dev/TROUBLESHOOTING.md)** - Common issues and solutions
- **[scripts/README.md](scripts/README.md)** - Complete reference for all helper scripts

**For a complete overview, see [docs-dev/README.md](docs-dev/README.md)**

## 🚀 QUICK START: DEVELOPMENT ENVIRONMENT

**⚠️ IMPORTANT: Always use these scripts to start/stop the development environment!**

### Start the Complete Development Environment

```bash
# Start all services (PostgreSQL, ElectricSQL, Phoenix, Frontend)
./scripts/development/sert-enf-start
```

This script will:
- Start Docker services (PostgreSQL on port 5434, ElectricSQL on port 3001)
- Start Phoenix backend (port 4002)
- Start Frontend dev server (port 5173)
- Ensure all services are healthy before proceeding

### Stop the Development Environment

```bash
# Stop all services gracefully
./scripts/development/sert-enf-stop
```

This script will:
- Stop frontend dev server
- Stop Phoenix backend
- Stop Docker services (PostgreSQL, ElectricSQL)
- Clean up processes

### Alternative Development Scripts

If you need more control, see additional scripts in `scripts/development/`:
- `ehs-dev.sh` - Start dev with Docker
- `ehs-dev-no-docker.sh` - Start dev without Docker
- `start-dev.sh` - Quick Phoenix server start
- `docker-manual.sh` - Manual Docker management

**See [scripts/README.md](scripts/README.md) for complete script documentation**

---

## SESSION DOCUMENTATION

When working within an active development session:
- **CHECK** for active session: `.claude/sessions/.current-session`
- **UPDATE** the active session document with progress, findings, and key decisions
- **DOCUMENT** important discoveries, bugs found, and solutions implemented in the session file

When completing major builds or milestones without an active session:
- **SAVE** build summaries to `~/Desktop/claude_build_summaries/[title].md`

**⚠️ CRITICAL: Git and Session Files**
- **NEVER** use `git add -f` to force-add files in `.gitignore`
- Session files in `.claude/sessions/` are gitignored for good reason (local development only)
- **NEVER** commit session files or `.current-session` to the repository
- Respect all `.gitignore` settings - they exist for security and project hygiene

## ⚠️ CRITICAL ASH FRAMEWORK RULES

**🚫 NEVER USE STANDARD ECTO/PHOENIX PATTERNS - ALWAYS USE ASH PATTERNS**

### Database Operations
- **NEVER**: `Ecto.Changeset.cast/3`, `Repo.insert/1`, `Repo.update/1`, `Repo.get/2`
- **ALWAYS**: `Ash.create/2`, `Ash.update/2`, `Ash.read/2`, `Ash.get/2`, `Ash.destroy/2`

### Forms and Changesets
- **NEVER**: `Ecto.Changeset.change/2`, `Phoenix.HTML.Form` with Ecto changesets
- **ALWAYS**: `AshPhoenix.Form.for_create/3`, `AshPhoenix.Form.for_update/3`, `AshPhoenix.Form.validate/2`, `AshPhoenix.Form.submit/2`

### Data Queries
- **NEVER**: `from(u in User, where: u.role == :admin) |> Repo.all()`
- **ALWAYS**: `Ash.read(User, actor: current_user)` with Ash queries and filters

### Resource Actions
- **NEVER**: Define custom functions that bypass Ash actions
- **ALWAYS**: Use defined Ash actions like `:register_with_password`, `:update_role`, etc.

### Authentication Integration
- **NEVER**: Custom authentication logic bypassing Ash policies
- **ALWAYS**: Use `actor: current_user` parameter in all Ash calls for policy enforcement

### Error Handling
- **NEVER**: `{:error, %Ecto.Changeset{}}` pattern matching
- **ALWAYS**: `{:error, %Ash.Error{}}` and `AshPhoenix.Form` error handling

### Pre-Development Checklist
**Before writing ANY code that interacts with data:**
1. ✅ Check existing Ash resource definitions in `lib/sertantai/`
2. ✅ Identify available Ash actions (`:create`, `:read`, `:update`, `:destroy`, custom actions)
3. ✅ Use `AshPhoenix.Form` for all form handling
4. ✅ Use `Ash.*` functions for all database operations
5. ✅ Include `actor: current_user` in all calls for authorization
6. ✅ Test with Ash policies and authorization in mind

### Common Ash Patterns
```elixir
# Forms
form = AshPhoenix.Form.for_create(User, :register_with_password, forms: [auto?: false])
form = AshPhoenix.Form.for_update(user, :update, forms: [auto?: false])
form = AshPhoenix.Form.validate(form, params)
{:ok, user} = AshPhoenix.Form.submit(form, params: params)

# Database Operations
{:ok, users} = Ash.read(User, actor: current_user)
{:ok, user} = Ash.get(User, id, actor: current_user)
{:ok, user} = Ash.create(User, params, action: :register_with_password, actor: current_user)
{:ok, user} = Ash.update(user, params, action: :update, actor: current_user)
:ok = Ash.destroy(user, actor: current_user)
```

**⚠️ GOLDEN RULE**: After any code changes involving Ash resources, ALWAYS run:
1. `mix ash.codegen --check` (generate any needed migrations)
2. `mix ash.migrate` (apply pending Ash migrations)
3. THEN start the server with `mix phx.server`

**⚠️ CRITICAL**: Use `mix ash.migrate` NOT `mix ecto.migrate` for Ash-generated migrations!

**Never let the app run ahead of the database schema!**

**⚠️ ASH QUERY COMPILATION REQUIREMENTS:**
- **ALWAYS add `require Ash.Query` and `import Ash.Expr`** at the top of test files using Ash queries
- **Required for filter expressions**: `Ash.Query.filter(active == true)` won't compile without these imports
- **Enables query building**: Without these, variables like `active` in filters cause "undefined variable" errors
- **Add BEFORE any Ash.Query operations**: Place after other aliases but before describe blocks

**⚠️ MIGRATION SAFETY RULES:**
- **ALWAYS check existing schema** before creating migrations with `mix ecto.migrations`
- **NEVER assume table structure** - use `\d table_name` in psql or check existing migrations
- **VERIFY resource snapshots** in `priv/resource_snapshots/` before running `mix ash.codegen`
- **TEST migrations safely** by checking generated SQL in migration files before applying
- **REMOVE EXISTING TABLES** from generated migrations if they already exist in the database

## Development Commands

### Essential Commands
- `mix setup` - Install dependencies, setup database, and build assets
- `mix phx.server` - Start Phoenix server (http://localhost:4000)
- `iex -S mix phx.server` - Start server with interactive Elixir shell
- `mix test` - Run all tests
- `mix ecto.reset` - Drop, create, migrate, and seed database

### Asset Management
- `mix assets.build` - Build assets (Tailwind CSS + esbuild)
- `mix assets.deploy` - Build and minify assets for production

### Database Operations
- `mix ecto.create` - Create database
- `mix ash.migrate` - Run Ash-generated migrations (preferred for Ash resources)
- `mix ecto.migrate` - Run standard Ecto migrations (use only for non-Ash tables)
- `mix ecto.drop` - Drop database

## Architecture Overview

This is a Phoenix LiveView application for collecting and managing UK environmental, health, and safety enforcement data. The app is currently in Phase 2 of development, transitioning from legacy `Legl.*` modules to new `EhsEnforcement.*` structure.

### Core Components

**Legacy Structure (removed)**:
- `Legl.Countries.Uk.LeglEnforcement.*` - HSE enforcement processing modules (removed)
- `Legl.Services.Hse.*` - HSE website scraping clients (removed)
- `Legl.Services.Airtable.*` - Airtable API integration (removed Nov 2025)

**Current Structure**:
- `EhsEnforcement.Agencies.*` - Agency-specific data collection and processing
- `EhsEnforcement.Integrations.*` - External service integrations
- `EhsEnforcement.Enforcement.*` - Core enforcement data models (Ash resources)

### Key Dependencies

- **Database**: PostgreSQL (via Ecto and Ash)
- **HTTP Clients**: Tesla, Req for external API calls
- **Phoenix 1.7+** - Web framework
- **Ash 3.0+** - Data modeling and business logic framework
- **Ash Phoenix** - Phoenix integration for Ash
- **LiveView** - Real-time UI components
- **Ecto/PostgreSQL** - Database layer
- **Tailwind CSS** - Styling framework
- **ESBuild** - JavaScript bundling

### Data Flow

1. **Web Scraping**: Agency-specific scrapers fetch data from regulator websites (HSE, EA, SEPA, NRW)
2. **Processing**: Scrapers parse and structure enforcement data
3. **Storage**: Data stored in PostgreSQL via Ash resources
4. **UI**: Svelte 5 frontend with Phoenix backend API

### Current Development Phase

**Phase 2: Service Integration** - Module refactoring from `Legl.*` to `EhsEnforcement.*` namespace is in progress. See `docs/MODULE_REFACTORING.md` for detailed mapping.

### Configuration

- Database configuration in `config/` directory
- Agency-specific settings in `config/runtime.exs`
- Environment variables for GitHub OAuth and other external services

### Testing

- Test files follow same structure as `lib/` directory
- HSE enforcement logic has existing test coverage in `test/ehs_enforcement/countries/uk/legl_enforcement/`
- Use `mix test path/to/specific_test.exs` for single test files

**⚠️ CRITICAL TESTING RULES:**
- **NEVER create scripts in `/scripts` for testing** - Always use proper ExUnit tests in `/test` folder
- **ALWAYS use ExUnit framework** with `describe` blocks, proper `setup` callbacks, and `test` macros
- **FOLLOW Phoenix LiveView testing patterns** using `Phoenix.LiveViewTest` for LiveView components
- **USE proper test assertions** like `assert`, `refute`, `assert_receive`, etc.
- **CREATE integration tests** in `/test` folder that mirror real application usage
- **INCLUDE proper test setup and teardown** with database transactions

### ExUnit Testing Patterns
```elixir
defmodule MyAppWeb.MyLiveTest do
  use MyAppWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "LiveView functionality" do
    setup do
      # Setup test data using Ash patterns
      {:ok, user} = MyApp.Accounts.create_user(%{...})
      %{user: user}
    end

    test "displays data correctly", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, "/path")
      assert html =~ "expected content"
      assert has_element?(view, "[data-testid='element']")
    end
  end
end
```

**MANUAL TESTING APPROACH (Secondary):**
1. **Use Tidewave MCP** to examine test results and outputs instead of running tests directly
2. **Access via**: Project-specific `mcpServers.json` configuration (port 4002)
3. **Query test files** and examine expected vs actual behavior through MCP interface
4. **Validate functionality** by examining code paths and test assertions manually

**⚠️ PORT CONFIGURATION**:
- **EHS Enforcement runs on port 4002** (configured in `config/dev.exs`)
- **Tidewave MCP is available at** `http://localhost:4002/tidewave/mcp` when the app is running
- **MCP configuration** is in project-specific `mcpServers.json` file
- **Other Phoenix projects** use different ports (Sertantai: 4000, etc.) to avoid conflicts

<!-- usage-rules-start -->
<!-- usage-rules-header -->
# Usage Rules

**IMPORTANT**: Consult these usage rules early and often when working with the packages listed below. 
Before attempting to use any of these packages or to discover if you should use them, review their 
usage rules to understand the correct patterns, conventions, and best practices.
<!-- usage-rules-header-end -->

<!-- ash_graphql-start -->
## ash_graphql usage
_The extension for building GraphQL APIs with Ash_

[ash_graphql usage rules](deps/ash_graphql/usage-rules.md)
<!-- ash_graphql-end -->
<!-- ash-start -->
## ash usage
_A declarative, extensible framework for building Elixir applications._

[ash usage rules](deps/ash/usage-rules.md)
<!-- ash-end -->
<!-- ash_postgres-start -->
## ash_postgres usage
_The PostgreSQL data layer for Ash Framework_

[ash_postgres usage rules](deps/ash_postgres/usage-rules.md)
<!-- ash_postgres-end -->
<!-- igniter-start -->
## igniter usage
_A code generation and project patching framework_

[igniter usage rules](deps/igniter/usage-rules.md)
<!-- igniter-end -->
<!-- usage_rules-start -->
## usage_rules usage
_A dev tool for Elixir projects to gather LLM usage rules from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
# Elixir Core Usage Rules

## Pattern Matching
- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies

## Error Handling
- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid
- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design
- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark. 
- Names like `is_thing` should be reserved for guards

## Data Structures
- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing
- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
# OTP Usage Rules

## GenServer Best Practices
- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication
- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, us `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance
- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async
- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- ash_phoenix-start -->
## ash_phoenix usage
_Utilities for integrating Ash and Phoenix_

[ash_phoenix usage rules](deps/ash_phoenix/usage-rules.md)
<!-- ash_phoenix-end -->
<!-- ash_json_api-start -->
## ash_json_api usage
_The JSON:API extension for the Ash Framework._

[ash_json_api usage rules](deps/ash_json_api/usage-rules.md)
<!-- ash_json_api-end -->
<!-- usage-rules-end -->
