# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [Removed] - 2025-11-24 - Airtable Integration

The legacy Airtable integration has been completely removed. The project now uses PostgreSQL as the single source of truth, with data populated via web scraping (HSE, EA, SEPA, NRW agencies).

### Removed
- **Airtable API integration modules** (17 files, ~1,500 LOC)
  - `lib/ehs_enforcement/integrations/airtable/*` - All Airtable integration code
  - `lib/ehs_enforcement/sync/airtable_importer.ex` - Airtable sync module

- **Legacy HSE modules** (2 files, ~300 LOC)
  - `lib/ehs_enforcement/agencies/hse/breaches.ex` - Legacy breach processing
  - `lib/ehs_enforcement/agencies/hse/notices.ex` - Legacy notice processing

- **Import scripts** (10 files, ~600 LOC)
  - `scripts/data/airtable_import.sh`
  - `scripts/data/airtable_sync.sh`
  - `scripts/data/clean_and_reimport.exs`
  - `scripts/data/import.exs`
  - `scripts/data/import_1000_cases.exs`
  - `scripts/data/import_1000_notices.exs`
  - `scripts/data/import_1000_records.exs`
  - `scripts/data/test_notice_import.exs`
  - `scripts/data/offender.exs`
  - `scripts/data/update_offender_fields.exs`

- **Database schema changes**
  - Cases: `airtable_id` field removed (Oct 2025, migration 20251022071558)
  - Notices: `airtable_id` field removed (Nov 2025, migration 20251124124617)

- **Configuration**
  - Removed `:airtable_client` config from `config/test.exs`
  - Removed `AT_UK_E_API_KEY` environment variable requirement

### Impact
- ✅ **5 DOS.StringToAtom security warnings eliminated**
- ✅ **~2,400 lines of legacy code removed**
- ✅ **Simplified data architecture** - PostgreSQL is now single source of truth
- ✅ **Reduced dependencies** - No Airtable API dependency

### Migration Notes
- **Cases**: Already migrated from `airtable_id` to `case_reference` (October 2025)
- **Notices**: `airtable_id` column dropped from database
- **No impact on active features**: All Airtable code was legacy/unused
- **Data source**: Web scraping via `EhsEnforcement.Scraping.*` modules
- **UI**: Svelte 5 frontend with Phoenix backend API

### Documentation
- Archived Airtable documentation to `docs-dev/archive/airtable/`
- Updated README.md and CLAUDE.md to reflect PostgreSQL-only architecture
- Removed Airtable references from development setup instructions

### Related
- Session doc: `.claude/sessions/AIRTABLE-REMOVAL-PLAN.md`
- DOS analysis: `.claude/sessions/DOS.md`
- Security fixes: `.claude/sessions/2025-11-23-fix-validation-failures.md`
