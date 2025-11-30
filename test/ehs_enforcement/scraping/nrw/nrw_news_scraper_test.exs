defmodule EhsEnforcement.Scraping.Nrw.NrwNewsScraperTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Nrw.NrwNewsScraper.ScrapedArticle

  @fixtures_path "test/fixtures/nrw"

  describe "URL slug filtering" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "news_listing.html"))
      {:ok, document} = Floki.parse_document(html)
      %{html: html, document: document}
    end

    test "extracts enforcement-related URLs from news listing", %{document: document} do
      # Extract all news links
      all_links =
        document
        |> Floki.find("a[href*='/about-us/news-and-blogs/news/']")
        |> Enum.map(fn element ->
          Floki.attribute(element, "href") |> List.first()
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      # Should find 11 total links
      assert length(all_links) == 11

      # Filter for enforcement URLs
      enforcement_urls = Enum.filter(all_links, &is_enforcement_url?/1)

      # Should find 6 enforcement-related URLs
      # Note: "prosecution-brings-" doesn't match /-prosecution/ pattern (hyphen before)
      assert length(enforcement_urls) == 6

      # Verify enforcement URLs contain expected patterns
      assert Enum.any?(enforcement_urls, &String.contains?(&1, "fined"))
      assert Enum.any?(enforcement_urls, &String.contains?(&1, "prosecuted"))
      assert Enum.any?(enforcement_urls, &String.contains?(&1, "sentenced"))
      assert Enum.any?(enforcement_urls, &String.contains?(&1, "guilty"))
      assert Enum.any?(enforcement_urls, &String.contains?(&1, "illegal"))
      assert Enum.any?(enforcement_urls, &String.contains?(&1, "court"))
      assert Enum.any?(enforcement_urls, &String.contains?(&1, "ordered-to-pay"))
    end

    test "excludes non-enforcement URLs", %{document: document} do
      all_links =
        document
        |> Floki.find("a[href*='/about-us/news-and-blogs/news/']")
        |> Enum.map(fn element ->
          Floki.attribute(element, "href") |> List.first()
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      enforcement_urls = Enum.filter(all_links, &is_enforcement_url?/1)

      # Non-enforcement URLs should not be included
      refute Enum.any?(enforcement_urls, &String.contains?(&1, "nature-reserve"))
      refute Enum.any?(enforcement_urls, &String.contains?(&1, "flood-warning"))
      refute Enum.any?(enforcement_urls, &String.contains?(&1, "recycling-campaign"))
      refute Enum.any?(enforcement_urls, &String.contains?(&1, "wildlife-survey"))
    end
  end

  describe "article parsing - single defendant" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "single_defendant_article.html"))
      %{html: html}
    end

    test "parses article title correctly", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      title =
        document
        |> Floki.find("h1")
        |> Floki.text()
        |> String.trim()

      assert title == "Farmer fined £2,000 for illegal tree felling"
    end

    test "extracts publication date from time element", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      date_text =
        document
        |> Floki.find("time")
        |> Floki.text()
        |> String.trim()

      assert date_text == "21 March 2024"

      # Parse the date
      parsed_date = parse_date_text(date_text)
      assert parsed_date == ~D[2024-03-21]
    end

    test "extracts article content", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      content =
        document
        |> Floki.find("article, .article-content")
        |> Floki.text()
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      # Should contain key information
      assert String.contains?(content, "John Kerwen Davies")
      assert String.contains?(content, "fined £2,000")
      assert String.contains?(content, "£5,000 in prosecution costs")
      assert String.contains?(content, "£800 victim surcharge")
      assert String.contains?(content, "Forestry Act 1967")
      assert String.contains?(content, "Llanelli Magistrates' Court")
    end
  end

  describe "article parsing - multi defendant" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "multi_defendant_article.html"))
      %{html: html}
    end

    test "parses article with multiple defendants", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      content =
        document
        |> Floki.find("article")
        |> Floki.text()
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      # Should contain both defendants
      assert String.contains?(content, "Benji and Co Limited")
      assert String.contains?(content, "Peter Rees")

      # Should contain different fines
      assert String.contains?(content, "fined £40,000")
      assert String.contains?(content, "fined £10,000")

      # Should contain shared surcharge
      assert String.contains?(content, "£2,000 victim surcharge each")
    end

    test "extracts correct publication date", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      date_text =
        document
        |> Floki.find("time")
        |> Floki.attribute("datetime")
        |> List.first()

      assert date_text == "2025-10-14"
    end
  end

  describe "article parsing - POCA confiscation" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "poca_confiscation_article.html"))
      %{html: html}
    end

    test "identifies POCA confiscation articles", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      content =
        document
        |> Floki.find("article")
        |> Floki.text()
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      assert String.contains?(content, "Proceeds of Crime Act")
      assert String.contains?(content, "POCA")
      assert String.contains?(content, "£78,614")
      assert String.contains?(content, "confiscation order")
    end
  end

  describe "article parsing - major fine" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "major_fine_article.html"))
      %{html: html}
    end

    test "parses major fine article correctly", %{html: html} do
      {:ok, document} = Floki.parse_document(html)

      content =
        document
        |> Floki.find("article")
        |> Floki.text()
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      assert String.contains?(content, "Dwr Cymru Welsh Water")
      assert String.contains?(content, "fined £250,000")
      assert String.contains?(content, "£18,320 in prosecution costs")
      assert String.contains?(content, "Environmental Permitting")
    end
  end

  describe "ScrapedArticle struct" do
    test "can be created with all fields" do
      article = %ScrapedArticle{
        url: "https://naturalresources.wales/about-us/news/test-article/?lang=en",
        slug: "test-article",
        title: "Test Article Title",
        publication_date: ~D[2024-03-21],
        content: "Article content text",
        scrape_timestamp: DateTime.utc_now()
      }

      assert article.url == "https://naturalresources.wales/about-us/news/test-article/?lang=en"
      assert article.slug == "test-article"
      assert article.title == "Test Article Title"
      assert article.publication_date == ~D[2024-03-21]
    end

    test "can encode to JSON" do
      article = %ScrapedArticle{
        url: "https://naturalresources.wales/about-us/news/test-article/?lang=en",
        slug: "test-article",
        title: "Test Article",
        publication_date: ~D[2024-03-21],
        content: "Content",
        scrape_timestamp: ~U[2024-03-21 12:00:00Z]
      }

      assert {:ok, json} = Jason.encode(article)
      assert String.contains?(json, "test-article")
      assert String.contains?(json, "Test Article")
    end
  end

  describe "URL normalization" do
    test "normalizes relative URLs" do
      assert normalize_url("/about-us/news-and-blogs/news/test/?lang=en") ==
               "https://naturalresources.wales/about-us/news-and-blogs/news/test/?lang=en"
    end

    test "preserves absolute URLs" do
      url = "https://naturalresources.wales/about-us/news-and-blogs/news/test/?lang=en"
      assert normalize_url(url) == url
    end

    test "adds language parameter if missing" do
      url = "https://naturalresources.wales/about-us/news/test/"
      normalized = normalize_url(url)
      assert String.contains?(normalized, "lang=en")
    end

    test "preserves existing language parameter" do
      url = "https://naturalresources.wales/about-us/news/test/?lang=cy"
      normalized = normalize_url(url)
      # Should not add duplicate lang param
      assert normalized == url
    end
  end

  describe "slug extraction" do
    test "extracts slug from article URL" do
      url =
        "https://naturalresources.wales/about-us/news-and-blogs/news/company-fined-42000-for-waste/?lang=en"

      slug = extract_slug(url)
      assert slug == "company-fined-42000-for-waste"
    end

    test "handles URL without language parameter" do
      url = "https://naturalresources.wales/about-us/news-and-blogs/news/test-article/"
      slug = extract_slug(url)
      assert slug == "test-article"
    end
  end

  # Helper functions that mirror the scraper's internal logic

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
  end

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

  defp extract_slug(url) do
    url
    |> URI.parse()
    |> Map.get(:path, "")
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
    |> List.last()
  end

  defp parse_date_text(text) do
    case Regex.run(
           ~r/(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})/i,
           text
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
end
