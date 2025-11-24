defmodule Mix.Tasks.Evaluate.CreateTestDataset do
  @moduledoc """
  Creates a balanced test dataset for AI model evaluation.

  This task selects a representative sample of enforcement cases for testing
  AI enrichment models on RunPod. The dataset balances:
  - Temporal distribution (recent vs older cases)
  - Financial range (low, medium, high fines)
  - Complexity levels

  ## Usage

      mix evaluate.create_test_dataset

  ## Output

  Generates `test/fixtures/ai_evaluation/test_dataset.json` containing:
  - 20 representative cases with full details
  - Metadata about selection criteria
  - Export timestamp

  ## Configuration

  Edit this file to adjust:
  - Sample size (currently 20 cases)
  - Selection criteria weights
  - Output format
  """

  use Mix.Task
  require Ash.Query

  @shortdoc "Create balanced test dataset for AI model evaluation"

  @output_path "test/fixtures/ai_evaluation/test_dataset.json"
  @sample_size_cases 15
  @sample_size_notices 10

  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("Creating test dataset for AI model evaluation...")
    Mix.shell().info("Target: #{@sample_size_cases} cases + #{@sample_size_notices} notices")

    # Ensure output directory exists
    File.mkdir_p!(Path.dirname(@output_path))

    # Load cases using different selection strategies
    test_cases =
      []
      |> add_recent_cases()
      |> add_medium_age_cases()
      |> add_older_cases()
      |> add_low_fine_cases()
      |> add_medium_fine_cases()
      |> add_high_fine_cases()
      |> Enum.uniq_by(& &1.id)
      |> Enum.take(@sample_size_cases)

    Mix.shell().info("Selected #{length(test_cases)} unique cases")

    # Load notices using different selection strategies
    test_notices =
      []
      |> add_recent_notices()
      |> add_medium_age_notices()
      |> add_older_notices()
      |> Enum.uniq_by(& &1.id)
      |> Enum.take(@sample_size_notices)

    Mix.shell().info("Selected #{length(test_notices)} unique notices")

    # Convert to JSON-friendly format
    dataset = %{
      metadata: %{
        created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        sample_size_cases: length(test_cases),
        sample_size_notices: length(test_notices),
        total_samples: length(test_cases) + length(test_notices),
        selection_criteria: [
          "Cases: Recent (3mo), Medium-age (6-12mo), Older (12-24mo)",
          "Cases: Low fines (<£10k), Medium (£10k-£100k), High (>£100k)",
          "Notices: Recent (3mo), Medium-age (6-12mo), Older (12-24mo)"
        ],
        purpose: "AI model evaluation for enforcement action enrichment (cases + notices)"
      },
      cases: Enum.map(test_cases, &format_case/1),
      notices: Enum.map(test_notices, &format_notice/1)
    }

    # Write to JSON file
    json = Jason.encode!(dataset, pretty: true)
    File.write!(@output_path, json)

    Mix.shell().info("✓ Test dataset created: #{@output_path}")
    Mix.shell().info("")
    print_summary(dataset)
  end

  # Load cases from last 3 months
  defp add_recent_cases(acc) do
    three_months_ago = DateTime.utc_now() |> DateTime.add(-90, :day)

    cases =
      EhsEnforcement.Enforcement.Case
      |> Ash.Query.filter(inserted_at >= ^three_months_ago)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(3)
      |> Ash.read!()

    acc ++ cases
  end

  # Load cases from 6-12 months ago
  defp add_medium_age_cases(acc) do
    twelve_months_ago = DateTime.utc_now() |> DateTime.add(-365, :day)
    six_months_ago = DateTime.utc_now() |> DateTime.add(-180, :day)

    cases =
      EhsEnforcement.Enforcement.Case
      |> Ash.Query.filter(inserted_at >= ^twelve_months_ago and inserted_at < ^six_months_ago)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(3)
      |> Ash.read!()

    acc ++ cases
  end

  # Load cases from 12-24 months ago
  defp add_older_cases(acc) do
    twenty_four_months_ago = DateTime.utc_now() |> DateTime.add(-730, :day)
    twelve_months_ago = DateTime.utc_now() |> DateTime.add(-365, :day)

    cases =
      EhsEnforcement.Enforcement.Case
      |> Ash.Query.filter(
        inserted_at >= ^twenty_four_months_ago and inserted_at < ^twelve_months_ago
      )
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(2)
      |> Ash.read!()

    acc ++ cases
  end

  # Load cases with low fines (<£10,000)
  defp add_low_fine_cases(acc) do
    cases =
      EhsEnforcement.Enforcement.Case
      |> Ash.Query.filter(offence_fine < 10_000 and not is_nil(offence_fine))
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(3)
      |> Ash.read!()

    acc ++ cases
  end

  # Load cases with medium fines (£10,000-£100,000)
  defp add_medium_fine_cases(acc) do
    cases =
      EhsEnforcement.Enforcement.Case
      |> Ash.Query.filter(offence_fine >= 10_000 and offence_fine <= 100_000)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(3)
      |> Ash.read!()

    acc ++ cases
  end

  # Load cases with high fines (>£100,000)
  defp add_high_fine_cases(acc) do
    cases =
      EhsEnforcement.Enforcement.Case
      |> Ash.Query.filter(offence_fine > 100_000)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(3)
      |> Ash.read!()

    acc ++ cases
  end

  # Load notices from last 3 months
  defp add_recent_notices(acc) do
    three_months_ago = DateTime.utc_now() |> DateTime.add(-90, :day)

    notices =
      EhsEnforcement.Enforcement.Notice
      |> Ash.Query.filter(inserted_at >= ^three_months_ago)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(4)
      |> Ash.read!()

    acc ++ notices
  end

  # Load notices from 6-12 months ago
  defp add_medium_age_notices(acc) do
    twelve_months_ago = DateTime.utc_now() |> DateTime.add(-365, :day)
    six_months_ago = DateTime.utc_now() |> DateTime.add(-180, :day)

    notices =
      EhsEnforcement.Enforcement.Notice
      |> Ash.Query.filter(inserted_at >= ^twelve_months_ago and inserted_at < ^six_months_ago)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(3)
      |> Ash.read!()

    acc ++ notices
  end

  # Load notices from 12-24 months ago
  defp add_older_notices(acc) do
    twenty_four_months_ago = DateTime.utc_now() |> DateTime.add(-730, :day)
    twelve_months_ago = DateTime.utc_now() |> DateTime.add(-365, :day)

    notices =
      EhsEnforcement.Enforcement.Notice
      |> Ash.Query.filter(
        inserted_at >= ^twenty_four_months_ago and inserted_at < ^twelve_months_ago
      )
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(3)
      |> Ash.read!()

    acc ++ notices
  end

  # Format case for JSON export
  defp format_case(case_record) do
    %{
      id: case_record.id,
      case_reference: case_record.case_reference,
      regulator_id: case_record.regulator_id,
      offence_result: case_record.offence_result,
      offence_action_type: case_record.offence_action_type,
      offence_fine: case_record.offence_fine,
      offence_costs: case_record.offence_costs,
      offence_action_date: case_record.offence_action_date,
      offence_hearing_date: case_record.offence_hearing_date,
      offence_breaches: case_record.offence_breaches,
      environmental_impact: case_record.environmental_impact,
      environmental_receptor: case_record.environmental_receptor,
      url: case_record.url,
      inserted_at: case_record.inserted_at |> DateTime.to_iso8601()
    }
  end

  # Format notice for JSON export
  defp format_notice(notice_record) do
    %{
      id: notice_record.id,
      regulator_ref_number: notice_record.regulator_ref_number,
      regulator_id: notice_record.regulator_id,
      offence_action_type: notice_record.offence_action_type,
      notice_date: notice_record.notice_date,
      operative_date: notice_record.operative_date,
      compliance_date: notice_record.compliance_date,
      notice_body: notice_record.notice_body,
      offence_breaches: notice_record.offence_breaches,
      environmental_impact: notice_record.environmental_impact,
      environmental_receptor: notice_record.environmental_receptor,
      legal_act: notice_record.legal_act,
      legal_section: notice_record.legal_section,
      url: notice_record.url,
      inserted_at: notice_record.inserted_at |> DateTime.to_iso8601()
    }
  end

  # Print summary statistics
  defp print_summary(dataset) do
    cases = dataset.cases
    notices = dataset.notices

    Mix.shell().info("Dataset Summary:")
    Mix.shell().info("================")
    Mix.shell().info("")

    Mix.shell().info(
      "Total samples: #{length(cases)} cases + #{length(notices)} notices = #{length(cases) + length(notices)}"
    )

    Mix.shell().info("")

    # Cases temporal distribution
    Mix.shell().info("Cases - Temporal Distribution:")
    case_temporal_stats = temporal_distribution(cases)

    Enum.each(case_temporal_stats, fn {period, count} ->
      Mix.shell().info("  #{period}: #{count} cases")
    end)

    Mix.shell().info("")

    # Fine range distribution
    Mix.shell().info("Cases - Fine Range Distribution:")
    fine_stats = fine_distribution(cases)

    Enum.each(fine_stats, fn {range, count} ->
      Mix.shell().info("  #{range}: #{count} cases")
    end)

    Mix.shell().info("")

    # Total fines
    total_fines =
      cases
      |> Enum.map(& &1.offence_fine)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Decimal.to_float/1)
      |> Enum.sum()

    avg_fine = if length(cases) > 0, do: total_fines / length(cases), else: 0.0

    Mix.shell().info("Total fines: £#{:erlang.float_to_binary(total_fines, decimals: 2)}")
    Mix.shell().info("Average fine: £#{:erlang.float_to_binary(avg_fine, decimals: 2)}")
    Mix.shell().info("")

    # Notices temporal distribution
    Mix.shell().info("Notices - Temporal Distribution:")
    notice_temporal_stats = temporal_distribution(notices)

    Enum.each(notice_temporal_stats, fn {period, count} ->
      Mix.shell().info("  #{period}: #{count} notices")
    end)

    Mix.shell().info("")

    # Notice types distribution
    Mix.shell().info("Notices - Action Type Distribution:")
    notice_type_stats = notice_type_distribution(notices)

    Enum.each(notice_type_stats, fn {type, count} ->
      Mix.shell().info("  #{type}: #{count} notices")
    end)
  end

  defp temporal_distribution(cases) do
    now = DateTime.utc_now()
    three_months_ago = DateTime.add(now, -90, :day)
    six_months_ago = DateTime.add(now, -180, :day)
    twelve_months_ago = DateTime.add(now, -365, :day)

    Enum.reduce(
      cases,
      %{"0-3 months" => 0, "3-6 months" => 0, "6-12 months" => 0, "12+ months" => 0},
      fn case_data, acc ->
        {:ok, inserted_at, _} = DateTime.from_iso8601(case_data.inserted_at)

        cond do
          DateTime.compare(inserted_at, three_months_ago) in [:gt, :eq] ->
            Map.update(acc, "0-3 months", 1, &(&1 + 1))

          DateTime.compare(inserted_at, six_months_ago) in [:gt, :eq] ->
            Map.update(acc, "3-6 months", 1, &(&1 + 1))

          DateTime.compare(inserted_at, twelve_months_ago) in [:gt, :eq] ->
            Map.update(acc, "6-12 months", 1, &(&1 + 1))

          true ->
            Map.update(acc, "12+ months", 1, &(&1 + 1))
        end
      end
    )
  end

  defp fine_distribution(cases) do
    Enum.reduce(
      cases,
      %{"<£10k" => 0, "£10k-£100k" => 0, ">£100k" => 0, "No fine" => 0},
      fn case_data, acc ->
        fine = case_data.offence_fine

        cond do
          is_nil(fine) ->
            Map.update(acc, "No fine", 1, &(&1 + 1))

          Decimal.compare(fine, Decimal.new(10_000)) == :lt ->
            Map.update(acc, "<£10k", 1, &(&1 + 1))

          Decimal.compare(fine, Decimal.new(100_000)) in [:lt, :eq] ->
            Map.update(acc, "£10k-£100k", 1, &(&1 + 1))

          true ->
            Map.update(acc, ">£100k", 1, &(&1 + 1))
        end
      end
    )
  end

  defp notice_type_distribution(notices) do
    Enum.reduce(notices, %{}, fn notice_data, acc ->
      type = notice_data.offence_action_type || "Unknown"
      Map.update(acc, type, 1, &(&1 + 1))
    end)
  end
end
