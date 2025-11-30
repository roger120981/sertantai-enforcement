defmodule EhsEnforcement.Scraping.Nrw.NrwArticleParser do
  @moduledoc """
  Parses NRW news article content to extract enforcement case details.

  NRW articles are unstructured narrative text, so this module uses
  regex patterns to extract:
  - Offender names (individuals and companies)
  - Fine amounts
  - Costs and surcharges
  - Court dates
  - Offence descriptions
  - Legislation references

  Some articles contain multiple cases (e.g., "NRW secures three major prosecutions"),
  which are split into separate case records.
  """

  require Logger

  alias EhsEnforcement.Scraping.Nrw.NrwNewsScraper.ScrapedArticle
  alias EhsEnforcement.Scraping.Shared.DateParser

  defmodule ParsedCase do
    @moduledoc "Struct representing a parsed enforcement case from an NRW article"

    @derive Jason.Encoder
    defstruct [
      :offender_name,
      :offender_type,
      :offender_location,
      :hearing_date,
      :fine_amount,
      :costs_amount,
      :surcharge_amount,
      :total_amount,
      :poca_amount,
      :offence_description,
      :offence_result,
      :legislation,
      :article_url,
      :article_title,
      :article_date
    ]
  end

  # Regex patterns for extraction
  @patterns %{
    # Match person names with age: "John Smith, 65" or "John Smith (65)"
    person_with_age:
      ~r/([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,3}),?\s*(?:\(?\d{1,2}\)?|aged?\s+\d{1,2})/,

    # Match company names ending in Ltd, Limited, PLC, etc.
    # Use word boundary and non-greedy matching to avoid capturing preceding text
    company:
      ~r/\b([A-Z][A-Za-z0-9]+(?:\s+(?:and|&|[A-Za-z0-9]+))*?\s+(?:Ltd|Limited|PLC|plc|LLP|Inc|Company|Co\s+Limited|Co\.))/,

    # Match "of [Location]" or "from [Location]"
    location: ~r/(?:of|from)\s+([A-Z][a-z]+(?:[\s,]+[A-Z][a-z]+)*)/,

    # Match fine amounts: "fined £2,000" or "fine of £20,000"
    fine: ~r/fined?\s+(?:a\s+total\s+of\s+)?£([\d,]+)/i,

    # Match costs: "costs of £5,000" or "pay £160 in costs"
    costs: ~r/(?:costs?\s+(?:of\s+)?£([\d,]+)|pay\s+£([\d,]+)\s+(?:in\s+)?costs?)/i,

    # Match victim surcharge: "victim surcharge of £800" or "£114 victim surcharge"
    surcharge:
      ~r/(?:victim\s+)?surcharge\s+(?:of\s+)?£([\d,]+)|£([\d,]+)\s+(?:victim\s+)?surcharge/i,

    # Match POCA confiscation orders
    poca: ~r/(?:POCA|Proceeds\s+of\s+Crime|confiscation\s+order)\s+.*?£([\d,]+)/i,

    # Match total ordered to pay
    total_ordered: ~r/ordered\s+to\s+pay\s+(?:a\s+(?:combined\s+)?total\s+of\s+)?£([\d,]+)/i,

    # Match court dates: "at Swansea Crown Court on 5 January 2024"
    court_date:
      ~r/(?:at|before)\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\s+(?:Magistrates'?\s+Court|Crown\s+Court)\s+(?:on\s+)?(\d{1,2}\s+[A-Z][a-z]+\s+\d{4})/i,

    # Match sentencing date: "sentenced on 23 September 2024"
    sentenced_date: ~r/sentenced\s+(?:at\s+.*?\s+)?(?:on\s+)?(\d{1,2}\s+[A-Z][a-z]+\s+\d{4})/i,

    # Match pleaded guilty date
    pleaded_date: ~r/pleaded\s+guilty\s+.*?(\d{1,2}\s+[A-Z][a-z]+\s+\d{4})/i,

    # Common legislation references
    legislation:
      ~r/(Environmental\s+Permitting|Forestry\s+Act|Environmental\s+Protection\s+Act|Water\s+Resources\s+Act|Control\s+of\s+Pollution|Waste\s+(?:England\s+and\s+Wales\s+)?Regulations)/i
  }

  @doc """
  Parse a scraped article to extract enforcement case details.

  Returns {:ok, [%ParsedCase{}]} (may return multiple cases from one article)
  or {:error, reason}
  """
  def parse_article(%ScrapedArticle{} = article) do
    Logger.debug("NRW: Parsing article: #{article.title}")

    content = article.content || ""

    # Check if this is a multi-case article
    cases =
      if is_multi_case_article?(content) do
        parse_multi_case_article(article)
      else
        [parse_single_case(article)]
      end
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&empty_case?/1)

    if Enum.empty?(cases) do
      Logger.warning("NRW: No cases extracted from article: #{article.title}")
      {:ok, []}
    else
      Logger.info("NRW: Extracted #{length(cases)} cases from article")
      {:ok, cases}
    end
  end

  @doc """
  Parse multiple articles and return all extracted cases.

  Returns {:ok, [%ParsedCase{}], errors: [...]} or {:error, reason}
  """
  def parse_articles(articles) when is_list(articles) do
    cases =
      Enum.flat_map(articles, fn article ->
        {:ok, parsed_cases} = parse_article(article)
        parsed_cases
      end)

    {:ok, cases}
  end

  # Private Functions

  defp is_multi_case_article?(content) do
    # Check for patterns indicating multiple cases
    # e.g., numbered lists, multiple distinct names with fines
    fine_matches = Regex.scan(@patterns.fine, content)
    person_matches = Regex.scan(@patterns.person_with_age, content)

    length(fine_matches) > 1 || length(person_matches) > 2
  end

  defp parse_multi_case_article(%ScrapedArticle{} = article) do
    content = article.content || ""

    # Try to split by case markers
    # Look for patterns like numbered sections or distinct name+fine combinations
    case_sections = split_into_case_sections(content)

    if length(case_sections) > 1 do
      Enum.map(case_sections, fn section ->
        parse_case_from_text(section, article)
      end)
    else
      # Fall back to extracting multiple names/fines
      extract_multiple_cases(content, article)
    end
  end

  defp split_into_case_sections(content) do
    # Split on patterns like "Case 1:", numbered lists, or distinct paragraphs with names
    # For now, split on double newlines and filter for case-relevant sections
    content
    |> String.split(~r/\n\n+/)
    |> Enum.filter(fn section ->
      has_offender?(section) && has_financial_penalty?(section)
    end)
    |> case do
      [] -> [content]
      sections -> sections
    end
  end

  defp has_offender?(text) do
    Regex.match?(@patterns.person_with_age, text) ||
      Regex.match?(@patterns.company, text)
  end

  defp has_financial_penalty?(text) do
    Regex.match?(@patterns.fine, text) ||
      Regex.match?(@patterns.total_ordered, text) ||
      Regex.match?(@patterns.poca, text)
  end

  defp extract_multiple_cases(content, article) do
    # Extract all person names with ages
    persons =
      Regex.scan(@patterns.person_with_age, content)
      |> Enum.map(fn [_, name] -> String.trim(name) end)
      |> Enum.reject(&is_legislation_name?/1)
      |> Enum.uniq()

    # Extract all company names
    companies =
      Regex.scan(@patterns.company, content)
      |> Enum.map(fn [_, name] -> String.trim(name) end)
      |> Enum.reject(&is_legislation_name?/1)
      |> Enum.uniq()

    all_offenders = persons ++ companies

    # For each unique offender, try to extract their specific case details
    Enum.map(all_offenders, fn offender_name ->
      extract_case_for_offender(offender_name, content, article)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_case_for_offender(offender_name, content, article) do
    # Find the section of content most relevant to this offender
    # by looking for their name and nearby financial details

    # Create a pattern to find text around this offender's name
    escaped_name = Regex.escape(offender_name)

    case Regex.run(~r/#{escaped_name}.{0,500}/s, content) do
      [relevant_section] ->
        parse_case_from_text(relevant_section, article, offender_name)

      _ ->
        # Fall back to parsing the whole content with this offender
        case_data = parse_case_from_text(content, article)

        if case_data do
          %{case_data | offender_name: offender_name}
        else
          nil
        end
    end
  end

  defp parse_single_case(%ScrapedArticle{} = article) do
    parse_case_from_text(article.content || "", article)
  end

  defp parse_case_from_text(text, article, forced_offender_name \\ nil) do
    offender_name = forced_offender_name || extract_offender_name(text)
    offender_type = determine_offender_type(offender_name, text)
    offender_location = extract_location(text)

    hearing_date = extract_hearing_date(text) || article.publication_date
    fine_amount = extract_amount(@patterns.fine, text)
    costs_amount = extract_costs_amount(text)
    surcharge_amount = extract_surcharge_amount(text)
    poca_amount = extract_amount(@patterns.poca, text)
    total_amount = extract_amount(@patterns.total_ordered, text)

    # Use total if individual amounts not found
    calculated_total =
      if total_amount do
        total_amount
      else
        sum_amounts([fine_amount, costs_amount, surcharge_amount])
      end

    legislation = extract_legislation(text)
    offence_description = extract_offence_description(text)
    offence_result = build_offence_result(text)

    %ParsedCase{
      offender_name: offender_name,
      offender_type: offender_type,
      offender_location: offender_location,
      hearing_date: hearing_date,
      fine_amount: fine_amount,
      costs_amount: costs_amount,
      surcharge_amount: surcharge_amount,
      total_amount: calculated_total,
      poca_amount: poca_amount,
      offence_description: offence_description,
      offence_result: offence_result,
      legislation: legislation,
      article_url: article.url,
      article_title: article.title,
      article_date: article.publication_date
    }
  end

  defp extract_offender_name(text) do
    # Try person first, then company
    # Exclude matches that are legislation names
    case Regex.run(@patterns.person_with_age, text) do
      [_, name] ->
        name = String.trim(name)
        if is_legislation_name?(name), do: nil, else: name

      _ ->
        case Regex.run(@patterns.company, text) do
          [_, name] ->
            name = String.trim(name)
            if is_legislation_name?(name), do: nil, else: name

          _ ->
            nil
        end
    end
  end

  # Check if a name is actually legislation (common false positive)
  defp is_legislation_name?(name) do
    legislation_words = [
      "Act",
      "Regulation",
      "Regulations",
      "Order",
      "Environmental",
      "Protection",
      "Permitting",
      "Forestry",
      "Water",
      "Control",
      "Pollution",
      "Waste"
    ]

    # If the name contains multiple legislation keywords, it's probably not a person/company
    matching_words =
      Enum.count(legislation_words, fn word ->
        String.contains?(name, word)
      end)

    matching_words >= 2
  end

  defp determine_offender_type(name, text) when is_binary(name) do
    cond do
      Regex.match?(~r/Ltd|Limited|PLC|plc|LLP|Company|Co\./i, name) -> :company
      Regex.match?(@patterns.person_with_age, text) -> :individual
      true -> :unknown
    end
  end

  defp determine_offender_type(_, _), do: :unknown

  defp extract_location(text) do
    case Regex.run(@patterns.location, text) do
      [_, location] -> String.trim(location)
      _ -> nil
    end
  end

  defp extract_hearing_date(text) do
    # Try multiple date patterns in order of specificity
    date_string =
      case Regex.run(@patterns.court_date, text) do
        [_, date] ->
          date

        _ ->
          case Regex.run(@patterns.sentenced_date, text) do
            [_, date] ->
              date

            _ ->
              case Regex.run(@patterns.pleaded_date, text) do
                [_, date] -> date
                _ -> nil
              end
          end
      end

    if date_string do
      DateParser.parse_date(date_string)
    else
      nil
    end
  end

  defp extract_amount(pattern, text) do
    case Regex.run(pattern, text) do
      [_, amount] -> parse_currency(amount)
      [_, amount, _] -> parse_currency(amount)
      _ -> nil
    end
  end

  defp extract_costs_amount(text) do
    case Regex.run(@patterns.costs, text) do
      [_, amount, nil] -> parse_currency(amount)
      [_, nil, amount] -> parse_currency(amount)
      [_, amount] -> parse_currency(amount)
      _ -> nil
    end
  end

  defp extract_surcharge_amount(text) do
    case Regex.run(@patterns.surcharge, text) do
      [_, amount, nil] -> parse_currency(amount)
      [_, nil, amount] -> parse_currency(amount)
      [_, amount] -> parse_currency(amount)
      _ -> nil
    end
  end

  defp parse_currency(nil), do: nil

  defp parse_currency(amount_string) do
    amount_string
    |> String.replace(",", "")
    |> String.trim()
    |> case do
      "" ->
        nil

      str ->
        case Decimal.parse(str) do
          {decimal, _} -> decimal
          :error -> nil
        end
    end
  end

  defp sum_amounts(amounts) do
    amounts
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      decimals -> Enum.reduce(decimals, Decimal.new(0), &Decimal.add/2)
    end
  end

  defp extract_legislation(text) do
    Regex.scan(@patterns.legislation, text)
    |> Enum.map(fn [match | _] -> String.trim(match) end)
    |> Enum.uniq()
    |> Enum.join("; ")
    |> case do
      "" -> nil
      legislation -> legislation
    end
  end

  defp extract_offence_description(text) do
    # Look for common offence description patterns
    patterns = [
      ~r/(?:guilty\s+(?:of|to)\s+)([^.]+)/i,
      ~r/(?:convicted\s+(?:of|for)\s+)([^.]+)/i,
      ~r/(?:prosecuted\s+(?:for|after)\s+)([^.]+)/i,
      ~r/(?:fined\s+.*?for\s+)([^.]+)/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [_, description] -> String.trim(description) |> truncate(500)
        _ -> nil
      end
    end)
  end

  defp build_offence_result(text) do
    # Extract the sentencing outcome
    result_patterns = [
      ~r/(fined\s+£[\d,]+[^.]*)/i,
      ~r/(ordered\s+to\s+pay[^.]+)/i,
      ~r/(given\s+a\s+\d+-month\s+community\s+order[^.]*)/i,
      ~r/(sentenced\s+to[^.]+)/i
    ]

    results =
      Enum.flat_map(result_patterns, fn pattern ->
        Regex.scan(pattern, text)
        |> Enum.map(fn [_, match] -> String.trim(match) end)
      end)
      |> Enum.uniq()

    case results do
      [] -> nil
      matches -> Enum.join(matches, "; ") |> truncate(1000)
    end
  end

  defp truncate(nil, _), do: nil

  defp truncate(string, max_length) when byte_size(string) > max_length do
    String.slice(string, 0, max_length - 3) <> "..."
  end

  defp truncate(string, _), do: string

  defp empty_case?(%ParsedCase{offender_name: nil, fine_amount: nil, poca_amount: nil}), do: true
  defp empty_case?(_), do: false
end
