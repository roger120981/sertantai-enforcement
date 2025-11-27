defmodule EhsEnforcement.Scraping.Hse.NoticeScraper do
  @moduledoc """
  HSE notice scraper module.
  Handles scraping of HSE enforcement notice data from the HSE website with rate limiting.

  The `get_hse_notices/2` function retrieves a list of HSE notices based on the specified page number and country.

  The `get_notice_details/1` function retrieves the details of a specific HSE notice based on the notice number.

  The `get_notice_breaches/1` function retrieves the breaches associated with a specific HSE notice based on the notice number.

  All functions include ethical rate limiting to respect HSE website resources.
  """

  require Logger
  alias EhsEnforcement.Scraping.RateLimiter

  def get_hse_notices(page_number: page_number, country: country) do
    base_url = ~s|https://resources.hse.gov.uk|

    # Build URL based on country filter
    # HSE website doesn't recognize "All" as a valid country value
    # So we omit the country filter parameters entirely when "All" is selected
    url =
      if country == "All" do
        # No country filter - returns all notices
        base_url <> ~s|/notices/notices/notice_list.asp?PN=#{page_number}&ST=N&SO=DNIS|
      else
        # Filter by specific country (England, Scotland, Wales)
        encoded_country = URI.encode_www_form(country)

        base_url <>
          ~s|/notices/notices/notice_list.asp?PN=#{page_number}&ST=N&CO=,AND&SN=F&EO==&SF=CTR&SV=#{encoded_country}&SO=DNIS|
      end

    Logger.debug("Fetching HSE notices for #{country}, page #{page_number}")

    case RateLimiter.rate_limited_request(url) do
      {:ok, body} ->
        body
        |> parse_tr()
        |> extract_td()
        |> extract_notices(country)

      {:error, reason} ->
        Logger.error(
          "Failed to fetch HSE notices for #{country}, page #{page_number}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  def get_notice_details(%{notice_number: notice_number}), do: get_notice_details(notice_number)

  def get_notice_details(notice_number) do
    base_url = ~s|https://resources.hse.gov.uk|
    encoded_notice_number = URI.encode_www_form(notice_number)
    url = base_url <> ~s|/notices/notices/notice_details.asp?SF=CN&SV=#{encoded_notice_number}|

    Logger.debug("Fetching details for HSE notice #{notice_number}")

    case RateLimiter.rate_limited_request(url) do
      {:ok, body} ->
        body
        |> parse_tr()
        |> extract_td()
        |> extract_notice_details()

      {:error, reason} ->
        Logger.warning("Failed to fetch details for notice #{notice_number}: #{inspect(reason)}")
        # Return empty map on error to avoid breaking the pipeline
        %{}
    end
  end

  def get_notice_breaches(%{notice_number: notice_number}), do: get_notice_breaches(notice_number)

  def get_notice_breaches(notice_number) do
    base_url = ~s|https://resources.hse.gov.uk|
    encoded_notice_number = URI.encode_www_form(notice_number)

    url =
      base_url <>
        ~s|/notices/breach/breach_list.asp?ST=B&SN=F&EO==&SF=NN&SV=#{encoded_notice_number}|

    Logger.debug("Fetching breaches for HSE notice #{notice_number}")

    case RateLimiter.rate_limited_request(url) do
      {:ok, body} ->
        body
        |> parse_tr()
        |> extract_td()
        |> extract_notice_breaches()

      {:error, reason} ->
        Logger.warning("Failed to fetch breaches for notice #{notice_number}: #{inspect(reason)}")
        # Return empty breaches on error
        %{offence_breaches: []}
    end
  end

  defp parse_tr(body) do
    {:ok, document} = Floki.parse_document(body)
    rows = Floki.find(document, "tr")
    rows
  end

  defp extract_td(notices) do
    Enum.reduce(notices, [], fn
      # Match TR elements with ANY attributes (or no attributes)
      # HSE uses <tr class="odd"> and <tr class="even"> for row styling
      {"tr", _, notice}, acc -> [notice | acc]
      _, acc -> acc
    end)
  end

  defp extract_notices(notices, country) do
    Enum.reduce(notices, [], fn
      # Match row with 6 TD elements (HSE notice list structure)
      [
        {"td", _, notice_number_content},
        {"td", _, recipients_name_content},
        {"td", _, notice_type_content},
        {"td", _, issue_date_content},
        {"td", _, local_authority_content},
        {"td", _, sic_content}
      ],
      acc ->
        # Use Floki.text/1 to extract text from any HTML structure
        # This handles nested elements like <span>, <div>, etc.
        [
          %{
            regulator_id: Floki.text(notice_number_content) |> String.trim(),
            offender_name: Floki.text(recipients_name_content) |> String.trim(),
            offence_action_type: Floki.text(notice_type_content) |> String.trim(),
            offence_action_date:
              EhsEnforcement.Utility.iso_date(Floki.text(issue_date_content) |> String.trim()),
            offender_local_authority: Floki.text(local_authority_content) |> String.trim(),
            offender_sic: Floki.text(sic_content) |> String.trim(),
            offender_country: country
          }
          | acc
        ]

      _, acc ->
        acc
    end)
  end

  defp extract_notice_details(notice_details) do
    Enum.reduce(notice_details, %{}, fn
      # Handle 2-column rows (label + value)
      [
        {"td", _, label_content},
        {"td", _, value_content}
      ],
      acc ->
        label = Floki.text(label_content) |> String.trim()
        value = Floki.text(value_content) |> String.trim()

        case label do
          "Description" ->
            Map.put(acc, :offence_description, value)

          "Main Activity" ->
            Map.put(acc, :offender_main_activity, value)

          "Industry" ->
            Map.put(acc, :offender_industry, value)

          "Result" ->
            Map.put(acc, :offence_result, value)

          _ ->
            acc
        end

      # Handle 4-column rows (2 label-value pairs)
      [
        {"td", _, label1_content},
        {"td", _, value1_content},
        {"td", _, label2_content},
        {"td", _, value2_content}
      ],
      acc ->
        label1 = Floki.text(label1_content) |> String.trim()
        value1 = Floki.text(value1_content) |> String.trim()
        label2 = Floki.text(label2_content) |> String.trim()
        value2 = Floki.text(value2_content) |> String.trim()

        acc =
          case label1 do
            "Compliance Date" ->
              Map.put(acc, :offence_compliance_date, EhsEnforcement.Utility.iso_date(value1))

            _ ->
              acc
          end

        acc =
          case label2 do
            "HSE Directorate" ->
              Map.put(
                acc,
                :regulator_function,
                EhsEnforcement.Utility.upcase_first_from_upcase_phrase(value2)
              )

            "Revised Compliance Date" ->
              Map.put(
                acc,
                :offence_revised_compliance_date,
                EhsEnforcement.Utility.iso_date(value2)
              )

            _ ->
              acc
          end

        acc

      _notice, acc ->
        acc
    end)
  end

  defp extract_notice_breaches(notice_breaches) do
    Enum.reduce(notice_breaches, [], fn
      [
        {"td", _, _},
        {"td", _, _},
        {"td", _, _},
        {"td", _, breach_content},
        {_, _, _}
      ],
      acc ->
        breach_text = Floki.text(breach_content) |> String.trim()
        [breach_text | acc]

      _breach, acc ->
        acc
    end)
    |> (&Map.put(%{}, :offence_breaches, &1)).()
  end
end
