# Configure ExUnit for robust concurrent testing
# See: .claude/sessions/2025-10-19-Test-Environment.md
ExUnit.start(
  # Limit concurrent test files to prevent resource exhaustion
  # With 8 CPU cores, default would be 16, but DB-heavy tests need more connections each
  # Temporarily reduced to 2 for Phase 2C verification (from 4)
  # Background: Each test case uses multiple DB connections (main process + Sandbox.allow for async operations)
  # This prevents "connection not available" errors and connection pool exhaustion
  # Increase back to 4 once auth-related test failures are fully resolved
  max_cases: 2,

  # Increase timeout for heavy operations (metrics refresh, complex queries)
  # 2 minutes - necessary for dashboard metric calculations and large data operations
  timeout: 120_000,

  # Exclude slow, integration, and external tests by default for faster development cycles
  # Note: :heavy tests (like dashboard) are INCLUDED by default with limited max_cases
  # Run with: mix test --include slow --include integration --include external
  # Or exclude heavy: mix test --exclude heavy
  # :external tests make live HTTP calls to agency websites (ORR, FRA, MCA)
  exclude: [:integration, :slow, :external]
)

# Configure Ecto SQL Sandbox for test isolation
# Each test runs in a transaction that's rolled back after completion
# This ensures tests don't interfere with each other's data
Ecto.Adapters.SQL.Sandbox.mode(EhsEnforcement.Repo, :manual)
