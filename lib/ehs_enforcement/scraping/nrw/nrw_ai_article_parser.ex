defmodule EhsEnforcement.Scraping.Nrw.NrwAiArticleParser do
  @moduledoc """
  AI-powered parser for NRW news articles.

  Uses LLM to extract structured enforcement case data from unstructured
  narrative text. This approach handles:
  - Variable phrasing ("fined £10,000" vs "ordered to pay £10,000")
  - Multi-defendant articles with correct fine attribution
  - Novel article formats without regex pattern updates
  - Complex sentences like "Both were required to pay £2,000 surcharge each"

  ## Usage

      alias EhsEnforcement.Scraping.Nrw.{NrwNewsScraper, NrwAiArticleParser}

      {:ok, article} = NrwNewsScraper.fetch_and_parse_article(url)
      {:ok, parsed_cases} = NrwAiArticleParser.parse_article(article)

  ## Configuration

  Uses the same AI client configuration as the enrichment service:

      config :ehs_enforcement, :ai_enrichment,
        provider: :runpod,
        runpod_api_key: System.get_env("RUNPOD_API_KEY"),
        runpod_endpoint: System.get_env("RUNPOD_ENDPOINT")
  """

  alias EhsEnforcement.AI.Client
  alias EhsEnforcement.Scraping.Nrw.NrwNewsScraper.ScrapedArticle

  require Logger

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

  @doc """
  Parse a scraped article using AI to extract enforcement case details.

  Returns {:ok, [%ParsedCase{}]} (may return multiple cases from one article)
  or {:error, reason}
  """
  def parse_article(%ScrapedArticle{} = article) do
    Logger.info("NRW AI: Parsing article: #{article.title}")

    client = Client.get_client()
    messages = build_extraction_messages(article)

    case client.complete(messages, json_mode: true, temperature: 0.1, max_tokens: 4096) do
      {:ok, %{content: content, model: model, latency_ms: latency}} ->
        Logger.debug("NRW AI: Response received in #{latency}ms using #{model}")
        parse_ai_response(content, article)

      {:error, reason} = error ->
        Logger.error("NRW AI: Failed to parse article: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Parse multiple articles in batch.

  Returns {:ok, [%ParsedCase{}]} with all cases from all articles.
  """
  def parse_articles(articles) when is_list(articles) do
    results =
      Enum.map(articles, fn article ->
        case parse_article(article) do
          {:ok, cases} ->
            cases

          {:error, reason} ->
            Logger.warning("NRW AI: Skipping article due to error: #{inspect(reason)}")
            []
        end
      end)

    {:ok, List.flatten(results)}
  end

  # Private functions

  defp build_extraction_messages(%ScrapedArticle{} = article) do
    [
      %{
        role: "system",
        content: extraction_system_prompt()
      },
      %{
        role: "user",
        content: """
        Extract all enforcement cases from this Natural Resources Wales (NRW) news article.

        ## Article Details

        **Title**: #{article.title}
        **URL**: #{article.url}
        **Publication Date**: #{format_date(article.publication_date)}

        ## Article Content

        #{article.content}

        ---

        Extract ALL defendants/offenders mentioned with their specific penalties. Return the data in the specified JSON format.
        """
      }
    ]
  end

  defp extraction_system_prompt do
    """
    You are an expert at extracting structured data from UK environmental enforcement news articles.

    Your task is to parse Natural Resources Wales (NRW) prosecution announcements and extract case details for each defendant.

    ## Required Output Format (JSON)

    You MUST respond with valid JSON in this exact structure:

    {
      "cases": [
        {
          "offender_name": "Full name of individual or company",
          "offender_type": "individual" or "company",
          "offender_location": "Location/address if mentioned, or null",
          "hearing_date": "YYYY-MM-DD format or null if not found",
          "fine_amount": <number in GBP or null>,
          "costs_amount": <prosecution costs in GBP or null>,
          "surcharge_amount": <victim surcharge in GBP or null>,
          "total_amount": <total ordered to pay if stated, or null>,
          "poca_amount": <Proceeds of Crime confiscation amount or null>,
          "offence_description": "Brief description of what the offender did wrong",
          "offence_result": "The sentence/outcome including any community orders",
          "legislation": "Legislation breached, e.g. 'Environmental Permitting Regulations 2016'"
        }
      ],
      "extraction_notes": "Any relevant notes about the extraction, e.g. 'Multiple defendants shared some penalties'"
    }

    ## Extraction Rules

    1. **Multiple Defendants**: Create a SEPARATE case entry for EACH defendant (individual or company)
    2. **Company Directors**: A company and its director are SEPARATE defendants with separate penalties
    3. **Shared Penalties**: If the article says "Both were required to pay £X each", assign £X to EACH defendant
    4. **Fine vs POCA**: Regular fines go in `fine_amount`; Proceeds of Crime confiscation goes in `poca_amount`
    5. **Costs**: Prosecution costs go in `costs_amount`; victim surcharge goes in `surcharge_amount`
    6. **Dates**: Extract the court/hearing date, NOT the offence date. Format as YYYY-MM-DD
    7. **Company Names**: Include full legal name with Ltd/Limited/PLC suffix
    8. **Individual Names**: Include full name as stated, without age or location suffix
    9. **Null Values**: Use null (not 0) for amounts not mentioned for a specific defendant

    ## Common Patterns

    - "fined £X" → fine_amount: X
    - "ordered to pay £X in costs" → costs_amount: X
    - "victim surcharge of £X" → surcharge_amount: X
    - "confiscation order of £X" / "POCA order" → poca_amount: X
    - "12-month community order" → include in offence_result
    - "at [Court Name] on [Date]" → extract as hearing_date

    ## Important

    - Return an EMPTY cases array [] if the article is not about enforcement/prosecution
    - Do NOT include journalists, NRW officers, or quoted individuals as defendants
    - Only extract actual defendants who received penalties or court orders
    """
  end

  defp parse_ai_response(content, article) do
    case Jason.decode(content) do
      {:ok, %{"cases" => cases}} when is_list(cases) ->
        parsed_cases =
          cases
          |> Enum.map(fn case_data -> build_parsed_case(case_data, article) end)
          |> Enum.reject(&is_nil/1)

        Logger.info("NRW AI: Extracted #{length(parsed_cases)} cases from article")
        {:ok, parsed_cases}

      {:ok, %{"cases" => nil}} ->
        Logger.warning("NRW AI: No cases found in article")
        {:ok, []}

      {:ok, other} ->
        Logger.error("NRW AI: Unexpected response structure: #{inspect(other)}")
        {:error, {:invalid_response_structure, other}}

      {:error, reason} ->
        Logger.error("NRW AI: Failed to parse JSON response: #{inspect(reason)}")
        Logger.debug("NRW AI: Raw content: #{content}")
        {:error, {:json_parse_error, reason}}
    end
  end

  defp build_parsed_case(case_data, article) when is_map(case_data) do
    # Skip if no offender name
    offender_name = case_data["offender_name"]

    if is_nil(offender_name) or offender_name == "" do
      nil
    else
      %ParsedCase{
        offender_name: offender_name,
        offender_type: parse_offender_type(case_data["offender_type"]),
        offender_location: case_data["offender_location"],
        hearing_date: parse_date(case_data["hearing_date"]),
        fine_amount: parse_decimal(case_data["fine_amount"]),
        costs_amount: parse_decimal(case_data["costs_amount"]),
        surcharge_amount: parse_decimal(case_data["surcharge_amount"]),
        total_amount: parse_decimal(case_data["total_amount"]),
        poca_amount: parse_decimal(case_data["poca_amount"]),
        offence_description: case_data["offence_description"],
        offence_result: case_data["offence_result"],
        legislation: case_data["legislation"],
        article_url: article.url,
        article_title: article.title,
        article_date: article.publication_date
      }
    end
  end

  defp build_parsed_case(_, _), do: nil

  defp parse_offender_type("company"), do: :company
  defp parse_offender_type("individual"), do: :individual
  defp parse_offender_type(_), do: :unknown

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        date

      {:error, _} ->
        # Try common UK date formats
        parse_uk_date(date_string)
    end
  end

  defp parse_date(_), do: nil

  defp parse_uk_date(date_string) do
    # Try "14 October 2025" format
    case Regex.run(
           ~r/(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})/i,
           date_string
         ) do
      [_, day, month, year] ->
        month_num = month_to_number(month)

        case Date.new(String.to_integer(year), month_num, String.to_integer(day)) do
          {:ok, date} -> date
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp month_to_number(month) do
    month
    |> String.downcase()
    |> case do
      "january" -> 1
      "february" -> 2
      "march" -> 3
      "april" -> 4
      "may" -> 5
      "june" -> 6
      "july" -> 7
      "august" -> 8
      "september" -> 9
      "october" -> 10
      "november" -> 11
      "december" -> 12
      _ -> 1
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp parse_decimal(value) when is_float(value), do: Decimal.from_float(value)

  defp parse_decimal(value) when is_binary(value) do
    value
    |> String.replace(",", "")
    |> String.replace("£", "")
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

  defp parse_decimal(_), do: nil

  defp format_date(nil), do: "Not specified"
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%d %B %Y")
  defp format_date(date), do: to_string(date)
end
