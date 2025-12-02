# HSE Cases API Schema Documentation

## Overview

The Health and Safety Executive (HSE) provides public access to enforcement case data through their web portal. This document describes the URL structure, parameters, and data schema used for scraping HSE conviction and notice data.

## Base URLs

### Convictions Database
```
https://resources.hse.gov.uk/convictions/case/
```

### Notices Database  
```
https://resources.hse.gov.uk/notices/case/
```

## URL Structure and Parameters

### Case List Endpoint
```
https://resources.hse.gov.uk/{database}/case/case_list.asp?{parameters}
```

#### Parameters Breakdown

| Parameter | Description | Values | Example |
|-----------|------------|--------|---------|
| `PN` | **Page Number** | Integer (1, 2, 3...) | `PN=2` |
| `ST` | **Search Type** | `C` = Cases | `ST=C` |
| `EO` | **Exact Operation** | `LIKE` = Contains search | `EO=LIKE` |
| `SN` | **Search Name** | `F` = Full search | `SN=F` |
| `SF` | **Search Field** | `DN` = Date/Name, `CN` = Case Number | `SF=DN` |
| `SV` | **Search Value** | Search term (empty for all) | `SV=` (all cases) |
| `SO` | **Sort Order** | `DODS` = Date of Decision (descending) | `SO=DODS` |

#### Sort Order Options
- `DODS` - Date of Decision, Descending (newest first)
- `DOAS` - Date of Decision, Ascending (oldest first)
- `CNAS` - Case Number, Ascending
- `CNDS` - Case Number, Descending
- `ONAS` - Offender Name, Ascending
- `ONDS` - Offender Name, Descending

#### Search Field Options
- `DN` - Date/Name search (general search)
- `CN` - Case Number search (specific case lookup)
- `OF` - Offender name search
- `LA` - Local Authority search
- `IN` - Industry search

### Case Details Endpoint
```
https://resources.hse.gov.uk/{database}/case/case_details.asp?SF=CN&SV={regulator_id}
```

## Data Schema

### Scraped Case Structure

Each case contains the following core data points:

```elixir
%ScrapedCase{
  regulator_id: String.t(),           # Unique HSE case identifier
  offender_name: String.t(),          # Company/individual name
  offence_action_date: Date.t(),      # Date of the offence/incident
  offence_location: String.t(),       # Location where offence occurred
  offence_type: String.t(),           # Type of health & safety violation
  offender_local_authority: String.t(), # Local authority jurisdiction
  offender_main_activity: String.t(),  # Primary business activity
  offender_industry: String.t(),       # Industry classification
  decision_date: Date.t(),            # Court decision date
  court_name: String.t(),             # Court that heard the case
  fine_amount: Decimal.t(),           # Financial penalty imposed
  costs_amount: Decimal.t(),          # Legal costs awarded
  investigation_officer: String.t(),   # HSE investigating officer
  summary: String.t(),                # Case summary/description
  conviction_outcome: String.t(),     # Guilty/not guilty/etc
  page_number: Integer.t(),           # Source page number
  scraped_at: DateTime.t(),           # When data was scraped
  # Additional fields may be present depending on case type
}
```

### Database Differences

#### Convictions Database
- Contains concluded court cases
- Includes fine amounts and costs
- Has conviction outcomes
- More complete financial data

#### Notices Database  
- Contains improvement/prohibition notices
- Different enforcement actions
- May not have court proceedings
- Different outcome types

## Example URLs

### Get All Cases, Page 1 (Most Recent First)
```
https://resources.hse.gov.uk/convictions/case/case_list.asp?PN=1&ST=C&EO=LIKE&SN=F&SF=DN&SV=&SO=DODS
```

### Search for Specific Case by ID
```
https://resources.hse.gov.uk/convictions/case/case_list.asp?ST=C&EO=LIKE&SN=F&SF=CN&SV=4797069
```

### Search by Company Name
```
https://resources.hse.gov.uk/convictions/case/case_list.asp?ST=C&EO=LIKE&SN=F&SF=OF&SV=ACME%20CONSTRUCTION
```

### Get Case Details
```
https://resources.hse.gov.uk/convictions/case/case_details.asp?SF=CN&SV=4797069
```

## Scraping Implementation Notes

### Rate Limiting
- HSE implements rate limiting on their endpoints
- Current implementation uses 3-second delays between requests
- Respectful scraping practices are implemented

### Error Handling
- HTTP 500+ errors trigger retry logic (up to 3 attempts)
- Rate limiting responses are handled with exponential backoff
- Network timeouts are configurable (default: 30 seconds)

### Data Processing Pipeline
1. **Scrape**: Fetch HTML from case list pages
2. **Parse**: Extract case data using HTML parsing
3. **Enrich**: Fetch additional details for each case
4. **Process**: Clean and standardize data
5. **Store**: Create Ash resources in PostgreSQL

### Duplicate Detection
- Cases are identified by `regulator_id` field
- Bulk duplicate detection is attempted first
- Falls back to individual case checking if bulk fails

## Configuration

Current scraping configuration in the EHS Enforcement application:

```elixir
# Default configuration
@default_database "convictions"
@base_url_template "https://resources.hse.gov.uk/%{database}/case/"
@max_retries 3
@retry_delay_ms 1000
```

## Data Quality Notes

### Known Issues
- Some dates may be missing or in inconsistent formats  
- Fine amounts may include non-numeric text
- Company names may have inconsistent formatting
- Some fields may be empty for older cases

### Data Validation
- All scraped data goes through validation before storage
- Invalid dates are handled gracefully
- Monetary amounts are parsed and stored as Decimal types
- Text fields are trimmed and normalized

## Data Currency and Publication Timeline

### HSE Publishing Process
- **Publication Delay**: Cases are published 9 weeks after conviction
- **Quality Assurance**: Delay accounts for appeals process and internal QA
- **Data Retention**: Cases remain on main register for 1 year, then moved to history register for 9 additional years

### Current Data Status (as of July 2025)
- **Most Recent Case**: June 17, 2024 (Gary Saville)
- **Total Cases Available**: 191 results across 20 pages
- **Data Gap**: ~13 month gap due to significant court system backlogs
- **Root Cause**: Record backlog of criminal cases in Crown Court system

### Court System Impact on Data Publication
- **Court Delays**: Substantial delays with trial dates being set well into 2025
- **Typical Timeline**: 2+ years for cases to reach court resolution
- **Crown Court Backlog**: Record backlog affecting all criminal cases including H&S prosecutions
- **Prosecution Trends**: 2024 seeing return to pre-pandemic prosecution levels but court resolution severely delayed
- **HSE Response**: Introduction of Crown Court Digital Case System (CCDCS) to streamline case management

### Monitoring Recommendations
- Regular scraping to detect when new cases are published
- Monitor HSE announcements for changes to publication process
- Consider contacting HSE directly about recent case publication delays

## Legal and Ethical Considerations

- HSE data is publicly available for transparency
- Scraping is performed respectfully with appropriate delays
- Data is used for research and public interest purposes
- No personal data of individuals is scraped beyond what HSE publishes
- Attribution to HSE is maintained in all derived works

## Related Documentation

- [Scraping Configuration](./scraping_config.md)
- [Rate Limiting](./rate_limiting.md) 
- [Data Processing Pipeline](./data_processing.md)
- [HSE Official Documentation](https://www.hse.gov.uk/prosecutions/)