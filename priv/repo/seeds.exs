# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     EhsEnforcement.Repo.insert!(%EhsEnforcement.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias EhsEnforcement.Enforcement.Agency
require Logger

defmodule Seeds do
  # UK Safety Regulatory Agencies
  # Based on research from docs-dev/research/regulatory-agency-overview.md
  #
  # Status Legend:
  #   enabled: true  - Implemented and active
  #   enabled: false - Planned/researched but not yet implemented

  @agencies [
    # =====================================================
    # IMPLEMENTED AGENCIES
    # =====================================================
    %{
      code: :hse,
      name: "Health and Safety Executive",
      base_url: "https://www.hse.gov.uk",
      enabled: true
    },
    %{
      code: :ea,
      name: "Environment Agency",
      base_url: "https://environment.data.gov.uk",
      enabled: true
    },

    # =====================================================
    # HIGH PRIORITY - IN PROGRESS
    # =====================================================
    %{
      code: :sepa,
      name: "Scottish Environment Protection Agency",
      base_url: "https://beta.sepa.scot",
      enabled: true
    },
    %{
      code: :nrw,
      name: "Natural Resources Wales",
      base_url: "https://naturalresources.wales",
      enabled: false
    },

    # =====================================================
    # MEDIUM PRIORITY - RESEARCHED
    # =====================================================
    %{
      code: :orr,
      name: "Office of Rail and Road",
      base_url: "https://www.orr.gov.uk",
      enabled: false
    },
    %{
      code: :mca,
      name: "Maritime and Coastguard Agency",
      base_url: "https://www.gov.uk/government/organisations/maritime-and-coastguard-agency",
      enabled: false
    },
    %{
      code: :caa,
      name: "Civil Aviation Authority",
      base_url: "https://www.caa.co.uk",
      enabled: false
    },
    %{
      code: :cqc,
      name: "Care Quality Commission",
      base_url: "https://www.cqc.org.uk",
      enabled: false
    },
    %{
      code: :dwi,
      name: "Drinking Water Inspectorate",
      base_url: "https://www.dwi.gov.uk",
      enabled: false
    },
    %{
      code: :opss,
      name: "Office for Product Safety and Standards",
      base_url:
        "https://www.gov.uk/government/organisations/office-for-product-safety-and-standards",
      enabled: false
    },
    %{
      code: :gc,
      name: "Gambling Commission",
      base_url: "https://www.gamblingcommission.gov.uk",
      enabled: false
    },

    # =====================================================
    # LOWER PRIORITY - PLANNED
    # =====================================================
    %{
      code: :onr,
      name: "Office for Nuclear Regulation",
      base_url: "https://www.onr.org.uk",
      enabled: false
    },
    %{
      code: :fra,
      name: "Fire and Rescue Authorities (NFCC)",
      base_url: "https://nfcc.org.uk",
      enabled: false
    },
    %{
      code: :niea,
      name: "Northern Ireland Environment Agency",
      base_url: "https://www.daera-ni.gov.uk/northern-ireland-environment-agency",
      enabled: false
    },
    %{
      code: :fsa,
      name: "Food Standards Agency",
      base_url: "https://www.food.gov.uk",
      enabled: false
    },
    %{
      code: :ico,
      name: "Information Commissioner's Office",
      base_url: "https://ico.org.uk",
      enabled: false
    }
  ]

  def run do
    Logger.info("Seeding agencies...")

    results =
      Enum.map(@agencies, fn agency_attrs ->
        case create_or_update_agency(agency_attrs) do
          {:ok, :created, agency} ->
            Logger.info("Created agency: #{agency.name} (#{agency.code})")
            {:created, agency.code}

          {:ok, :exists, agency} ->
            Logger.info("Agency already exists: #{agency.name} (#{agency.code})")
            {:exists, agency.code}

          {:error, error} ->
            Logger.error("Failed to create agency #{agency_attrs.code}: #{inspect(error)}")
            {:error, agency_attrs.code}
        end
      end)

    created = Enum.count(results, fn {status, _} -> status == :created end)
    existing = Enum.count(results, fn {status, _} -> status == :exists end)
    failed = Enum.count(results, fn {status, _} -> status == :error end)

    Logger.info(
      "Agency seeding complete: #{created} created, #{existing} existing, #{failed} failed"
    )
  end

  defp create_or_update_agency(attrs) do
    case Ash.create(Agency, attrs) do
      {:ok, agency} ->
        {:ok, :created, agency}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        if duplicate_error?(errors) do
          # Agency already exists, fetch it
          case EhsEnforcement.Enforcement.get_agency_by_code(attrs.code) do
            {:ok, agency} -> {:ok, :exists, agency}
            error -> error
          end
        else
          {:error, errors}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp duplicate_error?(errors) do
    Enum.any?(errors, fn error ->
      error.field == :code and
        (String.contains?(to_string(error.message || ""), "already been taken") or
           String.contains?(to_string(error.message || ""), "has already been taken"))
    end)
  end
end

Seeds.run()
