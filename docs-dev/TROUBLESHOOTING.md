# Troubleshooting Guide

Common issues and solutions for EHS Enforcement development.

## Table of Contents

- [Database Issues](#database-issues)
- [Application Startup Issues](#application-startup-issues)
- [Ash Framework Issues](#ash-framework-issues)
- [Migration Issues](#migration-issues)
- [Phoenix/LiveView Issues](#phoenixliveview-issues)
- [Asset Compilation Issues](#asset-compilation-issues)
- [Testing Issues](#testing-issues)
- [Docker Issues](#docker-issues)
- [Performance Issues](#performance-issues)
- [Integration Issues](#integration-issues)

## Database Issues

### Cannot Connect to Database

**Symptom:**
```
** (Postgrex.Error) FATAL (invalid_catalog_name): database "sertantai_enforcement_dev" does not exist
```

**Solutions:**

1. **Database doesn't exist:**
   ```bash
   mix ecto.create
   ```

2. **PostgreSQL not running:**
   ```bash
   # Check if PostgreSQL is running
   pg_isready

   # If using Docker
   docker ps | grep postgres

   # Start with script
   ./scripts/development/ehs-dev.sh
   ```

3. **Wrong connection settings:**
   ```bash
   # Check config/dev.exs for correct settings
   # Default: localhost:5434, user: postgres, password: postgres

   # Test connection manually
   psql -h localhost -p 5434 -U postgres -d sertantai_enforcement_dev
   ```

---

### Database Migration Errors

**Symptom:**
```
** (Postgrex.Error) ERROR 42P07 (duplicate_table): relation "cases" already exists
```

**Solutions:**

1. **Table already exists:**
   ```bash
   # Check existing tables
   psql -d sertantai_enforcement_dev -c "\dt"

   # If development, reset database
   mix ecto.reset

   # If migration issue, rollback and fix
   mix ecto.rollback
   # Edit migration to use create_if_not_exists
   mix ecto.migrate
   ```

2. **Ash resource snapshot out of sync:**
   ```bash
   # Check for pending Ash migrations
   mix ash.codegen --check

   # Regenerate snapshots
   mix ash.codegen

   # Apply migrations
   mix ash.migrate
   ```

---

### Port Already in Use (Database)

**Symptom:**
```
Error starting userland proxy: listen tcp4 0.0.0.0:5434: bind: address already in use
```

**Solutions:**

1. **Find and kill process:**
   ```bash
   # Find process on port 5434
   lsof -i :5434

   # Kill the process
   kill -9 <PID>

   # Or stop Docker container
   docker ps
   docker stop ehs_postgres_dev
   ```

2. **Use different port:**
   ```bash
   # Edit docker command in scripts/development/ehs-dev.sh
   # Change -p 5434:5432 to -p 5435:5432
   # Update config/dev.exs to use port 5435
   ```

---

## Application Startup Issues

### Port Already in Use (Phoenix)

**Symptom:**
```
** (RuntimeError) failed to start Ranch listener because address already in use
```

**Solutions:**

1. **Kill existing process:**
   ```bash
   # Find process on port 4002
   lsof -i :4002

   # Kill it
   kill -9 <PID>
   ```

2. **Change port:**
   ```elixir
   # Edit config/dev.exs
   config :ehs_enforcement, EhsEnforcementWeb.Endpoint,
     http: [ip: {127, 0, 0, 1}, port: 4003]  # Change port
   ```

---

### Mix Dependencies Issues

**Symptom:**
```
** (Mix) Could not compile dependency :ash, "mix compile" failed.
```

**Solutions:**

1. **Clean and reinstall:**
   ```bash
   mix deps.clean --all
   rm -rf _build
   mix deps.get
   mix compile
   ```

2. **Update dependencies:**
   ```bash
   mix deps.update --all
   ```

3. **Check Elixir/Erlang versions:**
   ```bash
   elixir --version
   # Should be Elixir 1.15+ and Erlang/OTP 26+
   ```

---

### Compilation Errors

**Symptom:**
```
== Compilation error in file lib/ehs_enforcement/enforcement/case.ex ==
** (CompileError) undefined function ...
```

**Solutions:**

1. **Force recompile:**
   ```bash
   mix compile --force
   ```

2. **Clean build:**
   ```bash
   rm -rf _build
   mix deps.compile
   mix compile
   ```

3. **Check for syntax errors:**
   ```bash
   # Use editor with Elixir LSP for better error messages
   ```

---

## Ash Framework Issues

### Undefined Variable in Ash Query Filter

**Symptom:**
```
** (CompileError) undefined variable "active" in query
```

**Solution:**

Add required imports at top of file:

```elixir
defmodule MyTest do
  use EhsEnforcement.DataCase

  # ADD THESE LINES
  require Ash.Query
  import Ash.Expr

  # Now filters work
  test "filter" do
    Case
    |> Ash.Query.filter(active == true)
    |> Ash.read()
  end
end
```

---

### Ash Resource Not Found

**Symptom:**
```
** (Ash.Error.Invalid.NoSuchResource) No such resource MyResource
```

**Solutions:**

1. **Add resource to domain:**
   ```elixir
   # Edit lib/ehs_enforcement/enforcement.ex
   defmodule EhsEnforcement.Enforcement do
     use Ash.Domain

     resources do
       resource EhsEnforcement.Enforcement.Case
       resource EhsEnforcement.Enforcement.MyResource  # Add this
     end
   end
   ```

2. **Restart application:**
   ```bash
   # In IEx
   recompile()

   # Or restart server
   mix phx.server
   ```

---

### Ash Action Not Found

**Symptom:**
```
** (Ash.Error.Invalid.NoSuchAction) No such action :custom_action on MyResource
```

**Solutions:**

1. **Define action in resource:**
   ```elixir
   defmodule MyResource do
     use Ash.Resource

     actions do
       defaults [:read, :destroy]

       create :custom_action do
         accept [:field1, :field2]
       end
     end
   end
   ```

2. **Use correct action name:**
   ```elixir
   # Check available actions
   MyResource.actions()

   # Use correct name
   Ash.create(MyResource, attrs, action: :create)  # Not :custom_action
   ```

---

### Migration Out of Sync with Resource

**Symptom:**
```
** (Ash.Error.Unknown.AshError) Attribute :new_field does not exist
```

**Solution:**

```bash
# Generate missing migrations
mix ash.codegen

# Apply migrations
mix ash.migrate

# Restart server
mix phx.server
```

---

## Migration Issues

### Cannot Rollback Migration

**Symptom:**
```
** (Postgrex.Error) ERROR: cannot drop table because other objects depend on it
```

**Solutions:**

1. **Drop dependent objects first:**
   ```bash
   # Connect to database
   psql -d sertantai_enforcement_dev

   # Find dependencies
   SELECT * FROM information_schema.table_constraints
   WHERE table_name = 'your_table';

   # Drop constraints first, then table
   ```

2. **Reset database (development only):**
   ```bash
   mix ecto.reset
   ```

---

### Duplicate Migration

**Symptom:**
```
** (Postgrex.Error) ERROR: relation already exists
```

**Solutions:**

1. **Check migration file:**
   ```elixir
   # Change create to create_if_not_exists
   def change do
     create_if_not_exists table(:my_table) do
       # ...
     end
   end
   ```

2. **Skip migration:**
   ```bash
   # Mark migration as run without executing
   # WARNING: Only if you know what you're doing
   psql -d sertantai_enforcement_dev
   INSERT INTO schema_migrations VALUES ('20240115120000');
   ```

---

## Phoenix/LiveView Issues

### LiveView Not Updating

**Symptom:**
Changes to LiveView code don't appear in browser.

**Solutions:**

1. **Check LiveView reloader:**
   ```elixir
   # In config/dev.exs, ensure:
   config :ehs_enforcement, EhsEnforcementWeb.Endpoint,
     live_reload: [
       patterns: [
         ~r"lib/ehs_enforcement_web/(controllers|live|components)/.*(ex|heex)$"
       ]
     ]
   ```

2. **Hard refresh browser:**
   ```
   Ctrl + Shift + R (Linux/Windows)
   Cmd + Shift + R (macOS)
   ```

3. **Restart Phoenix:**
   ```bash
   # Stop server (Ctrl+C twice)
   mix phx.server
   ```

---

### WebSocket Connection Failed

**Symptom:**
```
WebSocket connection to 'ws://localhost:4002/live/websocket' failed
```

**Solutions:**

1. **Check endpoint configuration:**
   ```elixir
   # config/dev.exs
   config :ehs_enforcement, EhsEnforcementWeb.Endpoint,
     url: [host: "localhost", port: 4002]
   ```

2. **Clear browser cache**

3. **Check firewall/proxy settings**

---

### Form Doesn't Submit

**Symptom:**
LiveView form submission doesn't work.

**Solutions:**

1. **Check phx-submit attribute:**
   ```heex
   <.form for={@form} phx-submit="save">
     <!-- form fields -->
   </.form>
   ```

2. **Check handle_event:**
   ```elixir
   def handle_event("save", %{"form" => params}, socket) do
     # handler code
     {:noreply, socket}
   end
   ```

3. **Check for JavaScript errors:**
   ```
   Open browser console (F12)
   Look for errors
   ```

---

## Asset Compilation Issues

### Assets Not Loading

**Symptom:**
CSS/JavaScript not loading in browser.

**Solutions:**

1. **Rebuild assets:**
   ```bash
   mix assets.build
   ```

2. **Check asset configuration:**
   ```elixir
   # config/dev.exs
   config :ehs_enforcement, EhsEnforcementWeb.Endpoint,
     watchers: [
       esbuild: {Esbuild, :install_and_run, [:ehs_enforcement, ~w(--sourcemap=inline --watch)]},
       tailwind: {Tailwind, :install_and_run, [:ehs_enforcement, ~w(--watch)]}
     ]
   ```

3. **Reinstall Node dependencies:**
   ```bash
   cd assets
   rm -rf node_modules package-lock.json
   npm install
   cd ..
   ```

---

### Tailwind CSS Not Working

**Symptom:**
Tailwind classes not applying styles.

**Solutions:**

1. **Rebuild Tailwind:**
   ```bash
   mix tailwind.install
   mix tailwind ehs_enforcement
   ```

2. **Check content paths in tailwind.config.js:**
   ```javascript
   module.exports = {
     content: [
       './js/**/*.js',
       '../lib/ehs_enforcement_web/**/*.*ex'
     ],
     // ...
   }
   ```

3. **Purge and rebuild:**
   ```bash
   rm -rf priv/static/assets
   mix assets.deploy
   ```

---

## Testing Issues

### Tests Hanging

**Symptom:**
Test suite hangs indefinitely.

**Solutions:**

1. **Run with --trace to identify:**
   ```bash
   mix test --trace
   ```

2. **Check for infinite loops or deadlocks**

3. **Increase timeout:**
   ```elixir
   @tag timeout: :infinity
   test "long running test" do
     # ...
   end
   ```

---

### Database Not Cleaned Between Tests

**Symptom:**
Tests fail due to leftover data.

**Solutions:**

1. **Ensure SQL Sandbox is enabled:**
   ```elixir
   # test/support/data_case.ex
   setup tags do
     pid = Ecto.Adapters.SQL.Sandbox.start_owner!(EhsEnforcement.Repo, shared: not tags[:async])
     on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
     :ok
   end
   ```

2. **Don't use async for tests with shared state:**
   ```elixir
   # Remove this if tests interact
   use EhsEnforcement.DataCase, async: true
   ```

---

### Ash Query Compilation Errors in Tests

**Symptom:**
```
** (CompileError) undefined variable in filter
```

**Solution:**

```elixir
# Add at top of test file
require Ash.Query
import Ash.Expr
```

---

## Docker Issues

### Container Won't Start

**Symptom:**
```
docker: Error response from daemon: Conflict. The container name "/ehs_postgres_dev" is already in use.
```

**Solutions:**

1. **Remove existing container:**
   ```bash
   docker rm -f ehs_postgres_dev
   ```

2. **Check container status:**
   ```bash
   docker ps -a
   docker logs ehs_postgres_dev
   ```

---

### Volume Permission Issues

**Symptom:**
```
Error: Permission denied
```

**Solutions:**

1. **Fix permissions:**
   ```bash
   sudo chown -R $USER:$USER ~/.docker
   ```

2. **Run with sudo (not recommended):**
   ```bash
   sudo ./scripts/development/ehs-dev.sh
   ```

---

## Performance Issues

### Slow Page Load

**Solutions:**

1. **Check database queries:**
   ```elixir
   # Enable query logging
   config :logger, level: :debug

   # Look for N+1 queries
   # Use preloading
   Case |> Ash.Query.load([:offender, :agency]) |> Ash.read()
   ```

2. **Profile with telemetry:**
   ```bash
   # Check logs for slow queries
   grep "QUERY" log/dev.log | grep "ms"
   ```

3. **Add database indexes**

---

### High Memory Usage

**Solutions:**

1. **Check for memory leaks:**
   ```bash
   # Monitor Observer
   iex -S mix phx.server
   iex> :observer.start()
   ```

2. **Limit query results:**
   ```elixir
   # Use pagination
   Case |> Ash.Query.page(limit: 50) |> Ash.read()
   ```

---

## Integration Issues

### Airtable API Errors

**Symptom:**
```
** (HTTPoison.Error) 401 Unauthorized
```

**Solutions:**

1. **Check API key:**
   ```bash
   echo $AT_UK_E_API_KEY
   # Should return your API key

   # Set if missing
   export AT_UK_E_API_KEY="your_key_here"
   ```

2. **Check rate limits:**
   ```
   Airtable rate limit: 5 requests per second
   Wait and retry
   ```

---

### Scraping Timeouts

**Symptom:**
```
** (HTTPoison.Error) :timeout
```

**Solutions:**

1. **Increase timeout:**
   ```elixir
   # In scraper module
   HTTPoison.get(url, [], timeout: 30_000, recv_timeout: 30_000)
   ```

2. **Check network connection**

3. **Verify website is accessible:**
   ```bash
   curl -I https://www.hse.gov.uk
   ```

---

## Getting Help

### Debugging Steps

1. **Check logs:**
   ```bash
   tail -f log/dev.log
   ```

2. **Use IEx for debugging:**
   ```bash
   iex -S mix phx.server
   ```

3. **Run with verbose output:**
   ```bash
   mix test --trace
   LOG_LEVEL=debug mix phx.server
   ```

### Common Log Locations

- `log/dev.log` - Development logs
- `log/test.log` - Test logs
- `log/prod.log` - Production logs (if configured)

### Useful Commands

```bash
# Check system status
mix phx.server --no-start  # Check for startup errors
docker ps                   # Check Docker containers
pg_isready                  # Check PostgreSQL
lsof -i :4002              # Check port usage

# Clean slate
mix ecto.reset             # Reset database
mix deps.clean --all       # Clean dependencies
rm -rf _build              # Remove build artifacts
```

---

**Still having issues?**
- Review [DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md)
- Check [CLAUDE.md](../CLAUDE.md) for Ash-specific rules
- Review application logs
- Search GitHub issues
- Ask the team

---

**Last Updated:** 2025-10-16
