defmodule Mix.Tasks.ScrapeEaNotices do
  @moduledoc """
  Mix task to scrape EA enforcement notices for a given year and persist to database.

  ## Usage

      mix scrape_ea_notices 2024
      mix scrape_ea_notices 2023
  """
  use Mix.Task

  require Logger

  alias EhsEnforcement.Scraping.Ea.NoticeScraper
  alias EhsEnforcement.Scraping.Ea.NoticeProcessor

  @shortdoc "Scrape EA enforcement notices for a given year"

  def run([year_str]) do
    # Start the application to ensure Repo and dependencies are available
    Mix.Task.run("app.start")

    year = String.to_integer(year_str)
    date_from = Date.new!(year, 1, 1)
    date_to = Date.new!(year, 12, 31)

    IO.puts("Scraping EA enforcement notices for #{year}...")
    IO.puts("Date range: #{date_from} to #{date_to}")

    case NoticeScraper.collect_and_enrich_notices(date_from, date_to) do
      {:ok, notices} ->
        IO.puts("Successfully scraped #{length(notices)} EA notices")
        IO.puts("Processing and persisting notices...")

        # Use nil actor for automated scraping
        actor = nil

        results =
          Enum.map(notices, fn notice ->
            case NoticeProcessor.process_and_create_notice(notice, actor) do
              {:ok, _created_notice, status} -> {status, notice.ea_record_id}
              {:error, reason} -> {:error, notice.ea_record_id, reason}
            end
          end)

        created = Enum.count(results, fn {status, _} -> status == :created end)
        updated = Enum.count(results, fn {status, _} -> status == :updated end)
        existing = Enum.count(results, fn {status, _} -> status == :existing end)
        errors = Enum.count(results, fn result -> elem(result, 0) == :error end)

        IO.puts("\n=== Results ===")
        IO.puts("Created:  #{created}")
        IO.puts("Updated:  #{updated}")
        IO.puts("Existing: #{existing}")
        IO.puts("Errors:   #{errors}")
        IO.puts("Total:    #{length(results)}")

        if errors > 0 do
          IO.puts("\nErrors:")

          results
          |> Enum.filter(fn result -> elem(result, 0) == :error end)
          |> Enum.each(fn {_status, record_id, reason} ->
            IO.puts("  - #{record_id}: #{inspect(reason)}")
          end)
        end

      {:error, reason} ->
        IO.puts("Scraping error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  def run(_) do
    IO.puts("Usage: mix scrape_ea_notices <year>")
    IO.puts("Example: mix scrape_ea_notices 2024")
    exit({:shutdown, 1})
  end
end
