defmodule EhsEnforcement.Scraping.ProcessingLog do
  @moduledoc """
  Unified processing log for all agency scraping operations.
  Replaces separate HSE and EA processing log resources.

  This resource follows the specification from CASE_SCRAPING_REVIEW.md to eliminate
  field name conflicts and provide agency-agnostic processing log functionality.

  Field Mapping:
  - HSE: cases_scraped -> items_found, cases_skipped -> items_failed, existing_count -> items_existing
  - EA:  cases_found -> items_found, cases_failed -> items_failed, cases_existing -> items_existing
  """

  use Ash.Resource,
    domain: EhsEnforcement.Scraping,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table("processing_logs")
    repo(EhsEnforcement.Repo)
  end

  pub_sub do
    module(EhsEnforcement.PubSub)
    prefix("processing_log")

    publish(:create, ["created"])
  end

  attributes do
    uuid_primary_key(:id)

    # Common fields
    attribute(:session_id, :string, allow_nil?: false)
    # :hse, :ea, etc.
    attribute(:agency, :atom, allow_nil?: false)

    # Unified naming (agency-agnostic)
    # page for HSE, batch for EA
    attribute(:batch_or_page, :integer, default: 1)
    # cases_scraped/cases_found
    attribute(:items_found, :integer, default: 0)
    # cases_created (same for both)
    attribute(:items_created, :integer, default: 0)
    # existing_count/cases_existing
    attribute(:items_existing, :integer, default: 0)
    # cases_skipped/cases_failed
    attribute(:items_failed, :integer, default: 0)

    # Common metadata
    attribute(:creation_errors, {:array, :string}, default: [])
    attribute(:scraped_items, {:array, :map}, default: [])

    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :session_id,
        :agency,
        :batch_or_page,
        :items_found,
        :items_created,
        :items_existing,
        :items_failed,
        :creation_errors,
        :scraped_items
      ])
    end

    read :for_session do
      argument(:session_id, :string, allow_nil?: false)
      filter(expr(session_id == ^arg(:session_id)))
    end
  end

  validations do
    # Validate non-negative integer fields
    validate(compare(:batch_or_page, greater_than_or_equal_to: 0))
    validate(compare(:items_found, greater_than_or_equal_to: 0))
    validate(compare(:items_created, greater_than_or_equal_to: 0))
    validate(compare(:items_existing, greater_than_or_equal_to: 0))
    validate(compare(:items_failed, greater_than_or_equal_to: 0))

    # Validate agency is supported value
    validate(attribute_in(:agency, [:hse, :ea, :sepa, :nrw, :fra, :mca, :onr, :orr]))
  end
end
