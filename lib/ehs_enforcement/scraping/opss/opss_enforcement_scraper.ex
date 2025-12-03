defmodule EhsEnforcement.Scraping.Opss.OpssEnforcementScraper do
  @moduledoc """
  Office for Product Safety and Standards (OPSS) enforcement action scraper.

  Scrapes enforcement actions from GOV.UK:
  https://www.gov.uk/government/publications/opss-enforcement-actions

  ## Enforcement Types

  - **Notices**: Compliance, Stop, Prohibition, Withdrawal, Recall, Seizure
  - **Prosecutions**: Criminal convictions with fines, costs, confiscation orders

  ## Data Sources

  - HTML reports: 2022 - Present (bi-annual)
  - PDF reports: 2020 - 2022 (historical)

  ## Categories

  - Construction Products
  - Environmental Protection (Ecodesign)
  - Product Safety (toys, electronics, PPE)
  - Timber (illegal logging)
  """

  require Logger

  @base_url "https://www.gov.uk/government/publications/opss-enforcement-actions"

  # Report periods available as HTML (oldest to newest)
  @html_periods [
    "opss-enforcement-actions-1-april-2022-to-30-september-2022",
    "opss-enforcement-actions-1-october-to-2022-to-31-march-2023",
    "opss-enforcement-actions-1-april-2023-to-30-june-2023",
    "opss-enforcement-actions-january-2024",
    "opss-enforcement-actions-1-april-2024-to-30-september-2024",
    "opss-enforcement-actions-1-october-2024-to-31-march-2025",
    "opss-enforcement-actions-1-april-2025-to-30-september-2025"
  ]

  @max_retries 3
  @retry_delay_ms 1000
  @rate_limit_delay_ms 2000

  defmodule ScrapedAction do
    @moduledoc "Struct representing a scraped OPSS enforcement action"

    @derive Jason.Encoder
    defstruct [
      :business_name,
      :action_type,
      :action_date,
      :category,
      :products,
      :breached_regulations,
      :detail,
      # Prosecution-specific fields
      :fine,
      :costs,
      :confiscation,
      :court,
      :imprisonment,
      # Metadata
      :period,
      :scrape_timestamp
    ]
  end

  @doc """
  Scrape all OPSS enforcement actions from available HTML reports.

  Returns {:ok, [%ScrapedAction{}]} or {:error, reason}
  """
  def scrape_all(opts \\ []) do
    timestamp = DateTime.utc_now()
    periods = Keyword.get(opts, :periods, @html_periods)

    Logger.info("OPSS: Scraping #{length(periods)} report periods")

    {actions, errors} =
      periods
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {period, index}, {actions_acc, errors_acc} ->
        # Rate limiting: wait between requests (skip delay for first request)
        if index > 0 do
          Process.sleep(@rate_limit_delay_ms)
        end

        case scrape_period(period, timestamp) do
          {:ok, period_actions} ->
            Logger.debug("OPSS: Scraped #{length(period_actions)} actions from #{period}")
            {actions_acc ++ period_actions, errors_acc}

          {:error, reason} ->
            Logger.warning("OPSS: Failed to scrape #{period}: #{inspect(reason)}")
            {actions_acc, [{period, reason} | errors_acc]}
        end
      end)

    Logger.info("OPSS: Successfully scraped #{length(actions)} enforcement actions")

    if errors == [] do
      {:ok, actions}
    else
      {:ok, actions, errors: Enum.reverse(errors)}
    end
  end

  @doc """
  Scrape enforcement actions from a specific report period.

  Returns {:ok, [%ScrapedAction{}]} or {:error, reason}
  """
  def scrape_period(period, timestamp \\ DateTime.utc_now()) do
    url = "#{@base_url}/#{period}"
    Logger.debug("OPSS: Fetching enforcement actions from #{url}")

    case fetch_with_retry(url, @max_retries) do
      {:ok, html} ->
        actions =
          html
          |> parse_enforcement_page(timestamp)
          |> Enum.map(&Map.put(&1, :period, period))

        {:ok, actions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parse enforcement actions from HTML content.

  This function is public for testing purposes with fixtures.

  ## Parameters
  - html: Raw HTML string from the OPSS enforcement page
  - timestamp: DateTime when scraping occurred

  ## Returns
  List of %ScrapedAction{} structs
  """
  def parse_enforcement_page(html, timestamp) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        # Find the govspeak content div
        govspeak = Floki.find(document, ".govspeak, div.govspeak")

        if Enum.empty?(govspeak) do
          []
        else
          parse_govspeak_content(govspeak, timestamp)
        end

      {:error, _reason} ->
        []
    end
  end

  defp parse_govspeak_content(govspeak, timestamp) do
    # Get the children of the govspeak div
    children =
      govspeak
      |> List.first()
      |> elem(2)

    # Process children to build actions
    parse_children(children, nil, nil, [], timestamp)
  end

  defp parse_children([], _current_category, _current_business, actions, _timestamp) do
    Enum.reverse(actions)
  end

  defp parse_children([child | rest], current_category, current_business, actions, timestamp) do
    case child do
      # H2 - Category header
      {"h2", _attrs, content} ->
        category_text = Floki.text(content) |> String.trim()
        category = extract_category(category_text)
        parse_children(rest, category, nil, actions, timestamp)

      # H3 - Business header
      {"h3", _attrs, content} ->
        business_text = Floki.text(content) |> String.trim()
        business_name = extract_business_name(business_text)

        # Collect all content until next h2 or h3
        {business_content, remaining} = collect_business_content(rest)

        # Parse the business action
        action =
          parse_business_action(current_category, business_name, business_content, timestamp)

        parse_children(remaining, current_category, business_name, [action | actions], timestamp)

      # Skip other elements at this level
      _ ->
        parse_children(rest, current_category, current_business, actions, timestamp)
    end
  end

  defp collect_business_content(children) do
    collect_business_content(children, [])
  end

  defp collect_business_content([], acc) do
    {Enum.reverse(acc), []}
  end

  defp collect_business_content([{"h2", _, _} = h2 | rest], acc) do
    # Stop at next h2
    {Enum.reverse(acc), [h2 | rest]}
  end

  defp collect_business_content([{"h3", _, _} = h3 | rest], acc) do
    # Stop at next h3
    {Enum.reverse(acc), [h3 | rest]}
  end

  defp collect_business_content([child | rest], acc) do
    collect_business_content(rest, [child | acc])
  end

  defp extract_business_name(heading) do
    # Remove "Business: " prefix if present
    heading
    |> String.replace(~r/^Business:\s*/i, "")
    |> String.trim()
  end

  defp parse_business_action(category, business_name, content_elements, timestamp) do
    # Parse h4 sections to extract fields
    fields = extract_fields_from_elements(content_elements)

    action_taken = Map.get(fields, "action taken", "")
    action_type = determine_action_type(action_taken)
    action_date = extract_date(action_taken)

    products = Map.get(fields, "products", Map.get(fields, "product", ""))
    breached_regs = Map.get(fields, "breached regulation details", "")
    detail = Map.get(fields, "detail", "")

    # Extract prosecution-specific fields if applicable
    {fine, costs, confiscation, court, imprisonment} =
      if is_prosecution?(action_type) do
        extract_prosecution_details(action_taken <> " " <> detail)
      else
        {nil, nil, nil, nil, nil}
      end

    %ScrapedAction{
      business_name: business_name,
      action_type: action_type,
      action_date: action_date,
      category: category,
      products: clean_text(products),
      breached_regulations: clean_text(breached_regs),
      detail: clean_text(detail),
      fine: fine,
      costs: costs,
      confiscation: confiscation,
      court: court,
      imprisonment: imprisonment,
      scrape_timestamp: timestamp
    }
  end

  defp extract_fields_from_elements(elements) do
    extract_fields_from_elements(elements, nil, %{})
  end

  defp extract_fields_from_elements([], _current_field, fields) do
    fields
  end

  defp extract_fields_from_elements([elem | rest], current_field, fields) do
    case elem do
      {"h4", _attrs, content} ->
        # New field header
        field_name =
          Floki.text(content)
          |> String.trim()
          |> String.replace(":", "")
          |> String.downcase()

        extract_fields_from_elements(rest, field_name, fields)

      {"p", _attrs, _content} when not is_nil(current_field) ->
        # Add paragraph content to current field
        text = Floki.text([elem]) |> String.trim()
        existing = Map.get(fields, current_field, "")

        new_value =
          if existing == "" do
            text
          else
            existing <> " " <> text
          end

        extract_fields_from_elements(
          rest,
          current_field,
          Map.put(fields, current_field, new_value)
        )

      {"ul", _attrs, items} when not is_nil(current_field) ->
        # Add list items to current field
        list_text =
          items
          |> Enum.map(fn item -> Floki.text([item]) |> String.trim() end)
          |> Enum.join(", ")

        existing = Map.get(fields, current_field, "")

        new_value =
          if existing == "" do
            list_text
          else
            existing <> " " <> list_text
          end

        extract_fields_from_elements(
          rest,
          current_field,
          Map.put(fields, current_field, new_value)
        )

      {"ol", _attrs, items} when not is_nil(current_field) ->
        # Add ordered list items to current field
        list_text =
          items
          |> Enum.with_index(1)
          |> Enum.map(fn {item, idx} ->
            "#{idx}. " <> (Floki.text([item]) |> String.trim())
          end)
          |> Enum.join(" ")

        existing = Map.get(fields, current_field, "")

        new_value =
          if existing == "" do
            list_text
          else
            existing <> " " <> list_text
          end

        extract_fields_from_elements(
          rest,
          current_field,
          Map.put(fields, current_field, new_value)
        )

      _ ->
        extract_fields_from_elements(rest, current_field, fields)
    end
  end

  defp clean_text(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp clean_text(_), do: ""

  @doc """
  Determine the action type from the "Action taken" text.
  """
  def determine_action_type(text) do
    cond do
      String.contains?(text, "Prohibition Notice") -> "Prohibition Notice"
      String.contains?(text, "Stop Notice") -> "Stop Notice"
      String.contains?(text, "Recall Notice") -> "Recall Notice"
      String.contains?(text, "Withdrawal Notice") -> "Withdrawal Notice"
      String.contains?(text, "Compliance Notice") -> "Compliance Notice"
      String.contains?(text, "Seizure Notice") -> "Seizure Notice"
      String.contains?(text, "Prosecution") -> "Prosecution"
      true -> "Unknown"
    end
  end

  @doc """
  Check if an action type is a prosecution (criminal case).
  """
  def is_prosecution?(action_type) do
    action_type == "Prosecution"
  end

  @doc """
  Extract a date from text containing "dated DD Month YYYY" or "on DD Month YYYY".
  """
  def extract_date(text) do
    patterns = [
      ~r/dated\s+(\d{1,2})\s+(\w+)\s+(\d{4})/i,
      ~r/on\s+(\d{1,2})\s+(\w+)\s+(\d{4})/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [_, day, month, year] ->
          month_num = month_to_number(month)

          if month_num do
            case Date.new(
                   String.to_integer(year),
                   month_num,
                   String.to_integer(day)
                 ) do
              {:ok, date} -> date
              _ -> nil
            end
          else
            nil
          end

        nil ->
          nil
      end
    end)
  end

  defp month_to_number(month) do
    months = %{
      "january" => 1,
      "february" => 2,
      "march" => 3,
      "april" => 4,
      "may" => 5,
      "june" => 6,
      "july" => 7,
      "august" => 8,
      "september" => 9,
      "october" => 10,
      "november" => 11,
      "december" => 12
    }

    Map.get(months, String.downcase(month))
  end

  @doc """
  Extract a monetary value (fine, costs, confiscation) from text.
  """
  def extract_monetary_value(text, type) do
    pattern =
      case type do
        :fine ->
          ~r/fine\s+(?:of|in the amount of)\s+£([\d,]+(?:\.\d{2})?)/i

        :costs ->
          ~r/costs\s+(?:of|in the sum of|in the amount of)\s+£([\d,]+(?:\.\d{2})?)/i

        :confiscation ->
          ~r/confiscation\s+(?:order\s+)?(?:for\s+)?(?:the\s+)?(?:amount\s+of\s+)?£([\d,]+(?:\.\d{2})?)/i
      end

    case Regex.run(pattern, text) do
      [_, amount_str] ->
        amount_str
        |> String.replace(",", "")
        |> parse_number()

      nil ->
        nil
    end
  end

  defp parse_number(str) do
    if String.contains?(str, ".") do
      case Float.parse(str) do
        {num, _} -> num
        :error -> nil
      end
    else
      case Integer.parse(str) do
        {num, _} -> num
        :error -> nil
      end
    end
  end

  defp extract_prosecution_details(text) do
    fine = extract_monetary_value(text, :fine)
    costs = extract_monetary_value(text, :costs)
    confiscation = extract_monetary_value(text, :confiscation)

    court =
      case Regex.run(~r/([\w\s]+(?:Crown|Magistrates'?)\s*Court)/i, text) do
        [_, court_name] -> String.trim(court_name)
        nil -> nil
      end

    imprisonment =
      case Regex.run(~r/(\d+)\s*months?\s*(?:suspended|imprisonment)/i, text) do
        [_, months] -> "#{months} months"
        nil -> nil
      end

    {fine, costs, confiscation, court, imprisonment}
  end

  @doc """
  Extract category name from heading, removing date suffix.
  """
  def extract_category(heading) do
    # Remove date patterns like "– October 2024" or "- August 2024"
    # The en-dash (–) is Unicode U+2013, regular dash is U+002D
    heading
    |> String.replace(~r/\s*[\x{2013}\x{2014}\-–—]\s*\w+\s+\d{4}\s*$/u, "")
    |> String.trim()
  end

  # HTTP fetching with retry

  defp fetch_with_retry(url, retries) do
    headers = [
      {"User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"}
    ]

    case Req.get(url, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, {:not_found, url}}

      {:ok, %{status: status}} when status >= 500 ->
        Logger.warning("OPSS: Server error HTTP #{status} for #{url}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1)
        else
          {:error, {:http_error, status}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("OPSS: Network error for #{url}: #{inspect(reason)}")

        if retries > 0 do
          Process.sleep(@retry_delay_ms)
          fetch_with_retry(url, retries - 1)
        else
          {:error, {:network_error, reason}}
        end
    end
  end

  @doc """
  Get available HTML report periods.
  """
  def available_periods, do: @html_periods
end
