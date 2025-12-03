defmodule EhsEnforcement.Scraping.Opss.OpssEnforcementScraperTest do
  use ExUnit.Case, async: true

  alias EhsEnforcement.Scraping.Opss.OpssEnforcementScraper

  @fixtures_path "test/fixtures/opss"

  describe "parse_enforcement_page/2 with Oct 2024 - Mar 2025 fixture" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "enforcement_oct_2024_mar_2025.html"))
      timestamp = DateTime.utc_now()
      {:ok, html: html, timestamp: timestamp}
    end

    test "parses correct number of enforcement actions", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)

      # 6 actions in fixture: 1 construction, 1 environmental, 2 product safety, 2 timber
      assert length(actions) == 6
    end

    test "extracts business names correctly", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)
      business_names = Enum.map(actions, & &1.business_name)

      assert "SUPER TOUGHENED GLASS LTD" in business_names
      assert "CVS Energy Ltd t/a Clearview Stoves" in business_names

      assert "SUZHOUYUEZHIFUKEJI CO., LTD t/a Joyful Inspiration (online seller, based in China)" in business_names

      assert "SUNSEEKER INTERNATIONAL LIMITED" in business_names
    end

    test "business names do not contain 'Business:' prefix", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)

      Enum.each(actions, fn action ->
        refute String.starts_with?(action.business_name, "Business:")
      end)
    end

    test "extracts action types correctly", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)

      action_types = Enum.map(actions, & &1.action_type)

      assert "Prohibition Notice" in action_types
      assert "Stop Notice" in action_types
      assert "Recall Notice" in action_types
      assert "Withdrawal Notice" in action_types
      assert "Prosecution" in action_types
      assert "Compliance Notice" in action_types
    end

    test "extracts categories correctly", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)

      categories = Enum.map(actions, & &1.category) |> Enum.uniq()

      assert "Construction Products" in categories
      assert "Environmental Protection" in categories
      assert "Product Safety" in categories
      assert "Timber" in categories
    end

    test "extracts action dates correctly", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)

      # Find the Super Toughened Glass action
      glass_action = Enum.find(actions, &(&1.business_name == "SUPER TOUGHENED GLASS LTD"))
      assert glass_action.action_date == ~D[2024-10-24]

      # Find the Sunseeker prosecution
      sunseeker_action =
        Enum.find(actions, &(&1.business_name == "SUNSEEKER INTERNATIONAL LIMITED"))

      assert sunseeker_action.action_date == ~D[2024-11-22]
    end

    test "extracts products affected", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)

      # CVS Energy has multiple products
      cvs_action =
        Enum.find(actions, &(&1.business_name == "CVS Energy Ltd t/a Clearview Stoves"))

      assert String.contains?(cvs_action.products, "Pioneer 400 Stove")
      assert String.contains?(cvs_action.products, "Solution 500 Stove")
    end

    test "extracts breached regulations", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)

      glass_action = Enum.find(actions, &(&1.business_name == "SUPER TOUGHENED GLASS LTD"))

      assert String.contains?(
               glass_action.breached_regulations,
               "Construction Products Regulations 2013"
             )

      cvs_action =
        Enum.find(actions, &(&1.business_name == "CVS Energy Ltd t/a Clearview Stoves"))

      assert String.contains?(
               cvs_action.breached_regulations,
               "Ecodesign for Energy-Related Products Regulations 2010"
             )
    end

    test "extracts prosecution details for criminal cases", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)

      sunseeker = Enum.find(actions, &(&1.business_name == "SUNSEEKER INTERNATIONAL LIMITED"))

      assert sunseeker.action_type == "Prosecution"
      assert sunseeker.fine == 240_000
      assert sunseeker.costs == 51_619.96
      assert sunseeker.confiscation == 66_950.64

      # Court info is extracted - may contain Magistrates' or Crown Court
      assert sunseeker.court != nil
      assert String.contains?(sunseeker.court, "Court")
    end

    test "extracts detail text", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)

      glass_action = Enum.find(actions, &(&1.business_name == "SUPER TOUGHENED GLASS LTD"))
      assert String.contains?(glass_action.detail, "prohibits the supply")
      assert String.contains?(glass_action.detail, "declaration of performance")
    end

    test "includes scrape timestamp", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)

      Enum.each(actions, fn action ->
        assert action.scrape_timestamp == timestamp
      end)
    end
  end

  describe "parse_enforcement_page/2 with Apr - Sep 2024 fixture" do
    setup do
      html = File.read!(Path.join(@fixtures_path, "enforcement_apr_sep_2024.html"))
      timestamp = DateTime.utc_now()
      {:ok, html: html, timestamp: timestamp}
    end

    test "parses correct number of enforcement actions", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)
      # 6 actions: 1 environmental, 3 product safety, 1 construction, 1 timber prosecution
      assert length(actions) == 6
    end

    test "extracts Seizure Notice action type", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)

      seizure_action = Enum.find(actions, &(&1.action_type == "Seizure Notice"))
      assert seizure_action != nil

      assert seizure_action.business_name ==
               "DIMENSIONE PESCA S.R.L. t/a Dimensione Pesca Com (online seller, based in Italy)"
    end

    test "extracts prosecution with fine amount", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)

      prosecution = Enum.find(actions, &(&1.business_name == "TROPICAL HARDWOODS IMPORT LTD"))
      assert prosecution.action_type == "Prosecution"
      assert prosecution.fine == 85_000
      assert prosecution.costs == 12_500
    end

    test "handles different category formats", %{html: html, timestamp: timestamp} do
      actions = OpssEnforcementScraper.parse_enforcement_page(html, timestamp)

      categories = Enum.map(actions, & &1.category) |> Enum.uniq()

      # Check categories are extracted without date suffixes
      Enum.each(categories, fn cat ->
        refute String.contains?(cat, "2024")
        refute String.contains?(cat, "April")
        refute String.contains?(cat, "August")
      end)
    end
  end

  describe "parse_enforcement_page/2 edge cases" do
    test "returns empty list for empty HTML" do
      actions = OpssEnforcementScraper.parse_enforcement_page("", DateTime.utc_now())
      assert actions == []
    end

    test "returns empty list for HTML without govspeak content" do
      html = "<html><body><p>No enforcement actions</p></body></html>"
      actions = OpssEnforcementScraper.parse_enforcement_page(html, DateTime.utc_now())
      assert actions == []
    end

    test "handles malformed HTML gracefully" do
      html = """
      <div class="govspeak">
        <h2 id="product-safety">Product Safety</h2>
        <h3>Business: INCOMPLETE ENTRY</h3>
        <!-- Missing h4 sections -->
      </div>
      """

      # Should not raise, may return empty or partial results
      actions = OpssEnforcementScraper.parse_enforcement_page(html, DateTime.utc_now())
      assert is_list(actions)
    end
  end

  describe "determine_action_type/1" do
    test "identifies Prohibition Notice" do
      text = "Prohibition Notice dated 24 October 2024, served with effect from..."
      assert OpssEnforcementScraper.determine_action_type(text) == "Prohibition Notice"
    end

    test "identifies Stop Notice" do
      text = "Stop Notice dated 21 October 2024, served under Regulation..."
      assert OpssEnforcementScraper.determine_action_type(text) == "Stop Notice"
    end

    test "identifies Recall Notice" do
      text = "Recall Notice dated 21 November 2024, served under..."
      assert OpssEnforcementScraper.determine_action_type(text) == "Recall Notice"
    end

    test "identifies Withdrawal Notice" do
      text = "Withdrawal Notice dated 5 December 2024, served under..."
      assert OpssEnforcementScraper.determine_action_type(text) == "Withdrawal Notice"
    end

    test "identifies Compliance Notice" do
      text = "Compliance Notice dated 21 August 2024, served under..."
      assert OpssEnforcementScraper.determine_action_type(text) == "Compliance Notice"
    end

    test "identifies Seizure Notice" do
      text = "Seizure Notice dated 10 May 2024, served under..."
      assert OpssEnforcementScraper.determine_action_type(text) == "Seizure Notice"
    end

    test "identifies Prosecution" do
      text = "Prosecution on 22 November 2024 (sentenced)."
      assert OpssEnforcementScraper.determine_action_type(text) == "Prosecution"
    end

    test "returns unknown for unrecognized action" do
      text = "Some other regulatory action taken"
      assert OpssEnforcementScraper.determine_action_type(text) == "Unknown"
    end
  end

  describe "extract_date/1" do
    test "extracts date from 'dated DD Month YYYY' format" do
      text = "Prohibition Notice dated 24 October 2024, served with effect..."
      assert OpssEnforcementScraper.extract_date(text) == ~D[2024-10-24]
    end

    test "extracts date from 'on DD Month YYYY' format" do
      text = "Prosecution on 22 November 2024 (sentenced)."
      assert OpssEnforcementScraper.extract_date(text) == ~D[2024-11-22]
    end

    test "extracts date from 'dated D Month YYYY' format (single digit day)" do
      text = "Recall Notice dated 5 December 2024, served under..."
      assert OpssEnforcementScraper.extract_date(text) == ~D[2024-12-05]
    end

    test "returns nil for text without date" do
      text = "Some action was taken regarding non-compliance"
      assert OpssEnforcementScraper.extract_date(text) == nil
    end
  end

  describe "extract_monetary_value/2" do
    test "extracts fine amount from text" do
      text = "The court imposed a fine of £85,000 and ordered costs..."
      assert OpssEnforcementScraper.extract_monetary_value(text, :fine) == 85_000
    end

    test "extracts costs from text" do
      text = "...and ordered costs of £12,500."
      assert OpssEnforcementScraper.extract_monetary_value(text, :costs) == 12_500
    end

    test "extracts fine with decimal places" do
      text = "The Crown Court imposed a fine in the amount of £240,000..."
      assert OpssEnforcementScraper.extract_monetary_value(text, :fine) == 240_000
    end

    test "extracts costs with pence" do
      text = "...and allowed costs in the sum of £51,619.96."
      assert OpssEnforcementScraper.extract_monetary_value(text, :costs) == 51_619.96
    end

    test "extracts confiscation order amount" do
      text = "...a confiscation order for the amount of £66,950.64..."
      assert OpssEnforcementScraper.extract_monetary_value(text, :confiscation) == 66_950.64
    end

    test "returns nil when value not found" do
      text = "No monetary penalties were imposed"
      assert OpssEnforcementScraper.extract_monetary_value(text, :fine) == nil
    end
  end

  describe "is_prosecution?/1" do
    test "returns true for prosecution action type" do
      assert OpssEnforcementScraper.is_prosecution?("Prosecution") == true
    end

    test "returns false for notice action types" do
      refute OpssEnforcementScraper.is_prosecution?("Prohibition Notice")
      refute OpssEnforcementScraper.is_prosecution?("Stop Notice")
      refute OpssEnforcementScraper.is_prosecution?("Recall Notice")
      refute OpssEnforcementScraper.is_prosecution?("Compliance Notice")
    end
  end

  describe "extract_category/1" do
    test "extracts category without date suffix" do
      heading = "Construction Products – October 2024"
      assert OpssEnforcementScraper.extract_category(heading) == "Construction Products"
    end

    test "handles different dash types" do
      heading = "Environmental Protection - August 2024"
      assert OpssEnforcementScraper.extract_category(heading) == "Environmental Protection"
    end

    test "handles extra whitespace" do
      heading = "Product Safety –  November 2024 "
      assert OpssEnforcementScraper.extract_category(heading) == "Product Safety"
    end

    test "returns full heading if no date pattern found" do
      heading = "Special Category"
      assert OpssEnforcementScraper.extract_category(heading) == "Special Category"
    end
  end
end
