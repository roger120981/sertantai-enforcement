# Office of Rail and Road (ORR) Enforcement Data

## Overview

The Office of Rail and Road (ORR) is the independent safety and economic regulator for Britain's railways and the monitor of Highways England. ORR publishes enforcement data covering:

1. **Prosecutions** - Court cases resulting in conviction (since 1 April 2006)
2. **Improvement Notices** - Requirements to fix compliance issues (since 2012)
3. **Prohibition Notices** - Orders to stop dangerous activities (since 2012)

**Main Enforcement Page:** https://www.orr.gov.uk/enforcement

---

## Data Availability Summary

| Data Type | Date Range | Volume | Format |
|-----------|------------|--------|--------|
| **Prosecutions** | 1 April 2006 - Present | 119 total (~6/year avg) | HTML (structured) |
| **Improvement Notices** | 2012 - Present | ~5-10/year | HTML + PDF copies |
| **Prohibition Notices** | 2012 - Present | ~1-3/year | HTML + PDF copies |

**Pre-2006 Data:** Available from HSE website (ORR took over rail safety regulation from HSE on 1 April 2006)

---

## Prosecutions Data

### Source URL
https://www.orr.gov.uk/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/prosecutions

### Data Fields

Each prosecution record contains:

| Field | Description | Example |
|-------|-------------|---------|
| Company Name | Defendant organization | Network Rail Infrastructure Limited |
| Summary | Narrative of incident and violations | Trackworker fatalities at Margam |
| Breaches Involved | Specific legislation violated | Health and Safety at Work etc Act 1974, s.3(1) |
| Date(s) of Offence | When violation occurred | 3 July 2019 |
| Plea | Court plea | Guilty |
| Result | Conviction outcome | Convicted |
| Court | Jurisdiction | Swansea Crown Court |
| Sentencing Date | When penalty imposed | 14 February 2025 |
| Penalty | Fine amount with culpability category | £3,750,000 (High culpability, Category 1 harm) |
| Costs | Legal/court costs | £145,000 |
| Location of Offence | Geographic details | Near Margam, South Wales |
| ORR Team/Directorate | Internal organizational unit | Railway Safety Directorate |

### Volume & Historical Range

- **Total prosecutions:** 119 (April 2006 - October 2025)
- **Average:** ~6 prosecutions per year
- **Oldest record:** 1 April 2006
- **Most recent:** 3 October 2025

### Recent Notable Cases

| Date | Company | Fine | Incident |
|------|---------|------|----------|
| Oct 2025 | First Greater Western Limited | £1,000,000 | Twerton fatality (Dec 2018) |
| Feb 2025 | Network Rail | £3,750,000 | Margam trackworker deaths (Jul 2019) |
| Feb 2025 | Network Rail | £3,410,000 | Surbiton trackworker death |
| Jul 2023 | TfL + Tram Operations | £14,000,000 | Croydon tram crash |

### Data Structure

Prosecutions are presented as expandable accordion sections organized chronologically by year. Each case expands to show full details in a consistent format.

---

## Improvement Notices

### Source URL
https://www.orr.gov.uk/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/improvement-notices

### Available Years

| Years | URL Pattern |
|-------|-------------|
| 2022-2025 | `/improvement-notices/[YEAR]` |
| 2012-2021 | `/rail/publications/enforcement-publications/improvement-notices/improvement-notices-[YEAR]` |
| Pre-2012 | National Archives |

### Data Fields

| Field | Description | Example |
|-------|-------------|---------|
| Company Name | Recipient of notice | Network Rail Infrastructure Limited |
| Notice Reference | Unique identifier | I/20240812/JGT |
| Date Issued | When notice served | 12 Aug 2024 |
| Compliance Date | Deadline for remediation | 11 Dec 2024 |
| Violation Description | What breach occurred | Failed to obtain authorization before deployment |
| Status | Current state | Complied / Open |

### Sample 2024 Data (8 notices)

| Company | Reference | Issued | Compliance |
|---------|-----------|--------|------------|
| Great Western Society Ltd | I/20241205/MDB/01 | 5 Dec 2024 | 1 Mar 2025 |
| Tramway Museum Society | I/LS-20241111-1 | 11 Nov 2024 | 9 Dec 2024 |
| Avon Valley Railway Co Ltd | I/20240821/SDB/01 | 21 Aug 2024 | 31 Jan 2025 |
| Network Rail | I/20240812/JGT | 12 Aug 2024 | 11 Dec 2024 |
| Chiltern Railways | I/240219-1-JGT | 19 Feb 2024 | 30 May 2024 |
| Chiltern Railways | I/240219-2-JGT | 19 Feb 2024 | 31 Oct 2025 |
| Great Central Railway (Nottingham) | I/20240215/RGT/01 | 15 Feb 2024 | 30 Apr 2024 |
| East Anglia Transport Museum | I/LS-300124-1 | 30 Jan 2024 | 15 Jun 2024 |

### PDF Copies

Individual notice PDFs are available on the public register:
```
https://orrprdpubreg1.blob.core.windows.net/docs/[NOTICE-REFERENCE].pdf
```

Example:
```
https://orrprdpubreg1.blob.core.windows.net/docs/I-20231017-SDB-01-Strathspey-Railway-improvement-notice.pdf
```

---

## Prohibition Notices

### Source URL
https://www.orr.gov.uk/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/prohibition-notices

### Available Years
2012, 2013, 2014, 2015, 2016, 2018, 2019, 2020, 2021, 2022, 2023

**Note:** 2017 and 2024 pages not found (possibly no notices issued those years)

### Volume
Approximately 1-3 prohibition notices per year. These are issued only for serious immediate risks.

### Data Structure
Same format as improvement notices with PDF copies on public register.

---

## Data Access Options

### Option 1: HTML Scraping (Recommended)

**Complexity:** Low-Medium  
**Reliability:** High  
**Data Coverage:** Complete (2006-present for prosecutions, 2012-present for notices)

The ORR website uses consistent HTML structure with well-organized data:
- Prosecutions: Accordion-style expandable sections
- Notices: Tabular data per year with links to PDF copies

**Advantages:**
- Clean, consistent HTML structure
- All data fields clearly labeled
- No anti-bot measures observed
- RSS feed available for updates

**Implementation:**
```elixir
defmodule EhsEnforcement.Scraping.Orr.ProsecutionScraper do
  @base_url "https://www.orr.gov.uk"
  
  def scrape_prosecutions do
    # Fetch main prosecutions page
    # Parse accordion sections
    # Extract structured data per prosecution
  end
end
```

### Option 2: PDF Parsing (For Notice Documents)

**Complexity:** Medium  
**Data Coverage:** Notice documents only

Individual improvement and prohibition notices are published as PDFs. These could be parsed for additional detail not in the HTML summaries.

PDF URL pattern:
```
https://orrprdpubreg1.blob.core.windows.net/docs/[REFERENCE].pdf
```

### Option 3: API Access (NOT Available)

**Status:** No public enforcement API exists

Research confirmed:
- ORR Data Portal (dataportal.orr.gov.uk) focuses on statistics, not enforcement
- data.gov.uk has no ORR enforcement datasets
- No documented API endpoints for enforcement data

### Option 4: RSS Feed (For Updates)

**URL:** https://www.orr.gov.uk/taxonomy/term/25/feed

Can be used to monitor new enforcement actions without full scraping.

---

## Comparison with Existing Data Sources

| Source | Data Type | Volume/Year | Access | Historical Depth |
|--------|-----------|-------------|--------|------------------|
| **HSE** | Cases & Notices | ~1000+ | Scraping | Multi-year |
| **EA** | Cases & Notices | ~500+ | API + Scraping | Multi-year |
| **FRA (NFCC)** | Notices | ~200+ | Scraping | 3 years |
| **MCA** | Prosecutions | ~5-10 | HTML/PDF | 2010+ |
| **ORR** | Prosecutions + Notices | ~10-15 | Scraping | 2006+ (prosecutions) |

---

## Database Schema Mapping

### Prosecutions → Case Resource

| ORR Field | Existing Field | Notes |
|-----------|----------------|-------|
| Company Name | offender.name | Via Offender relationship |
| Sentencing Date | offence_hearing_date | Direct mapping |
| Court | *(new or in details)* | Court name |
| Breaches Involved | offence_breaches | Legislation reference |
| Summary | *(notice_body or new)* | Full narrative |
| Penalty | offence_fine | £ amount |
| Costs | offence_costs | £ amount |
| Date(s) of Offence | offence_action_date | Incident date |
| Location | offender.address | Or location field |
| Result | offence_result | Conviction status |

### Improvement/Prohibition Notices → Notice Resource

| ORR Field | Existing Field | Notes |
|-----------|----------------|-------|
| Company Name | offender.name | Via Offender relationship |
| Notice Reference | regulator_id | Unique identifier |
| Date Issued | notice_date | Direct mapping |
| Compliance Date | compliance_date | Direct mapping |
| Violation Description | notice_body | Main content |
| Status | notice_status (new) | IN_FORCE/COMPLIED/WITHDRAWN |

### Agency Record

Single Agency record needed:
- Name: "Office of Rail and Road"
- Code: `:orr`
- Type: "rail_regulator"

---

## Implementation Recommendations

### Phase 1: Prosecution Scraper (Priority)

Scrape all 119 prosecutions from the main prosecutions page.

```elixir
defmodule EhsEnforcement.Scraping.Orr.ProsecutionScraper do
  @moduledoc """
  Scrapes ORR prosecution records from the enforcement pages.
  """
  
  @prosecutions_url "https://www.orr.gov.uk/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/prosecutions"
  
  def scrape_all_prosecutions do
    # 1. Fetch main page
    # 2. Parse each year's accordion section
    # 3. Extract structured prosecution data
    # 4. Return list of Case records
  end
end
```

**Effort:** 1-2 days

### Phase 2: Notice Scrapers

Scrape improvement and prohibition notices by year.

```elixir
defmodule EhsEnforcement.Scraping.Orr.NoticeScraper do
  @years 2012..2025
  
  def scrape_improvement_notices(year) do
    # Fetch year page
    # Parse notice entries
    # Optionally fetch PDF for full text
  end
  
  def scrape_prohibition_notices(year) do
    # Similar pattern
  end
end
```

**Effort:** 1-2 days

### Phase 3: Scheduled Updates

- Use RSS feed to detect new enforcement actions
- Weekly scrape of current year pages
- Lower frequency than HSE/EA (smaller volume)

---

## Effort Estimate

| Task | Estimate |
|------|----------|
| HTML structure analysis | 2-4 hours |
| Prosecution scraper | 1 day |
| Notice scrapers | 1 day |
| Schema migration (if needed) | 2-4 hours |
| Agency seed data | 1 hour |
| Testing & validation | 4-8 hours |
| Scheduled job setup | 2-4 hours |
| **Total** | **3-4 days** |

---

## Legal & Compliance Considerations

### Data Status
- **Public data:** Published under statutory obligation (Environment and Safety Information Act 1988)
- **No restrictions:** Public register explicitly maintained for transparency
- **Government source:** Official ORR website (gov.uk domain)

### Scraping Compliance
- Respect robots.txt
- Implement rate limiting (1 request per 2-3 seconds)
- Use RSS feed for update monitoring where possible

---

## Next Steps

1. [ ] Inspect HTML structure of prosecutions page (developer tools)
2. [ ] Create spike to parse single prosecution record
3. [ ] Verify PDF URL pattern for notices
4. [ ] Decision: Proceed with implementation

---

## References

- [ORR Enforcement Overview](https://www.orr.gov.uk/enforcement)
- [ORR Health and Safety Prosecutions](https://www.orr.gov.uk/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/prosecutions)
- [Improvement Notices](https://www.orr.gov.uk/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/improvement-notices)
- [Prohibition Notices](https://www.orr.gov.uk/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/prohibition-notices)
- [ORR Public Register](https://www.orr.gov.uk/public-register)
- [ORR Data Portal](https://dataportal.orr.gov.uk/)
- [RSS Feed for Enforcement](https://www.orr.gov.uk/taxonomy/term/25/feed)
- [Health and Safety at Work etc Act 1974](https://www.legislation.gov.uk/ukpga/1974/37/contents)
