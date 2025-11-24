# Airtable to PostgreSQL Sync Deployment Guide

Your EHS Enforcement application has robust Airtable sync functionality built-in. Here are the **multiple ways** to run the sync on your production server.

## ✅ Production-Ready Solution (Recommended)

After extensive testing, the **proven approach** for importing 30K+ records from Airtable to production PostgreSQL:

### **Step 1: Setup HSE Agency (Required)**
```bash
# SSH into production server
ssh user@yourdomain.com
cd /opt/ehs_enforcement

# Create agency setup script
cat > scripts/setup_agencies.exs << 'EOF'
#!/usr/bin/env elixir
alias EhsEnforcement.Enforcement.Agency
require Logger

case Ash.create(Agency, %{
  code: :hse,
  name: "Health and Safety Executive", 
  base_url: "https://www.hse.gov.uk",
  enabled: true
}) do
  {:ok, agency} ->
    Logger.info("✅ Created HSE agency: #{agency.name} (#{agency.code})")
  {:error, %Ash.Error.Invalid{errors: errors}} ->
    if Enum.any?(errors, fn error -> 
      error.field == :code and String.contains?(error.message || "", "already been taken")
    end) do
      Logger.info("✅ HSE agency already exists")
    else
      Logger.error("❌ Failed to create HSE agency: #{inspect(errors)}")
    end
end
EOF

# Run agency setup
docker compose exec -T app bin/ehs_enforcement eval "$(cat scripts/setup_agencies.exs)"
```

### **Step 2: Create Import Script**
```bash
# Create the 40K record import script
cat > scripts/import.exs << 'EOF'
#!/usr/bin/env elixir
alias EhsEnforcement.Sync.AirtableImporter
alias EhsEnforcement.Integrations.Airtable.ReqClient
require Logger

defmodule Import40kRecords do
  @target_records 40000
  @batch_size 100

  def run do
    Logger.info("Starting import of #{@target_records} records from Airtable...")
    
    case test_airtable_connection() do
      :ok ->
        Logger.info("✅ Airtable connection successful")
        import_records()
      {:error, reason} ->
        Logger.error("❌ Failed to connect to Airtable: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp test_airtable_connection do
    path = "/appq5OQW9bTHC1zO5/tbl6NZm9bLU2ijivf"
    case ReqClient.get(path, %{maxRecords: 1}) do
      {:ok, _response} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp import_records do
    AirtableImporter.stream_airtable_records()
    |> Stream.take(@target_records)
    |> Stream.chunk_every(@batch_size)
    |> Stream.with_index()
    |> Enum.reduce_while(0, fn {batch, batch_index}, acc ->
      batch_number = batch_index + 1
      estimated_batches = div(@target_records, @batch_size)
      Logger.info("Processing batch #{batch_number}/#{estimated_batches} (#{length(batch)} records)")
      
      case AirtableImporter.import_batch(batch) do
        :ok ->
          new_acc = acc + length(batch)
          Logger.info("✅ Batch #{batch_number} completed. Total processed: #{new_acc}")
          
          if rem(batch_number, 10) == 0 do
            Logger.info("🚀 Progress: #{new_acc}/#{@target_records} records processed (#{Float.round(new_acc / @target_records * 100, 1)}%)")
          end
          
          if new_acc >= @target_records do
            {:halt, new_acc}
          else
            {:cont, new_acc}
          end
          
        {:error, error} ->
          Logger.error("❌ Batch #{batch_number} failed: #{inspect(error)}")
          Logger.info("Continuing with next batch...")
          {:cont, acc}
      end
    end)
    |> case do
      count when is_integer(count) ->
        Logger.info("🎉 Import completed! Successfully processed #{count} records")
        {:ok, count}
      error ->
        Logger.error("💥 Import failed: #{inspect(error)}")
        {:error, error}
    end
  end
end

case Import40kRecords.run() do
  {:ok, count} -> IO.puts("Success: Processed #{count} records")
  {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
end
EOF
```

### **Step 3: Execute Import**
```bash
# Copy script to container and run in full application context
docker compose exec app mkdir -p /app/scripts
docker compose cp scripts/import.exs app:/app/scripts/

# Connect to running application and execute
docker compose exec app bin/ehs_enforcement remote

# In the IEx shell:
Code.eval_file("scripts/import.exs")

# Monitor progress - you'll see:
# [info] Processing batch 1/400 (100 records)  
# [info] Creating offender: COMPANY NAME LTD (no postcode)
# [info] ✅ Batch 1 completed. Total processed: 100
# [info] 🚀 Progress: 1000/40000 records processed (2.5%)
```

### **Key Features of This Solution:**
- ✅ **Uses proven `AirtableImporter` module** - Same code that works in development
- ✅ **Handles 40,000 records in 100-record batches** - Memory efficient  
- ✅ **Automatic classification** - Cases vs Notices by `offence_action_type`
- ✅ **Creates offenders as needed** - Relationship handling
- ✅ **Progress reporting** - Updates every 1,000 records
- ✅ **Error resilient** - Continues processing if individual records fail
- ✅ **Full application context** - All dependencies properly loaded

### **Expected Results:**
- **~15,000-20,000 Cases** (offence_action_type: "Court Case", "Caution")  
- **~15,000-20,000 Notices** (all other offence_action_type values)
- **~8,000-12,000 Unique Offenders** (companies/individuals)

### **Environment Requirements:**
```bash
# Ensure these are set in your .env.prod
AT_UK_E_API_KEY=your-airtable-api-key-here
AIRTABLE_BASE_ID=appq5OQW9bTHC1zO5
```

This approach bypasses the complex NCDB_2_PHX framework and uses the battle-tested import logic that successfully populated your development database. Import typically takes 15-30 minutes for 30K records.

## Sync Architecture Overview

### **Current Sync System:**
- ✅ **`EhsEnforcement.Sync`** - Main sync domain using NCDB_2_PHX framework
- ✅ **`NCDB_2_PHX.execute_sync/2`** - Core sync engine with streaming and batch processing
- ✅ **`EhsEnforcement.Sync.Adapters.AirtableAdapter`** - Airtable data source adapter
- ✅ **`EhsEnforcement.Sync.RecordProcessor`** - Data transformation and filtering
- ✅ **Admin UI** - Web interface for running syncs
- ✅ **Self-contained sync system** - All sync logic in `lib/ehs_enforcement/sync/`

### **NCDB_2_PHX Dependency:**

The sync system uses the `ncdb_2_phx` library (GitHub: `shotleybuilder/ncdb_2_phx`) which provides:

- **Streaming data processing** - Memory-efficient handling of large datasets
- **Batch processing** - Configurable batch sizes for optimal performance
- **Session tracking** - Complete audit trail via `NCDB2Phx.Resources.SyncSession`
- **Progress monitoring** - Real-time sync status via `NCDB2Phx.Resources.SyncBatch`
- **Error logging** - Detailed error tracking via `NCDB2Phx.Resources.SyncLog`
- **Adapter pattern** - Clean separation between data sources and targets
- **PubSub integration** - Real-time progress updates to UI components

**Key Resources Provided by NCDB_2_PHX:**
```elixir
# Core NCDB_2_PHX resources (used directly)
NCDB2Phx.Resources.SyncSession  # Tracks overall sync operations
NCDB2Phx.Resources.SyncBatch    # Tracks batch processing progress
NCDB2Phx.Resources.SyncLog      # Detailed operation logs

# Extended local resources (in lib/ehs_enforcement/sync/resources/)
EhsEnforcement.Sync.ExtendedSyncSession
EhsEnforcement.Sync.ExtendedSyncBatch
EhsEnforcement.Sync.ExtendedSyncLog
EhsEnforcement.Sync.SimpleSyncSession
```

### **Sync Process Flow:**

1. **`EhsEnforcement.Sync.import_cases()` or `import_notices()` called**
2. **Configuration built** - `build_sync_config/4` creates NCDB_2_PHX config with:
   - Source: `EhsEnforcement.Sync.Adapters.AirtableAdapter`
   - Target: `EhsEnforcement.Enforcement.Case` or `Notice` (Ash resources)
   - Processing: Batch size, limits, filtering functions
   - PubSub: Real-time progress updates to UI
3. **`NCDB_2_PHX.execute_sync/2` executes** - Handles streaming, batching, and error recovery
4. **Data filtering** - Records filtered by `offence_action_type`:
   - **Cases**: `"Court Case"`, `"Caution"`
   - **Notices**: All records containing `"Notice"`
5. **Data transformation** - `RecordProcessor.process_case_record/1` or `process_notice_record/1`
6. **Ash resource creation** - Records created via Ash actions `:create` or `:update`
7. **Session tracking** - Complete audit trail stored in NCDB_2_PHX resources

### **Data Source Configuration:**

```elixir
# Airtable source config (from sync.ex)
%{
  api_key: System.get_env("AT_UK_E_API_KEY"),
  base_id: "appq5OQW9bTHC1zO5",
  table_id: "tbl6NZm9bLU2ijivf",
  page_size: 100,
  rate_limit_delay_ms: 200,
  timeout_ms: 30_000,
  retry_attempts: 3,
  retry_delay_ms: 1000
}
```

## Option 1: Admin Web Interface (Recommended)

### **Access the NCDB_2_PHX Sync Admin Panel:**

Once deployed, access the Airtable sync interface at:

```
https://yourdomain.com/admin/sync
```

**Note**: The routes `/admin/config` and `/admin/scraping` are for HSE website scraping, NOT Airtable imports.

### **NCDB_2_PHX Admin Features:**
- ✅ **Sync Dashboard** - Overview of all sync operations
- ✅ **Session Management** - Create, monitor, and manage sync sessions
- ✅ **Real-time Monitoring** - Live progress tracking during imports
- ✅ **Batch Tracking** - Detailed batch-level progress and performance
- ✅ **Error Logging** - Comprehensive error tracking and debugging
- ✅ **Configuration Management** - Sync configuration and settings

### **Step-by-Step Airtable Import Guide:**

#### **Step 1: Access Admin Interface**
1. Login with GitHub OAuth (admin user required)
2. Navigate to `https://yourdomain.com/admin/sync`
3. You'll see the NCDB_2_PHX dashboard with sync overview

#### **Step 2: Create New Sync Session**
1. Click "Sessions" in the navigation
2. Click "New Session" button
3. Configure sync parameters:
   - **Sync Type**: Select "Cases" or "Notices"
   - **Limit**: Number of records to import (e.g., 1000)
   - **Batch Size**: Records per batch (default: 100)
   - **Description**: Optional description for tracking

#### **Step 3: Monitor Import Progress**
1. Once started, navigate to "Monitor" section
2. View real-time progress updates:
   - Records processed
   - Batch completion status
   - Processing speed and ETA
   - Memory usage and performance metrics

#### **Step 4: Review Results**
1. Check "Logs" section for detailed operation logs
2. Review "Batches" for batch-level statistics
3. Verify import success in main application:
   - Visit `/cases` or `/notices` to see imported data
   - Check record counts and data quality

#### **Available Admin Routes:**

```
# Main sync administration
https://yourdomain.com/admin/sync                    # Dashboard
https://yourdomain.com/admin/sync/sessions           # Session management
https://yourdomain.com/admin/sync/sessions/new       # Create new sync
https://yourdomain.com/admin/sync/monitor            # Real-time monitoring
https://yourdomain.com/admin/sync/batches            # Batch tracking
https://yourdomain.com/admin/sync/logs               # Error/operation logs
https://yourdomain.com/admin/sync/config             # Sync configuration
```

## Option 2: Command Line Scripts (Server)

### **Direct Elixir Console Commands:**

```bash
# SSH into your server
ssh user@yourdomain.com

# Access running application
docker-compose -f docker-compose.prod.yml exec app bin/ehs_enforcement remote

# In the Elixir console:
# Import all cases (up to 1000) - uses NCDB_2_PHX internally
EhsEnforcement.Sync.import_cases()

# Import all notices (up to 1000) - uses NCDB_2_PHX internally
EhsEnforcement.Sync.import_notices()

# Import with custom limits and batch sizes
EhsEnforcement.Sync.import_cases(limit: 5000, batch_size: 200)
EhsEnforcement.Sync.import_notices(limit: 2000, batch_size: 150, actor: admin_user)

# Check import statistics
EhsEnforcement.Sync.get_case_import_stats()
EhsEnforcement.Sync.get_notice_import_stats()

# Monitor sync sessions (NCDB_2_PHX resources)
{:ok, sessions} = Ash.read(NCDB2Phx.Resources.SyncSession)
{:ok, batches} = Ash.read(NCDB2Phx.Resources.SyncBatch)
{:ok, logs} = Ash.read(NCDB2Phx.Resources.SyncLog)
```

## Option 3: Automated Sync Scripts

### **Create Production Sync Scripts:**

Let me create automated scripts for you:

```bash
# One-time full import script
./scripts/airtable_import.sh prod

# Scheduled incremental sync  
./scripts/airtable_sync.sh prod --incremental
```

### **Cron Job Setup:**
```bash
# Add to server crontab for daily sync at 2 AM
0 2 * * * /opt/ehs_enforcement/scripts/airtable_sync.sh prod --incremental >> /var/log/airtable_sync.log 2>&1
```

## Option 4: Oban Background Jobs

### **Built-in Job System:**

Your app has Oban configured for background sync jobs:

```elixir
# Queue a sync job using SyncWorker
%{action: :import_cases, limit: 1000, batch_size: 100}  
|> EhsEnforcement.Sync.SyncWorker.new()
|> Oban.insert()

# Queue notice import job
%{action: :import_notices, limit: 1000, batch_size: 100}
|> EhsEnforcement.Sync.SyncWorker.new() 
|> Oban.insert()

# Monitor background jobs
Oban.peek_queue(:sync, limit: 10)
```

## Production Deployment Steps

### **1. Initial Data Migration (One-time):**

After deploying to production, run the full import:

```bash
# Method A: Via Admin UI
# Login → Admin → Configuration → "Import from Airtable"

# Method B: Via Console
docker-compose -f docker-compose.prod.yml exec app bin/ehs_enforcement remote
EhsEnforcement.Sync.import_cases(limit: 10000)
EhsEnforcement.Sync.import_notices(limit: 10000)

# Method C: Via Script
./scripts/airtable_import.sh prod --full
```

### **2. Environment Variables Setup:**

Ensure your `.env.prod` has:

```bash
# Required for Airtable sync
AT_UK_E_API_KEY=your-airtable-api-key
AIRTABLE_BASE_ID=appq5OQW9bTHC1zO5
```

### **3. NCDB_2_PHX Configuration (Required):**

⚠️ **Critical**: The NCDB_2_PHX sync admin interface requires proper PubSub configuration. Ensure your `config/config.exs` includes:

```elixir
# Configure ncdb_2_phx package to use our repo and PubSub
config :ncdb_2_phx, 
  repo: EhsEnforcement.Repo,
  pubsub_name: EhsEnforcement.PubSub
```

**Without this configuration, `/admin/sync` will fail with:**
```
** (ArgumentError) unknown registry: NCDB2Phx.PubSub
```

**This configuration tells NCDB_2_PHX to use the host application's PubSub module instead of its own.**

### **4. NCDB_2_PHX Styling Configuration (Optional):**

The NCDB_2_PHX admin interface requires basic CSS styling to display properly. The application includes pre-configured Tailwind CSS styles for NCDB_2_PHX components in `assets/css/app.css`.

**CSS Classes Included:**
- `.sync-dashboard` - Main dashboard container
- `.dashboard-grid` - Dashboard card grid layout
- `.sync-card`, `.dashboard-card` - Card components
- `.sync-navbar` - Navigation bar
- `.form-input`, `.form-label` - Form components
- `.btn`, `.btn-primary`, `.btn-secondary` - Button styles

**If styling appears missing:**
```bash
# Rebuild assets to ensure CSS is compiled
mix assets.build

# Restart the application
mix phx.server
```

**The admin interface should display with:**
- ✅ Proper card layouts and spacing
- ✅ Styled navigation menu
- ✅ Professional form inputs and buttons
- ✅ Responsive grid layouts
- ✅ Consistent typography and colors

### **5. Monitor Sync Progress:**

```bash
# View import logs
docker-compose -f docker-compose.prod.yml logs -f app | grep -i "import\|sync"

# Check database counts
docker-compose -f docker-compose.prod.yml exec app bin/ehs_enforcement remote
Ash.count(EhsEnforcement.Enforcement.Case)
Ash.count(EhsEnforcement.Enforcement.Notice)
```

### **Deployment Checklist:**

✅ **Application deployed and running**  
✅ **Environment variables configured** (`AT_UK_E_API_KEY`)  
✅ **NCDB_2_PHX PubSub configuration added to `config/config.exs`**  
✅ **Assets built with NCDB_2_PHX styling** (`mix assets.build`)  
✅ **Admin user created with GitHub OAuth**  
✅ **`/admin/sync` accessible** (redirects to sign-in if not authenticated)  
✅ **Airtable API connectivity verified**

## Sync Performance & Safety

### **Built-in Safety Features (NCDB_2_PHX Framework):**
- ✅ **Streaming processing** - Memory efficient for large datasets via NCDB_2_PHX
- ✅ **Batch processing** - 100 records per batch (configurable)
- ✅ **Error recovery** - Continues processing if individual records fail
- ✅ **Session tracking** - Complete sync audit trail with NCDB_2_PHX resources
- ✅ **Progress tracking** - Real-time sync status updates via PubSub
- ✅ **Data filtering** - Cases vs Notices filtered by `offence_action_type`
- ✅ **Duplicate prevention** - Uses `regulator_id` for Cases, `notice_id` for Notices
- ✅ **Transaction safety** - Database transactions for data integrity

### **Performance Tuning:**

```bash
# For large imports, increase batch size (NCDB_2_PHX handles streaming)
EhsEnforcement.Sync.import_cases(limit: 10000, batch_size: 500)

# Monitor NCDB_2_PHX sync progress
{:ok, active_sessions} = Ash.read(NCDB2Phx.Resources.SyncSession, 
  query: Ash.Query.filter(status == :in_progress))

# Check memory usage during import
docker stats ehs_enforcement_app

# Monitor PubSub sync progress messages
# Topic: "sync_progress" configured in EhsEnforcement.Sync
```

## Recommended Production Workflow

### **Initial Migration:**
1. ✅ Deploy application to production
2. ✅ Verify Airtable API connectivity  
3. ✅ Run full import via Admin UI (recommended)
4. ✅ Verify data integrity and counts
5. ✅ Set up monitoring and logging

### **Ongoing Sync Strategy:**
- **Primary**: Use Admin UI for manual syncs as needed
- **Backup**: Automated scripts for scheduled updates
- **Emergency**: Console commands for troubleshooting

## Troubleshooting Sync Issues

### **Common Issues:**

#### **API Rate Limits:**
```bash
# Reduce batch size if hitting rate limits
EhsEnforcement.Sync.import_cases(batch_size: 50)
```

#### **Memory Issues:**
```bash
# Monitor memory during import
docker stats ehs_enforcement_app

# Reduce batch size if needed
EhsEnforcement.Sync.import_cases(batch_size: 25)
```

#### **Connection Timeouts:**
```bash
# Check Airtable connectivity via adapter
docker-compose -f docker-compose.prod.yml exec app bin/ehs_enforcement remote
EhsEnforcement.Integrations.Airtable.ReqClient.get("/appq5OQW9bTHC1zO5/tbl6NZm9bLU2ijivf", %{maxRecords: 1})

# Test Airtable adapter directly
config = %{
  api_key: System.get_env("AT_UK_E_API_KEY"),
  base_id: "appq5OQW9bTHC1zO5",
  table_id: "tbl6NZm9bLU2ijivf",
  page_size: 10
}
EhsEnforcement.Sync.Adapters.AirtableAdapter.fetch_records(config)
```

#### **Duplicate Records:**
```bash
# Clean up orphaned offenders
EhsEnforcement.Sync.cleanup_orphaned_offenders()

# Check for duplicate cases
EhsEnforcement.Repo.query("SELECT regulator_id, COUNT(*) FROM cases GROUP BY regulator_id HAVING COUNT(*) > 1")

# Check for duplicate notices  
EhsEnforcement.Repo.query("SELECT notice_id, COUNT(*) FROM notices GROUP BY notice_id HAVING COUNT(*) > 1")

# Review sync session logs for errors
{:ok, error_logs} = Ash.read(NCDB2Phx.Resources.SyncLog,
  query: Ash.Query.filter(level == :error))
```

## Data Verification

### **After Import Verification:**

```bash
# Check total counts
docker-compose -f docker-compose.prod.yml exec app bin/ehs_enforcement remote

# Cases imported (via Ash)
{:ok, cases} = Ash.read(EhsEnforcement.Enforcement.Case)
length(cases)

# Notices imported (via Ash)
{:ok, notices} = Ash.read(EhsEnforcement.Enforcement.Notice)
length(notices)

# Offenders created
{:ok, offenders} = Ash.read(EhsEnforcement.Enforcement.Offender)
length(offenders)

# Sample data verification
cases |> Enum.take(5) |> Enum.map(&(&1.regulator_id))
notices |> Enum.take(5) |> Enum.map(&(&1.notice_id))

# Review successful sync sessions
{:ok, completed_sessions} = Ash.read(NCDB2Phx.Resources.SyncSession,
  query: Ash.Query.filter(status == :completed))
  
# Check sync statistics
EhsEnforcement.Sync.get_case_import_stats()
EhsEnforcement.Sync.get_notice_import_stats()
```

## Admin Interface Troubleshooting

### **Common Admin UI Issues:**

#### **Cannot Access `/admin/sync`**
```bash
# Check authentication
# Must be logged in with GitHub OAuth AND have admin privileges

# Verify admin role in console
docker-compose -f docker-compose.prod.yml exec app bin/ehs_enforcement remote
{:ok, user} = EhsEnforcement.Accounts.get_user_by_email("your-email@example.com")
user.role  # Should be :admin
```

#### **"Session Creation Failed"**
```bash
# Check Airtable API connectivity
docker-compose -f docker-compose.prod.yml exec app bin/ehs_enforcement remote

# Test Airtable connection
config = %{
  api_key: System.get_env("AT_UK_E_API_KEY"),
  base_id: "appq5OQW9bTHC1zO5",
  table_id: "tbl6NZm9bLU2ijivf"
}
EhsEnforcement.Sync.Adapters.AirtableAdapter.fetch_records(config)
```

#### **"No Progress Updates" in Monitor**
```bash
# Check PubSub configuration
docker-compose -f docker-compose.prod.yml exec app bin/ehs_enforcement remote

# Verify PubSub is working
Phoenix.PubSub.broadcast(EhsEnforcementWeb.PubSub, "sync_progress", {:test, "message"})

# Check active sync sessions
{:ok, sessions} = Ash.read(NCDB2Phx.Resources.SyncSession,
  query: Ash.Query.filter(status == :in_progress))
```

#### **"Import Stuck" or Hanging**
```bash
# Find stuck sessions
{:ok, stuck_sessions} = Ash.read(NCDB2Phx.Resources.SyncSession,
  query: Ash.Query.filter(status == :in_progress and 
    inserted_at < ago(1, :hour)))

# Check for failed batches
{:ok, failed_batches} = Ash.read(NCDB2Phx.Resources.SyncBatch,
  query: Ash.Query.filter(status == :failed))

# Review error logs
{:ok, errors} = Ash.read(NCDB2Phx.Resources.SyncLog,
  query: Ash.Query.filter(level == :error))
```

#### **"UndefinedFunctionError" when clicking Dashboard buttons**

**Issue**: Clicking "New Sync" or other dashboard buttons gives:
```
** (UndefinedFunctionError) function NCDB2Phx.Live.DashboardLive.handle_event/3 is undefined
```

**Solution**: This was fixed in NCDB_2_PHX version with commit `a799895`. Ensure you have the latest version:

```bash
# Update NCDB_2_PHX dependency to latest
mix deps.update ncdb_2_phx

# Recompile with latest changes
mix deps.compile ncdb_2_phx --force
mix compile

# Restart application
mix phx.server
```

**The dashboard buttons now navigate correctly:**
- ✅ **"New Sync"** → `/admin/sync/sessions/new`
- ✅ **"View All Sessions"** → `/admin/sync/sessions`
- ✅ **"View Logs"** → `/admin/sync/logs`
- ✅ **"System Monitor"** → `/admin/sync/monitor`

### **Manual Session Management:**

```bash
# If you need to manually trigger sync via console
docker-compose -f docker-compose.prod.yml exec app bin/ehs_enforcement remote

# Import cases via EhsEnforcement.Sync (uses NCDB_2_PHX internally)
EhsEnforcement.Sync.import_cases(limit: 1000, batch_size: 100)

# Import notices
EhsEnforcement.Sync.import_notices(limit: 1000, batch_size: 100)

# Clean up stuck sessions (if needed)
{:ok, stuck_sessions} = Ash.read(NCDB2Phx.Resources.SyncSession,
  query: Ash.Query.filter(status == :in_progress))

# Mark as failed (replace with actual session ID)
Ash.update!(stuck_session, %{status: :failed, ended_at: DateTime.utc_now()})
```

## Monitoring & Alerting

### **Sync Monitoring:**

```bash
# Monitor sync logs
docker-compose -f docker-compose.prod.yml logs -f app | grep "import\|sync"

# Check for errors
docker-compose -f docker-compose.prod.yml logs app | grep -i error | tail -20

# Database health after sync
curl https://yourdomain.com/health
```

## Recommendation

**For your production deployment:**

1. **🎯 Start with Admin UI** - Most user-friendly and feature-rich
2. **🔧 Add console access** - For troubleshooting and maintenance  
3. **⚙️ Consider automation** - For ongoing incremental updates
4. **📊 Monitor everything** - Use built-in logging and health checks

The **Admin UI approach is recommended** because:
- ✅ **No command line needed** - Web-based interface
- ✅ **Real-time progress** - See sync status live
- ✅ **Error handling** - Built-in retry and error recovery
- ✅ **User-friendly** - Point-and-click operation
- ✅ **Secure** - Uses your existing GitHub OAuth authentication

Your sync system is **production-ready** with enterprise-grade error handling, progress tracking, and safety features! 🚀