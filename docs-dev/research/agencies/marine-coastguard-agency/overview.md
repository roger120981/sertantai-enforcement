# Maritime and Coastguard Agency (MCA) Enforcement Data

## Overview

The Maritime and Coastguard Agency (MCA) publishes enforcement data covering:
1. **Prosecutions** - Court cases against vessel owners, companies, masters and officers
2. **Detentions** - Vessels detained for non-compliance (published via Paris MOU)

**Main Collection:** https://www.gov.uk/government/collections/prosecutions-and-detentions-mca-enforcement-policy-and-information

---

## Data Source Analysis

### Prosecutions Data

Annual prosecution reports have been published since 2010. The reports are published on GOV.UK in **HTML format** (recent years) or **PDF format** (older years).

#### Available Years

| Year | Format | URL Pattern |
|------|--------|-------------|
| 2025 | HTML | `/government/publications/regulatory-compliance-investigations-team-prosecutions-2025` |
| 2024 | HTML | `/government/publications/mca-enforcement-unit-prosecutions-2024/prosecutions-report-2024` |
| 2023 | HTML | `/government/publications/mca-enforcement-unit-prosecutions-2023/prosecutions-report-2023` |
| 2022 | HTML/PDF | `/government/publications/mca-enforcement-unit-prosecutions-2022` |
| 2021-2015 | PDF | `/government/publications/mca-enforcement-unit-prosecutions-YYYY` |
| 2014-2010 | PDF | `/government/publications/mca-enforcement-unit-prosecutions-YYYY` |

Example PDF URL (2015):
```
https://assets.publishing.service.gov.uk/media/5a8064e5ed915d74e33fa2cc/Final_Compiled_report_2015.pdf
```

#### Data Fields Per Prosecution Record

Each prosecution entry contains:

| Field | Description | Format |
|-------|-------------|--------|
| Defendant | Individual name, company, or vessel owner | Text, sometimes with age/location |
| Date of Hearing | Court appearance date | DD Month YYYY |
| Court | Name of court | e.g., "Portsmouth Crown Court" |
| Offence | Charge description with legislation reference | Text with Act/Regulation citation |
| Details | Full narrative of incident | Multi-paragraph text |
| Penalty | Sentencing breakdown | See below |

#### Penalty Structure

Penalties typically include multiple components:
- **Fine:** £ amount
- **Costs:** £ amount (prosecution costs)
- **Victim Surcharge:** £ amount
- **Custodial Sentence:** Weeks/months, often suspended
- **Community Service:** Hours of unpaid work

Example: "£20,000 in prosecution costs, 18 weeks in prison suspended for 12 months, and must complete 150 hours of unpaid work."

#### Legislation Citations

Charges reference specific legislation:
- Merchant Shipping Act 1995 (various sections)
- Merchant Shipping (Distress Signals and Prevention of Collisions) Regulations 1996
- International maritime conventions
- Other merchant shipping regulations

#### Volume

Approximately **5-10 prosecutions per year** (small dataset compared to HSE/EA).

---

### Detentions Data

Vessel detentions are NOT published by the MCA directly. They are maintained in the **Paris MOU database**.

#### Paris MOU Database

**Website:** https://parismou.org/  
**Current Detentions:** https://parismou.org/Inspection-Database/current-detentions

The Paris MOU (Memorandum of Understanding on Port State Control) maintains detention records for the Paris MOU region (European waters).

#### THETIS Database (EMSA)

**Website:** https://portal.emsa.europa.eu/web/thetis/current-detentions

THETIS is the inspection database operated by the European Maritime Safety Agency (EMSA).

| Field | Description |
|-------|-------------|
| IMO Number | International Maritime Organization vessel ID |
| Ship Name | Vessel name |
| Flag State | Country of registration |
| Ship Type | Vessel classification |
| Age | Vessel age |
| Date of Detention | When vessel was detained |
| Port of Detention | Where vessel was detained |
| Detaining Authority | Authority that issued detention |
| Number of Deficiencies | Count of compliance issues |
| ISM Company | Ship management company |

#### Data Access Restrictions (Paris MOU)

> "No part of the information contained in this website may be stored in a retrieval system, or transmitted in any form, or by any means without prior authorisation in writing from the owners of the data."

This severely limits automated access to detention data.

---

## Data Access Options

### Option 1: HTML Scraping (Recent Years) - Recommended for Prosecutions

**Complexity:** Low  
**Reliability:** High  
**Data Coverage:** 2020-present

Recent years are published as HTML pages on GOV.UK, making them easy to parse.

**Advantages:**
- Structured HTML format
- Consistent page structure across years
- No PDF parsing required
- GOV.UK is stable and reliable

**Implementation:**
```elixir
# Fetch HTML page
# Parse using Floki or similar
# Extract prosecution records from structured content
```

### Option 2: PDF Parsing (Historical Data)

**Complexity:** Medium-High  
**Reliability:** Medium  
**Data Coverage:** 2010-2019

Older years are PDF-only. Requires PDF text extraction.

**Challenges:**
- PDFs vary in structure year-to-year
- Text extraction may lose formatting
- Tables may not parse cleanly
- Some PDFs may be scanned images (OCR required)

**Tools:**
- `pdf-reader` (Elixir hex package)
- External service: AWS Textract, Google Document AI
- Python: `PyPDF2`, `pdfplumber`

**Sample PDF URL Pattern:**
```
https://assets.publishing.service.gov.uk/media/{hash}/{filename}.pdf
```

### Option 3: API Access (NOT Available)

**Status:** No public API exists for MCA prosecutions

Research confirmed:
- No API endpoints on GOV.UK
- No data.gov.uk dataset for prosecutions
- MCA has Survey and Inspection Database (SIAS) on data.gov.uk but NOT prosecutions

### Option 4: Detention Data (Restricted)

**Status:** Not recommended without authorization

Paris MOU and THETIS databases:
- Web interface only (no API)
- Explicit prohibition on automated retrieval
- Would require formal data sharing agreement
- UK-specific data mixed with all Paris MOU region

---

## Comparison with Existing Data Sources

| Source | Data Type | Volume/Year | Access Method | Complexity |
|--------|-----------|-------------|---------------|------------|
| **HSE** | Cases & Notices | ~1000+ | Web scraping | Medium |
| **EA** | Cases & Notices | ~500+ | API + scraping | Medium |
| **FRA (NFCC)** | Notices | ~200+ | Web scraping | Medium |
| **MCA** | Prosecutions | ~5-10 | HTML/PDF parse | Low-Medium |
| **MCA** | Detentions | N/A | Restricted | High (blocked) |

---

## Database Schema Mapping

MCA prosecution data maps to the existing `Case` resource:

| MCA Field | Existing Field | Notes |
|-----------|----------------|-------|
| Defendant | offender.name | Via Offender relationship |
| Date of Hearing | offence_hearing_date | Direct mapping |
| Court | *(new field or in details)* | Court name |
| Offence | offence_breaches | Legislation reference |
| Details | *(new field or notice_body)* | Full narrative |
| Fine | offence_fine | £ amount |
| Costs | offence_costs | £ amount |
| Total Penalty | calculated | fine + costs + surcharge |

### Proposed Schema Additions

```elixir
# May need additional fields:
attribute(:court_name, :string, description: "Name of court where case was heard")
attribute(:custodial_sentence, :string, description: "Prison term if applicable")
attribute(:community_service_hours, :integer, description: "Unpaid work hours")
attribute(:victim_surcharge, :decimal, description: "Victim surcharge amount")
```

### Agency Record

Need single Agency record for MCA:
- Name: "Maritime and Coastguard Agency"
- Code: `:mca`
- Type: "maritime_regulator"

---

## Implementation Recommendations

### Phase 1: HTML Scraper (Priority)

Focus on recent years (2020-2025) where data is in HTML format.

```elixir
defmodule EhsEnforcement.Scraping.Mca.ProsecutionScraper do
  @moduledoc """
  Scrapes MCA prosecution records from GOV.UK HTML pages.
  """
  
  @base_url "https://www.gov.uk/government/publications"
  
  def scrape_year(year) when year >= 2020 do
    # Fetch HTML page for year
    # Parse prosecution entries
    # Return structured data
  end
end
```

**Effort:** 1-2 days

### Phase 2: PDF Parser (Optional)

Add historical data from PDF reports if needed.

**Options:**
1. **Simple approach:** Use `pdf-reader` Elixir package
2. **Robust approach:** External service (AWS Textract)
3. **Manual:** One-time extraction for historical data

**Effort:** 2-4 days (depends on PDF complexity)

### Phase 3: Detention Data (Future/Deferred)

Requires formal agreement with Paris MOU/EMSA. Not recommended for initial implementation.

---

## Effort Estimate

| Task | Estimate |
|------|----------|
| GOV.UK HTML structure analysis | 2-4 hours |
| HTML scraper implementation | 1 day |
| PDF parser (if needed) | 2-3 days |
| Schema migration | 2-4 hours |
| Agency seed data | 1 hour |
| Testing & validation | 4-8 hours |
| **Total (HTML only)** | **2-3 days** |
| **Total (with PDF)** | **5-7 days** |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| PDF format changes | Low | Medium | Focus on HTML; PDF is historical |
| GOV.UK structure changes | Low | Low | Standard GOV.UK patterns |
| Low data volume | N/A | Low | Small dataset, quick to process |
| Detention data blocked | High | Medium | Defer detention scraping |

---

## Decision Points

### Recommended Approach

1. **Start with HTML scraping** for recent years (2020-2025)
2. **Defer PDF parsing** unless historical data is specifically needed
3. **Skip detention data** due to access restrictions
4. **Low priority overall** given small volume (~5-10 cases/year)

### Questions for Product Decision

1. Is historical data (pre-2020) needed, or is recent data sufficient?
2. What's the priority of MCA vs other agencies (SEPA, NRW)?
3. Is detention data valuable enough to pursue formal data sharing agreement?

---

## Next Steps

1. [ ] Confirm scope: HTML only vs HTML + PDF
2. [ ] Inspect GOV.UK HTML structure for 2024/2025 reports
3. [ ] Create spike to parse single year
4. [ ] Decision: Proceed with implementation or deprioritize

---

## References

- [MCA Prosecutions Collection](https://www.gov.uk/government/collections/prosecutions-and-detentions-mca-enforcement-policy-and-information)
- [MCA Enforcement Policy](https://www.gov.uk/government/publications/mca-enforcement-policy-statement)
- [Prosecutions Report 2024](https://www.gov.uk/government/publications/mca-enforcement-unit-prosecutions-2024/prosecutions-report-2024)
- [Prosecutions Report 2023](https://www.gov.uk/government/publications/mca-enforcement-unit-prosecutions-2023/prosecutions-report-2023)
- [Paris MOU Current Detentions](https://parismou.org/Inspection-Database/current-detentions)
- [THETIS Portal (EMSA)](https://portal.emsa.europa.eu/web/thetis/current-detentions)
- [Merchant Shipping Act 1995](https://www.legislation.gov.uk/ukpga/1995/21/contents)
