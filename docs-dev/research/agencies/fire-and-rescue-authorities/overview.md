# Fire and Rescue Authorities Enforcement Register

## Overview

The National Fire Chiefs Council (NFCC) maintains a national enforcement register containing statutory notices served by Fire and Rescue Authorities (FRAs) under the **Regulatory Reform (Fire Safety) Order 2005** (as amended).

**Register URL:** https://nfcc.org.uk/our-services/enforcement-register/  
**Usage Guide:** https://nfcc.org.uk/using-the-enforcement-register/

---

## Data Source Analysis

### What Data Is Available

The register contains three types of enforcement notices:

| Notice Type | Description |
|-------------|-------------|
| **Alterations Notice** | Requires premises to notify FRA before making changes that could affect fire safety |
| **Enforcement Notice** | Requires specific fire safety improvements within a set timeframe |
| **Prohibition Notice** | Prohibits or restricts the use of premises until fire safety issues are resolved |

### Data Fields

| Field | Description | Example |
|-------|-------------|---------|
| UPRN | Unique Property Reference Number | 10023349829 |
| FRS | Fire and Rescue Service (Authority) | Avon Fire and Rescue |
| Issue Date | Date notice was issued | 2024-03-15 |
| Notice Type | PROHIBITION, ENFORCEMENT, ALTERATIONS | PROHIBITION |
| Premises Type | Type of business/building | LICENSED PREMISES, SHOP, FACTORY |
| Status | Current status of notice | IN FORCE, COMPLIED |
| Address | Full premises address | 123 High Street, Bristol BS1 2AA |
| Notice Served On | Responsible party name | ABC Company Ltd |
| Date Complied With | Date notice requirements were met | 2024-05-20 |
| Reasons | Detailed description of violations | Fire exits blocked, no fire alarm |
| Additional Information | Specific restrictions/conditions | Use prohibited until X is addressed |

### Data Lifecycle

- **Publication delay:** Notices added **3 weeks after issue date** (to allow for appeals)
- **Retention period:** Notices remain for **3 years** unless:
  - Still in force
  - Deemed not complied with
  - Withdrawn by serving authority

---

## Data Access Options

### Option 1: Web Scraping (Recommended)

**Implementation Complexity:** Medium  
**Data Freshness:** Near real-time (daily scraping possible)  
**Reliability:** High (WordPress-based, stable structure)

The register appears to be a WordPress site using a table plugin (likely wpDataTables or similar). The data is server-rendered HTML, making it straightforward to scrape.

**Technical Details:**
- WordPress site on nfcc.org.uk domain
- Table data rendered server-side
- Sorting/filtering via JavaScript (DataTables library)
- No CAPTCHA or anti-bot measures observed
- Download/export buttons available (but format unclear)

**Scraping Strategy:**
1. Parse HTML table rows from main register page
2. Handle pagination (if applicable)
3. Extract all table columns
4. Map to database schema (see below)

**Sample Request Pattern:**
```
GET https://nfcc.org.uk/our-services/enforcement-register/
```

### Option 2: Manual Download + Import

**Implementation Complexity:** Low  
**Data Freshness:** Manual (periodic)  
**Reliability:** Depends on manual process

The site offers "print, download or copy" buttons. Testing is required to determine:
- Available export formats (CSV, Excel, PDF?)
- Whether full dataset or filtered view is exported
- Whether pagination affects export

This could serve as a fallback or validation method.

### Option 3: API Access (NOT Available)

**Status:** No public API exists

Research confirmed:
- No API endpoints documented
- No Open Data portal listing
- No data.gov.uk dataset found
- Crown Premises Fire Safety Inspectorate (separate register) also has no API

---

## Comparison with Existing Data Sources

| Source | Data Type | Access Method | API Available | Notes |
|--------|-----------|---------------|---------------|-------|
| **HSE** | Cases & Notices | Web scraping | No | Currently implemented |
| **EA** | Cases & Notices | API + scraping | Partial | Public Register API |
| **NFCC (FRA)** | Notices only | Web scraping | No | Fire safety notices |
| **SEPA** | Cases | TBD | Unknown | Scotland |
| **NRW** | Cases | TBD | Unknown | Wales |

---

## Database Schema Mapping

The NFCC data maps well to the existing `Notice` resource:

| NFCC Field | Existing Field | Notes |
|------------|----------------|-------|
| UPRN | *(new field needed)* | Property reference, useful for deduplication |
| FRS | agency_id | Need new Agency record per FRA |
| Issue Date | notice_date | Direct mapping |
| Notice Type | offence_action_type | Map: PROHIBITION, ENFORCEMENT, ALTERATIONS |
| Premises Type | *(new field or enrichment)* | Building classification |
| Status | *(new field needed)* | IN FORCE, COMPLIED, WITHDRAWN |
| Address | offender.address | Via Offender relationship |
| Notice Served On | offender.name | Via Offender relationship |
| Date Complied With | compliance_date | Direct mapping |
| Reasons | notice_body | Direct mapping |
| Additional Information | offence_breaches | Or new field |

### Proposed Schema Additions

```elixir
# In Notice resource - new attributes needed:
attribute(:uprn, :string, description: "Unique Property Reference Number")
attribute(:notice_status, :string, description: "IN_FORCE, COMPLIED, WITHDRAWN")
attribute(:premises_type, :string, description: "Building/business type classification")
```

### Agency Records Needed

Each Fire and Rescue Service needs an Agency record. There are approximately 44 FRAs in England and 3 in Wales (47 total).

Example FRS names from register:
- Avon Fire and Rescue Service
- Bedfordshire Fire and Rescue Service
- Buckinghamshire Fire and Rescue Service
- etc.

---

## Implementation Recommendations

### Phase 1: Discovery & Validation

1. **Test export functionality** - Determine if download buttons provide usable CSV/Excel
2. **Inspect HTML structure** - Identify table selectors, pagination patterns
3. **Sample scrape** - Pull 10-20 records to validate field mapping
4. **Verify update frequency** - Confirm 3-week delay mentioned in documentation

### Phase 2: Scraper Development

Follow existing patterns from HSE scraper:

```elixir
# Proposed module structure
defmodule EhsEnforcement.Scraping.Fra.NoticeScraper do
  @moduledoc """
  Scrapes fire safety enforcement notices from the NFCC register.
  """
  
  # Similar pattern to HSE scrapers
  def scrape_notices(opts \\ []) do
    # 1. Fetch register page(s)
    # 2. Parse HTML table
    # 3. Transform to Notice schema
    # 4. Return {:ok, [notices]} or {:error, reason}
  end
end
```

### Phase 3: Data Integration

1. Create Agency seed data for 47 FRAs (code: `:fra_xxx` pattern)
2. Add UPRN field to Notice schema (migration required)
3. Add notice_status and premises_type fields
4. Implement scraper following HSE patterns
5. Add scheduled Oban job for weekly updates

---

## Legal & Compliance Considerations

### Data Status
- **Public data:** Explicitly published for public access
- **Legal basis:** Environment and Safety Information Act 1988 requires transparency
- **No registration required:** No login or API key needed
- **Terms of use:** Not explicitly stated, but public interest data

### Scraping Compliance
- Respect robots.txt (if present)
- Implement rate limiting (1 request per 2-3 seconds)
- Include proper User-Agent header
- Cache responses to minimize requests

### GDPR Considerations
- Data primarily concerns business premises (not individuals)
- "Notice Served On" may be individual names for sole traders
- Same handling as HSE offender names
- Legitimate interest basis: public safety information

---

## Effort Estimate

| Task | Estimate |
|------|----------|
| HTML structure analysis | 2-4 hours |
| Scraper implementation | 1-2 days |
| Schema migration | 2-4 hours |
| Agency seed data | 2-4 hours |
| Testing & validation | 1 day |
| Scheduled job setup | 2-4 hours |
| **Total** | **3-5 days** |

---

## Next Steps

1. [ ] Manual inspection of register HTML structure (developer tools)
2. [ ] Test download button - what format is exported?
3. [ ] Count total records currently in register
4. [ ] Create spike to scrape single page
5. [ ] Decision: Proceed with implementation or deprioritize

---

## References

- [NFCC Enforcement Register](https://nfcc.org.uk/our-services/enforcement-register/)
- [Using the Enforcement Register](https://nfcc.org.uk/using-the-enforcement-register/)
- [Regulatory Reform (Fire Safety) Order 2005](https://www.legislation.gov.uk/uksi/2005/1541)
- [Crown Premises Fire Safety Inspectorate (separate register)](https://www.gov.uk/government/publications/crown-premises-fire-safety-inspectorate-enforcement-notices)
- [GOV.UK Enforcement Guidance](https://www.gov.uk/government/publications/regulatory-reform-fire-safety-order-2005-guidance-note-enforcement)
