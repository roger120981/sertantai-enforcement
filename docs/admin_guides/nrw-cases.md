# NRW Enforcement Cases

This guide describes the Natural Resources Wales (NRW) enforcement cases available in the database, including data sources, structure, and legal considerations for use.

## Overview

Natural Resources Wales (Cyfoeth Naturiol Cymru) is Wales's principal environmental regulator, responsible for protecting the environment, managing natural resources, and responding to environmental incidents. The database contains criminal prosecution cases brought by NRW for environmental offences in Wales.

### Data Summary

| Metric | Value |
|--------|-------|
| Primary Jurisdiction | Wales |
| Case Type | Criminal prosecutions |
| Typical Annual Volume | ~80 prosecutions/year |
| Data Source | NRW news/press releases |

### Case Categories

| Category | Fine Threshold | Description |
|----------|----------------|-------------|
| NRW Prosecution | < £10,000 | Standard prosecutions for environmental offences |
| NRW Prosecution (Significant) | £10,000 - £99,999 | Significant environmental crimes |
| NRW Prosecution (Major) | £100,000+ | Major environmental crimes (e.g., water company pollution) |
| NRW POCA Confiscation | Varies | Proceeds of Crime Act orders |
| NRW Prosecution (Community Order) | N/A | Non-custodial sentences without fines |

### Common Offence Types

| Offence Type | Typical Legislation |
|--------------|---------------------|
| Illegal waste operations | Environmental Permitting Regulations 2016 |
| Waste dumping/fly-tipping | Environmental Protection Act 1990 |
| Water pollution | Environmental Permitting Regulations 2016 |
| Illegal tree felling | Forestry Act 1967 |
| Illegal fishing | Salmon and Freshwater Fisheries Act 1975 |
| Permit breaches | Environmental Permitting Regulations 2016 |

## Data Source

NRW enforcement data is collected from official news and press releases:

**Source URL**: https://naturalresources.wales/about-us/news-and-blogs/news/

Unlike SEPA (which maintains a structured enforcement register), NRW publishes prosecution outcomes through individual news articles. The scraper:

1. Fetches the news listing page
2. Identifies enforcement-related articles by URL patterns (e.g., `-fined-`, `-prosecuted-`, `-sentenced-`)
3. Parses article content using AI to extract structured case data
4. Handles multi-defendant articles (e.g., company and director prosecuted together)

### Enforcement URL Patterns

Articles are identified as enforcement-related if their URL contains:
- `-fined-`
- `-prosecuted-`
- `-sentenced-`
- `-prosecution`
- `-guilty-`
- `-convicted-`
- `-illegal-`
- `-court-`
- `-ordered-to-pay-`

## Data Structure

### Case Record Fields

| Field | Description |
|-------|-------------|
| `regulator_id` | Unique identifier: `nrw_YYYYMMDD_hash` |
| `offence_hearing_date` | Date of court hearing/sentencing |
| `offence_action_date` | Date of article publication |
| `offence_fine` | Fine amount (or POCA confiscation amount) |
| `offence_costs` | Prosecution costs + victim surcharge combined |
| `offence_result` | Sentence details (fines, community orders, etc.) |
| `offence_breaches` | Legislation breached |
| `offence_action_type` | Classification of prosecution severity |
| `url` | Link to original NRW news article |

### Linked Records

Each case is linked to:
- **Agency**: Natural Resources Wales (NRW)
- **Offender**: Individual or organisation that was prosecuted

### Offender Data

| Field | Description |
|-------|-------------|
| `name` | Full name of individual or company |
| `address` | Location if mentioned in article |
| `country` | Always "Wales" for NRW cases |

## AI-Powered Data Extraction

Because NRW publishes unstructured news articles rather than tabular data, the scraper uses AI (LLM) to extract structured information:

### Extraction Capabilities

| Challenge | Solution |
|-----------|----------|
| Variable phrasing | AI understands "fined £10,000" = "ordered to pay £10,000" |
| Multi-defendant articles | Extracts separate cases for each defendant |
| Penalty attribution | Associates correct fines/costs with each defendant |
| Shared penalties | Parses "Both were required to pay £2,000 each" correctly |
| Date formats | Handles "21 March 2024", "14 October 2025", etc. |

### Example: Multi-Defendant Extraction

From an article about "Benji and Co Limited and director Peter Rees", the AI extracts:

| Defendant | Fine | Costs | Surcharge |
|-----------|------|-------|-----------|
| Benji and Co Limited | £40,000 | £15,000 | £2,000 |
| Peter Rees | £10,000 | - | £2,000 |

Each defendant receives a separate case record with unique `regulator_id`.

## Legal Basis for Data Collection and Use

### Public Information

NRW prosecution outcomes are published as press releases on their official website. This information is:

1. **Matters of Public Record**: Court proceedings in England and Wales are generally public
2. **Official Publications**: NRW publishes this information in their capacity as a public body
3. **Public Interest**: Environmental enforcement serves the public interest

### Right to Use

This data may be used under the following basis:

1. **Open Government Licence**: Welsh Government and NRW data is typically available under the [Open Government Licence v3.0](http://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/)

2. **Public Interest**: Enforcement data serves legitimate purposes:
   - Supply chain due diligence
   - Environmental compliance awareness
   - Regulatory research and analysis

### Attribution Requirements

When using NRW enforcement data, appropriate attribution should be provided:

> Source: Natural Resources Wales News and Press Releases
> https://naturalresources.wales/about-us/news-and-blogs/news/

## Privacy Considerations

### Personal Data

NRW prosecution notices contain personal data where the defendant is an individual. This data is processed on the following basis:

1. **Legitimate Interest**: Processing enforcement data serves legitimate interests in:
   - Environmental protection
   - Business due diligence
   - Regulatory transparency

2. **Public Record**: Criminal prosecution outcomes are matters of public record

### Data Protection Principles

| Principle | Application |
|-----------|-------------|
| Lawfulness | Data obtained from official public press releases |
| Purpose Limitation | Use for compliance, due diligence, research purposes |
| Data Minimisation | Only relevant enforcement data collected |
| Accuracy | Data refreshed weekly via automated scraping |
| Storage Limitation | Historical records retained for trend analysis |
| Security | Database access controls and encryption in transit |

## Data Refresh Schedule

NRW cases are automatically scraped **weekly on Tuesdays** at 05:00 UTC via an Oban scheduled job. The scraper:

1. Fetches the news listing page from NRW's website
2. Identifies enforcement-related articles by URL patterns
3. Fetches and parses each article using AI
4. Generates deterministic `regulator_id` for deduplication
5. Creates new records for cases not already in the database
6. Logs results to the scrape session history

Manual scraping can also be triggered via the admin interface at `/admin/scrape`.

## Querying NRW Data

### Via API

```bash
# Get all NRW cases
GET /api/cases?filter[agency_code]=nrw

# Get recent NRW prosecutions
GET /api/cases?filter[agency_code]=nrw&sort=-offence_hearing_date&page[limit]=20

# Get major prosecutions (fines >= £100,000)
GET /api/cases?filter[agency_code]=nrw&filter[offence_action_type]=NRW%20Prosecution%20(Major)
```

### Via Database

```sql
SELECT 
  c.regulator_id,
  c.offence_hearing_date,
  c.offence_fine,
  c.offence_costs,
  c.offence_action_type,
  c.offence_breaches,
  o.name as offender_name
FROM cases c
JOIN offenders o ON c.offender_id = o.id
JOIN agencies a ON c.agency_id = a.id
WHERE a.code = 'nrw'
ORDER BY c.offence_hearing_date DESC;
```

## Deduplication

The `regulator_id` field ensures no duplicate cases are created:

**Format**: `nrw_{YYYYMMDD}_{8-char-hash}`

- `YYYYMMDD` - Hearing date (or article date if no hearing date)
- `8-char-hash` - MD5 hash of normalised offender name

**Example**: `nrw_20251014_0840d69c`

This deterministic ID means re-scraping the same article produces the same ID, preventing duplicates.

## Limitations and Disclaimers

1. **Not Legal Advice**: This data is provided for informational purposes only and does not constitute legal advice

2. **AI Extraction Accuracy**: Data is extracted using AI from unstructured text; occasional extraction errors may occur

3. **Point-in-Time Accuracy**: Data reflects NRW's published articles at the time of scraping; appeals or corrections may not be immediately reflected

4. **Article Coverage**: Only articles matching enforcement URL patterns are scraped; some prosecutions may be missed if article URLs don't match expected patterns

5. **Third-Party Verification**: For critical business decisions, users should verify enforcement status directly with NRW or court records

## Further Resources

- [NRW Enforcement and Sanctions Policy](https://naturalresources.wales/about-us/what-we-do/how-we-regulate/our-regulatory-responsibilities/enforcement-and-sanctions-policy/)
- [NRW Regulation Overview](https://naturalresources.wales/about-us/what-we-do/how-we-regulate/)
- [Welsh Government Environmental Regulation](https://www.gov.wales/environment)
- [Open Government Licence](http://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/)

## Contact

For questions about NRW enforcement data in this system, contact the development team or raise an issue in the project repository.

For official NRW enquiries:
- Website: https://naturalresources.wales/
- Email: enquiries@naturalresourceswales.gov.uk
- Phone: 0300 065 3000
