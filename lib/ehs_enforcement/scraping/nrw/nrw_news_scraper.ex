defmodule EhsEnforcement.Scraping.Nrw.NrwNewsScraper do
  @moduledoc """
  NRW news/press release scraping service.

  Scrapes enforcement data from Natural Resources Wales news articles:
  - Prosecutions (court cases with fines)
  - Civil sanctions (FMP, VMP, Undertakings)

  Data source: https://naturalresources.wales/about-us/news-and-blogs/news/

  Unlike SEPA (structured tables), NRW publishes enforcement via news articles.
  This scraper:
  1. Fetches the news listing page
  2. Identifies enforcement-related articles by URL slug patterns
  3. Fetches and parses individual articles
  """

  require Logger

  @news_base_url "https://naturalresources.wales/about-us/news-and-blogs/news/?lang=en"
  @max_retries 3
  @retry_delay_ms 1000

  # URL slug patterns that indicate enforcement articles
  @enforcement_slug_patterns [
    ~r/-fined-/i,
    ~r/-prosecuted-/i,
    ~r/-sentenced-/i,
    ~r/-prosecution/i,
    ~r/-guilty-/i,
    ~r/-convicted-/i,
    ~r/-illegal-/i,
    ~r/-court-/i,
    ~r/-ordered-to-pay-/i
  ]

  defmodule ScrapedArticle do
    @moduledoc "Struct representing a scraped NRW news article"

    @derive Jason.Encoder
    defstruct [
      :url,
      :slug,
      :title,
      :publication_date,
      :content,
      :scrape_timestamp
    ]
  end

  @doc """
  Scrape all enforcement-related news articles from NRW.

  Returns {:ok, [%ScrapedArticle{}]} or {:error, reason}

  Options:
  - :limit - Maximum number of articles to fetch (default: 100)
  - :since_date - Only fetch articles after this date
  """
  def scrape_all(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    since_date = Keyword.get(opts, :since_date)

    Logger.info("NRW: Scraping enforcement news articles", limit: limit)

    with {:ok, article_urls} <- fetch_enforcement_article_urls(limit),
         {:ok, articles} <- fetch_articles(article_urls, since_date) do
      Logger.info("NRW: Successfully scraped #{length(articles)} enforcement articles")
      {:ok, articles}
    else
      {:error, reason} = error ->
        Logger.error("NRW: Failed to scrape news: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Fetch the news listing page and extract enforcement article URLs.

  Returns {:ok, [url]} or {:error, reason}
  """
  def fetch_enforcement_article_urls(limit \\ 100) do
    Logger.debug("NRW: Fetching news listing page")

    case fetch_page_html(@news_base_url) do
      {:ok, html} ->
        urls = extract_enforcement_urls(html, limit)
        Logger.info("NRW: Found #{length(urls)} potential enforcement articles")
        {:ok, urls}

      {:error, reason} ->
        {:error, {:fetch_error, reason}}
    end
  end

  @doc """
  Fetch and parse multiple article pages.

  Returns {:ok, [%ScrapedArticle{}]} or {:error, reason}
  """
  def fetch_articles(urls, since_date \\ nil) do
    timestamp = DateTime.utc_now()

    articles =
      urls
      |> Enum.map(fn url ->
        case fetch_and_parse_article(url, timestamp) do
          {:ok, article} ->
            if since_date && article.publication_date do
              if Date.compare(article.publication_date, since_date) == :gt do
                article
              else
                nil
              end
            else
              article
            end

          {:error, reason} ->
            Logger.warning("NRW: Failed to fetch article #{url}: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, articles}
  end

  @doc """
  Fetch and parse a single article page.

  Returns {:ok, %ScrapedArticle{}} or {:error, reason}
  """
  def fetch_and_parse_article(url, timestamp \\ nil) do
    timestamp = timestamp || DateTime.utc_now()
    # Encode any non-ASCII characters in the URL (e.g., Welsh ŵ, â, ê)
    encoded_url = encode_url_path(url)

    case fetch_page_html(encoded_url) do
      {:ok, html} ->
        # Store original URL for reference, but use encoded for fetching
        parse_article(html, url, timestamp)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private Functions

  defp fetch_page_html(url, retries \\ @max_retries) do
    Logger.debug("NRW: Fetching #{url}")

    # Use headers to set language preference and avoid splash page redirect
    headers = [
      {"Accept-Language", "en-GB,en;q=0.9"},
      {"Cookie", "lang=en"}
    ]

    case Req.get(url, receive_timeout: 30_000, redirect: true, max_redirects: 5, headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        if retries > 0 do
          Logger.warning("NRW: Got status #{status}, retrying...")
          Process.sleep(@retry_delay_ms)
          fetch_page_html(url, retries - 1)
        else
          {:error, {:http_error, status}}
        end

      {:error, reason} ->
        if retries > 0 do
          Logger.warning("NRW: Request failed: #{inspect(reason)}, retrying...")
          Process.sleep(@retry_delay_ms)
          fetch_page_html(url, retries - 1)
        else
          {:error, {:request_error, reason}}
        end
    end
  end

  defp extract_enforcement_urls(html, limit) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        document
        |> Floki.find("a[href*='/about-us/news-and-blogs/news/']")
        |> Enum.map(fn element ->
          Floki.attribute(element, "href") |> List.first()
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.filter(&is_enforcement_url?/1)
        |> Enum.map(&normalize_url/1)
        |> Enum.take(limit)

      {:error, _reason} ->
        []
    end
  end

  defp is_enforcement_url?(url) when is_binary(url) do
    Enum.any?(@enforcement_slug_patterns, fn pattern ->
      Regex.match?(pattern, url)
    end)
  end

  defp is_enforcement_url?(_), do: false

  defp normalize_url(url) do
    cond do
      String.starts_with?(url, "http") ->
        url

      String.starts_with?(url, "/") ->
        "https://naturalresources.wales" <> url

      true ->
        "https://naturalresources.wales/" <> url
    end
    |> ensure_lang_param()
    |> encode_url_path()
  end

  # Encode non-ASCII characters in URL path (e.g., Welsh characters like ŵ, â, ê)
  # while preserving already-valid URL characters
  defp encode_url_path(url) do
    uri = URI.parse(url)

    encoded_path =
      uri.path
      |> String.graphemes()
      |> Enum.map(fn char ->
        if ascii_safe_url_char?(char) do
          char
        else
          URI.encode(char)
        end
      end)
      |> Enum.join()

    %{uri | path: encoded_path}
    |> URI.to_string()
  end

  # Check if character is safe for URL paths (ASCII subset)
  defp ascii_safe_url_char?(char) when byte_size(char) == 1 do
    <<byte>> = char
    # Allow: A-Z, a-z, 0-9, -, _, ., ~, /
    (byte >= ?A and byte <= ?Z) or
      (byte >= ?a and byte <= ?z) or
      (byte >= ?0 and byte <= ?9) or
      byte in [?-, ?_, ?., ?~, ?/]
  end

  defp ascii_safe_url_char?(_), do: false

  defp ensure_lang_param(url) do
    if String.contains?(url, "lang=") do
      url
    else
      if String.contains?(url, "?") do
        url <> "&lang=en"
      else
        url <> "?lang=en"
      end
    end
  end

  defp parse_article(html, url, timestamp) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        slug = extract_slug(url)
        title = extract_title(document)
        publication_date = extract_publication_date(document)
        content = extract_content(document)

        article = %ScrapedArticle{
          url: url,
          slug: slug,
          title: title,
          publication_date: publication_date,
          content: content,
          scrape_timestamp: timestamp
        }

        {:ok, article}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp extract_slug(url) do
    url
    |> URI.parse()
    |> Map.get(:path, "")
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
    |> List.last()
  end

  defp extract_title(document) do
    document
    |> Floki.find("h1")
    |> Floki.text()
    |> String.trim()
    |> case do
      "" -> nil
      title -> title
    end
  end

  defp extract_publication_date(document) do
    # NRW typically shows dates in format "10 Oct 2024" or similar
    # Look in common date locations
    date_text =
      document
      |> Floki.find("time, .date, .publication-date, .news-date, article header")
      |> Floki.text()
      |> String.trim()

    # Also check the main content for date patterns
    content_date =
      document
      |> Floki.find("article, .content, main")
      |> Floki.text()
      |> extract_first_date()

    # Try to parse date from found text
    cond do
      date_text != "" -> parse_date_text(date_text)
      content_date -> content_date
      true -> nil
    end
  end

  defp extract_first_date(text) do
    # Match patterns like "10 Oct 2024", "21 March 2024"
    case Regex.run(
           ~r/(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{4})/i,
           text
         ) do
      [_, day, month, year] ->
        parse_date_text("#{day} #{month} #{year}")

      _ ->
        nil
    end
  end

  defp parse_date_text(text) do
    alias EhsEnforcement.Scraping.Shared.DateParser
    DateParser.parse_date(text)
  end

  defp extract_content(document) do
    # Extract main article content, excluding navigation, headers, footers
    document
    |> Floki.find("article, .article-content, .content, main")
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
