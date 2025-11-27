defmodule EhsEnforcement.Scraping.ScrapeSession do
  @moduledoc """
  Ash resource for tracking HSE scraping sessions with real-time progress updates.
  """

  use Ash.Resource,
    domain: EhsEnforcement.Scraping,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table("scrape_sessions")
    repo(EhsEnforcement.Repo)
  end

  pub_sub do
    module(EhsEnforcement.PubSub)
    prefix("scrape_session")

    publish(:create, ["created"])
    publish(:update, ["updated"])
  end

  attributes do
    uuid_primary_key(:id)

    attribute :session_id, :string do
      allow_nil?(false)
    end

    # Agency identifier - determines which scraping pattern is used
    attribute :agency, :atom do
      allow_nil?(false)
      default(:hse)
      constraints(one_of: [:hse, :ea])
    end

    # HSE-specific parameters (page-based scraping)
    attribute :start_page, :integer do
      allow_nil?(false)
      default(1)
    end

    attribute :max_pages, :integer do
      allow_nil?(false)
      default(10)
    end

    attribute :end_page, :integer do
      allow_nil?(true)
    end

    attribute :database, :string do
      allow_nil?(false)
      default("convictions")
      constraints(allow_empty?: false)
    end

    # EA-specific parameters (date-range scraping)
    attribute :date_from, :date do
      allow_nil?(true)
    end

    attribute :date_to, :date do
      allow_nil?(true)
    end

    attribute :action_types, {:array, :atom} do
      allow_nil?(true)
      constraints(items: [one_of: [:court_case, :caution, :enforcement_notice]])
    end

    # Common status field
    attribute :status, :atom do
      allow_nil?(false)
      default(:pending)
      constraints(one_of: [:pending, :running, :completed, :failed, :stopped])
    end

    attribute(:current_page, :integer)
    attribute(:pages_processed, :integer, default: 0)
    attribute(:cases_found, :integer, default: 0)
    attribute(:cases_processed, :integer, default: 0)
    attribute(:cases_created, :integer, default: 0)
    attribute(:cases_created_current_page, :integer, default: 0)
    attribute(:cases_updated, :integer, default: 0)
    attribute(:cases_updated_current_page, :integer, default: 0)
    attribute(:cases_exist_total, :integer, default: 0)
    attribute(:cases_exist_current_page, :integer, default: 0)
    attribute(:errors_count, :integer, default: 0)

    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :session_id,
        :agency,
        :start_page,
        :max_pages,
        :end_page,
        :database,
        :date_from,
        :date_to,
        :action_types,
        :status,
        :current_page,
        :pages_processed,
        :cases_found,
        :cases_processed,
        :cases_created,
        :cases_created_current_page,
        :cases_updated,
        :cases_updated_current_page,
        :cases_exist_total,
        :errors_count
      ])
    end

    update :update do
      primary?(true)
      require_atomic?(false)

      accept([
        :status,
        :current_page,
        :pages_processed,
        :cases_found,
        :cases_processed,
        :cases_created,
        :cases_created_current_page,
        :cases_updated,
        :cases_updated_current_page,
        :cases_exist_total,
        :cases_exist_current_page,
        :errors_count
      ])
    end

    update :mark_stopped do
      description "Mark a session as stopped (for manual intervention or cleanup)"
      require_atomic?(false)
      accept([:status])

      change(set_attribute(:status, :stopped))
    end

    read :active do
      description "Get currently active/running sessions"
      filter(expr(status in [:pending, :running]))
    end

    read :stale do
      description "Get stale sessions (running for more than 24 hours)"
      filter(expr(status in [:pending, :running] and updated_at < ago(24, :hour)))
    end
  end

  validations do
    validate(compare(:start_page, greater_than: 0))
    validate(compare(:max_pages, greater_than: 0))
    validate(compare(:max_pages, less_than_or_equal_to: 100))
    # TODO: Re-enable when Ash framework bug is fixed
    # validate attribute_in(:database, ["convictions", "notices"])
  end

  identities do
    identity(:unique_session_id, [:session_id])
  end
end
