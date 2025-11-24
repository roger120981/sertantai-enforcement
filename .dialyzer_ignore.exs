[
  # This file contains patterns to ignore specific Dialyzer warnings.
  # Patterns can be:
  # - Regular expressions: ~r"pattern"
  # - Tuples: {"file_pattern", :warning_type, ~c"message_pattern"}
  #
  # Run `mix dialyzer --list-unused-filters` to see which filters are not being used.
  # Keep this file minimal - only add filters for known false positives.

  # AshDiagram is a dev-only dependency used for generating diagrams
  # These functions are available at runtime but not in Dialyzer's PLT
  {"lib/mix/tasks/diagrams.generate.ex", :unknown_function},

  # Ash framework type inference issues - search_offenders can return empty list
  # but Dialyzer infers it always returns non-empty list or Page struct
  {"lib/ehs_enforcement/enforcement/resources/offender.ex", :pattern_match},

  # Additional call errors - function contract mismatches in legacy code
  {"lib/ehs_enforcement/legislation/taxa/lat_taxa.ex", :call},
  {"lib/ehs_enforcement/scraping/ea/notice_processor.ex", :call},

  # AgencyBehavior module attribute - false positive on @behaviour directive
  {"lib/ehs_enforcement/scraping/agencies/hse.ex", :pattern_match},

  # Complex with statement in EA case processor - Dialyzer struggles with nested with
  {"lib/ehs_enforcement/scraping/ea/case_processor.ex", :pattern_match},

  # HSE case scraper retry logic - pattern match on rate limit error
  {"lib/ehs_enforcement/scraping/hse/case_scraper.ex", :pattern_match},

  # Component timestamp display - placeholder function
  {"lib/ehs_enforcement_web/components/reports_action_card.ex", :pattern_match},

  # LiveView error boundary callback - Phoenix LiveView callback type complexity
  {"lib/ehs_enforcement_web/live/error_boundary.ex", :callback_type_mismatch},

  # Legislation LiveView pagination - Ash pagination result types
  {"lib/ehs_enforcement_web/live/legislation_live/index.ex", :pattern_match},

  # Offender LiveView show - Ash load result type inference
  {"lib/ehs_enforcement_web/live/offender_live/show.ex", :pattern_match},

  # Unused helper functions - may be used in future or kept for reference
  {"lib/ehs_enforcement/scraping/ea/notice_processor.ex", :unused_fun},

  # EA notice processor - unknown type from external Ash.Expr
  {"lib/ehs_enforcement/scraping/ea/notice_processor.ex", :unknown_type},
  {"lib/ehs_enforcement/scraping/ea/notice_processor.ex", :contract_supertype},
  {"lib/ehs_enforcement/scraping/ea/notice_processor.ex", :guard_fail},

  # Utility module - unknown types from complex map structures
  {"lib/ehs_enforcement/utility.ex", :unknown_type},

  # Legislation taxa - contract and guard issues in legacy tax-classification code
  {"lib/ehs_enforcement/legislation/taxa/lat_taxa.ex", :invalid_contract},
  {"lib/ehs_enforcement/legislation/taxa/lat_taxa.ex", :exact_eq},

  # CSV export functions - Enum.map_join return type inference issue
  {"lib/ehs_enforcement_web/live/legislation_live/show.ex", :unmatched_return}
]
