# Airtable Import Workflow for Development

This guide explains how to import production data from Airtable into your local development database using the Elixir interactive shell (IEx).

## Prerequisites

- Airtable API key set in environment variable: `AT_UK_E_API_KEY`
- Local PostgreSQL database running
- Mix dependencies installed

## Step-by-Step Terminal Workflow

### 1. Start IEx with Mix

```bash
iex -S mix
```

### 2. Create the HSE Agency (Required First Time)

The import requires the HSE agency to exist in the database. In IEx:

```elixir
# Create the HSE agency
EhsEnforcement.Enforcement.create_agency(%{
  code: :hse, 
  name: "Health and Safety Executive", 
  enabled: true, 
  base_url: "https://www.hse.gov.uk"
})
```

### 3. Import Data from Airtable

You have two options:

#### Option A: Import All Data (Full Sync)
```elixir
# Import all records from Airtable
EhsEnforcement.Sync.AirtableImporter.import_all_data()
```

#### Option B: Import Specific Number of Records
```elixir
# Import first 1000 records
alias EhsEnforcement.Sync.AirtableImporter

AirtableImporter.stream_airtable_records()
|> Stream.take(1000)
|> Stream.chunk_every(100)
|> Enum.each(&AirtableImporter.import_batch/1)
```

### 4. Verify the Import

Check how many records were imported:

```elixir
# Count cases
EhsEnforcement.Enforcement.count_cases!()

# Count offenders  
EhsEnforcement.Enforcement.count_offenders!()

# List some cases to verify
EhsEnforcement.Enforcement.list_cases!(limit: 10)
```

## Using the Import Script

Alternatively, you can use the provided script:

```bash
# Run the import script (imports 1000 records)
mix run scripts/import_1000_records.exs
```

## Troubleshooting

### Common Issues

1. **"Agency not found: hse" errors**
   - Solution: Create the HSE agency first (Step 2)

2. **API Key errors**
   - Solution: Ensure `AT_UK_E_API_KEY` environment variable is set
   ```bash
   export AT_UK_E_API_KEY="your-api-key-here"
   ```

3. **Database connection errors**
   - Solution: Ensure PostgreSQL is running
   ```bash
   sudo systemctl status postgresql
   ```

### Checking Import Progress

The import will log progress messages:
- `Processing batch X/Y` - Shows batch progress
- `Importing batch of N records` - Shows records per batch
- Error messages for failed records

### Reset and Retry

If you need to start over:

```elixir
# In IEx - Delete all imported data
alias EhsEnforcement.Repo
import Ecto.Query

# Delete all cases
Repo.delete_all(from c in "cases")

# Delete all offenders
Repo.delete_all(from o in "offenders")

# Keep the agency, or delete if needed
# Repo.delete_all(from a in "agencies")
```

## Understanding the Import

- **Batch Size**: 100 records per Airtable API call
- **Data Types**: Cases and Notices (notices are logged but not yet imported)
- **Relationships**: Creates offenders automatically, links cases to offenders and agency
- **Deduplication**: Offenders are matched by name and postcode

## CRITICAL ISSUE: Record Classification Bug

**❌ Current Problem**: The import logic incorrectly classifies ALL records as cases because:
1. Both cases AND notices in Airtable have `regulator_id` fields
2. Current logic: `regulator_id` → case, `notice_id` → notice
3. Result: All 1000 records imported as cases, 0 notices

**✅ Correct Classification Logic**:
- **Cases**: Records where `offence_action_type` = "Court Case" OR "Caution" 
- **Notices**: All other records (Improvement Notice, Prohibition Notice, etc.)
- Both record types have `regulator_id` fields in production

**Fix Required**: Update `AirtableImporter.partition_records/1` to use `offence_action_type` field instead of presence of `regulator_id`/`notice_id` fields.

## Performance Notes

- Importing 1000 records takes approximately 2-3 minutes
- Each batch includes rate limiting to respect Airtable's API limits
- Failed records are logged but don't stop the import process