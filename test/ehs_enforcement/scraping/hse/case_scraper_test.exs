defmodule EhsEnforcement.Scraping.Hse.CaseScraperTest do
  use EhsEnforcement.DataCase

  require Ash.Query
  import Ash.Expr

  alias EhsEnforcement.Enforcement
  alias EhsEnforcement.Scraping.Hse.CaseScraper
  alias EhsEnforcement.Scraping.Hse.CaseScraper.ScrapedCase

  describe "case_exists?/1" do
    test "returns false when case does not exist" do
      assert {:ok, false} = CaseScraper.case_exists?("NONEXISTENT123")
    end

    test "returns true when case exists" do
      # Create a test case using Ash
      agency = create_test_agency()
      offender = create_test_offender()

      {:ok, case_record} =
        Enforcement.create_case(%{
          agency_id: agency.id,
          offender_id: offender.id,
          regulator_id: "TEST123",
          offence_action_date: ~D[2023-01-15],
          offence_action_type: "Court Case"
        })

      assert {:ok, true} = CaseScraper.case_exists?("TEST123")
    end
  end

  describe "cases_exist?/1" do
    test "returns correct existence map for multiple regulator IDs" do
      # Create one existing case
      agency = create_test_agency()
      offender = create_test_offender()

      {:ok, _case} =
        Enforcement.create_case(%{
          agency_id: agency.id,
          offender_id: offender.id,
          regulator_id: "EXISTS123",
          offence_action_date: ~D[2023-01-15],
          offence_action_type: "Court Case"
        })

      regulator_ids = ["EXISTS123", "NOTEXISTS456", "ALSONOTEXISTS789"]

      assert {:ok, results} = CaseScraper.cases_exist?(regulator_ids)
      assert results["EXISTS123"] == true
      assert results["NOTEXISTS456"] == false
      assert results["ALSONOTEXISTS789"] == false
    end
  end

  # Note: Testing actual HTTP scraping would require mocking or VCR
  # For now, we test the core logic and Ash integration

  describe "ScrapedCase struct" do
    test "can encode to JSON" do
      scraped_case = %ScrapedCase{
        regulator_id: "TEST123",
        offender_name: "Test Company Ltd",
        offence_action_date: ~D[2023-01-15],
        page_number: 1,
        scrape_timestamp: DateTime.utc_now()
      }

      assert Jason.encode!(scraped_case)
    end
  end

  # ==========================================================================
  # HTML PARSING TESTS (TDD for nested element support)
  # ==========================================================================

  describe "HTML parsing pipeline for case lists" do
    test "parses complete HSE cases table HTML with plain text" do
      # Sample HTML that mimics HSE website structure
      html = """
      <!DOCTYPE html>
      <html>
      <body>
        <table>
          <tr>
            <td>
              <a title="View case details" href="case_details.asp?SF=CN&SV=CN123456">CN123456</a>
            </td>
            <td>ABC Manufacturing Ltd</td>
            <td>01/12/2024</td>
            <td>Leeds</td>
            <td>Manufacturing</td>
          </tr>
          <tr>
            <td>
              <a title="View case details" href="case_details.asp?SF=CN&SV=CN789012">CN789012</a>
            </td>
            <td>XYZ Construction</td>
            <td>15/11/2024</td>
            <td>Manchester</td>
            <td>Construction</td>
          </tr>
        </table>
      </body>
      </html>
      """

      # Parse using the actual pipeline from CaseScraper
      {:ok, document} = Floki.parse_document(html)
      rows = Floki.find(document, "tr")

      # Extract TD elements
      td_data =
        Enum.reduce(rows, [], fn
          {"tr", [], cells}, acc -> [cells | acc]
          _, acc -> acc
        end)

      # Extract cases using exact pattern matching (current implementation)
      timestamp = DateTime.utc_now()

      cases =
        Enum.reduce(td_data, [], fn
          [
            {"td", _, [{"a", [_, _], [regulator_id]}]},
            {"td", _, [offender_name]},
            {"td", _, [offence_action_date]},
            {"td", _, [offender_local_authority]},
            {"td", _, [offender_main_activity]}
          ],
          acc ->
            [
              %{
                regulator_id: String.trim(regulator_id),
                offender_name: String.trim(offender_name),
                offence_action_date: offence_action_date,
                offender_local_authority: String.trim(offender_local_authority),
                offender_main_activity: String.trim(offender_main_activity),
                page_number: 1,
                scrape_timestamp: timestamp
              }
              | acc
            ]

          _, acc ->
            acc
        end)

      # Should parse 2 cases with plain text structure
      assert length(cases) == 2

      # Verify both cases were parsed
      case_ids = Enum.map(cases, & &1.regulator_id)
      assert "CN123456" in case_ids
      assert "CN789012" in case_ids
    end

    test "handles HTML with nested elements in table cells (CURRENT BUG)" do
      # Real-world HTML often has nested spans, divs, etc.
      # This test exposes the bug in current implementation
      html = """
      <!DOCTYPE html>
      <html>
      <body>
        <table>
          <tr>
            <td>
              <a title="View case details" href="case_details.asp?SF=CN&SV=CN123456">
                <span>CN123456</span>
              </a>
            </td>
            <td><div>ABC Manufacturing Ltd</div></td>
            <td>01/12/2024</td>
            <td>Leeds</td>
            <td>Manufacturing</td>
          </tr>
        </table>
      </body>
      </html>
      """

      {:ok, document} = Floki.parse_document(html)
      rows = Floki.find(document, "tr")

      td_data =
        Enum.reduce(rows, [], fn
          {"tr", [], cells}, acc -> [cells | acc]
          _, acc -> acc
        end)

      # Current implementation with exact pattern matching - will FAIL
      # The pattern expects plain text but encounters nested elements
      # so the pattern NEVER MATCHES and falls through to the catchall clause
      cases_with_exact_match =
        Enum.reduce(td_data, [], fn
          # This pattern would only match plain text like: [{"a", [...], ["CN123456"]}]
          # But with nested elements like: [{"a", [...], [{"span", [], ["CN123456"]}]}]
          # it DOESN'T match, so goes to catchall below
          [
            {"td", _, [{"a", [_, _], [regulator_id]}]},
            {"td", _, [offender_name]},
            {"td", _, [offence_action_date]},
            {"td", _, [offender_local_authority]},
            {"td", _, [offender_main_activity]}
          ],
          acc
          when is_binary(regulator_id) ->
            # This would only execute if pattern matched with plain text
            [
              %{
                regulator_id: String.trim(regulator_id),
                offender_name: String.trim(offender_name),
                offence_action_date: offence_action_date,
                offender_local_authority: String.trim(offender_local_authority),
                offender_main_activity: String.trim(offender_main_activity),
                page_number: 1,
                scrape_timestamp: DateTime.utc_now()
              }
              | acc
            ]

          _, acc ->
            # With nested elements, all rows fall through to here
            acc
        end)

      # BUG: Exact pattern matching fails with nested elements - returns empty list
      assert cases_with_exact_match == []

      # SOLUTION: Use Floki.text to handle nested elements
      timestamp = DateTime.utc_now()

      cases_with_floki_text =
        Enum.reduce(td_data, [], fn
          [
            {"td", _, regulator_id_content},
            {"td", _, offender_name_content},
            {"td", _, offence_action_date_content},
            {"td", _, offender_local_authority_content},
            {"td", _, offender_main_activity_content}
          ],
          acc ->
            [
              %{
                regulator_id: Floki.text(regulator_id_content) |> String.trim(),
                offender_name: Floki.text(offender_name_content) |> String.trim(),
                offence_action_date: Floki.text(offence_action_date_content) |> String.trim(),
                offender_local_authority:
                  Floki.text(offender_local_authority_content) |> String.trim(),
                offender_main_activity:
                  Floki.text(offender_main_activity_content) |> String.trim(),
                page_number: 1,
                scrape_timestamp: timestamp
              }
              | acc
            ]

          _, acc ->
            acc
        end)

      # With Floki.text, nested elements are handled correctly
      assert length(cases_with_floki_text) == 1
      assert hd(cases_with_floki_text).regulator_id == "CN123456"
      assert hd(cases_with_floki_text).offender_name == "ABC Manufacturing Ltd"
    end

    test "parses case details with 2-column rows using Floki.text" do
      # HSE case details page uses 2-column format for some fields
      html = """
      <!DOCTYPE html>
      <html>
      <body>
        <table>
          <tr>
            <td><strong>Main Activity</strong></td>
            <td>Manufacturing of metal products</td>
          </tr>
          <tr>
            <td><strong>Industry</strong></td>
            <td>Engineering</td>
          </tr>
          <tr>
            <td><b>HSE Directorate</b></td>
            <td>MANUFACTURING SECTOR</td>
          </tr>
        </table>
      </body>
      </html>
      """

      {:ok, document} = Floki.parse_document(html)
      rows = Floki.find(document, "tr")

      td_data =
        Enum.reduce(rows, [], fn
          {"tr", [], cells}, acc -> [cells | acc]
          _, acc -> acc
        end)

      # Extract case details using 2-column pattern with Floki.text
      details =
        Enum.reduce(td_data, %{}, fn
          [{"td", _, label_content}, {"td", _, value_content}], acc ->
            label = Floki.text(label_content) |> String.trim()
            value = Floki.text(value_content) |> String.trim()

            case label do
              "Main Activity" ->
                Map.put(acc, :offender_main_activity, value)

              "Industry" ->
                Map.put(acc, :offender_industry, value)

              "HSE Directorate" ->
                # Test upcase_first_from_upcase_phrase functionality
                formatted_value =
                  value
                  |> String.downcase()
                  |> String.split()
                  |> Enum.map(&String.capitalize/1)
                  |> Enum.join(" ")

                Map.put(acc, :regulator_function, formatted_value)

              _ ->
                acc
            end

          _, acc ->
            acc
        end)

      assert details.offender_main_activity == "Manufacturing of metal products"
      assert details.offender_industry == "Engineering"
      assert details.regulator_function == "Manufacturing Sector"
    end

    test "parses case details with 4-column rows (monetary fields) using Floki.text" do
      # HSE case details page uses 4-column format for fines/costs
      html = """
      <!DOCTYPE html>
      <html>
      <body>
        <table>
          <tr>
            <td><strong>Total Fine</strong></td>
            <td>£10,000</td>
            <td><strong>Total Costs Awarded to HSE</strong></td>
            <td>£5,000</td>
          </tr>
        </table>
      </body>
      </html>
      """

      {:ok, document} = Floki.parse_document(html)
      rows = Floki.find(document, "tr")

      td_data =
        Enum.reduce(rows, [], fn
          {"tr", [], cells}, acc -> [cells | acc]
          _, acc -> acc
        end)

      # Extract case details using 4-column pattern with Floki.text
      details =
        Enum.reduce(td_data, %{}, fn
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
                "Total Fine" -> Map.put(acc, :offence_fine, value1)
                _ -> acc
              end

            acc =
              case label2 do
                "Total Costs Awarded to HSE" -> Map.put(acc, :offence_costs, value2)
                _ -> acc
              end

            acc

          _, acc ->
            acc
        end)

      assert details.offence_fine == "£10,000"
      assert details.offence_costs == "£5,000"
    end

    test "handles deeply nested HTML structures with Floki.text" do
      # Extreme case: multiple levels of nesting
      html = """
      <!DOCTYPE html>
      <html>
      <body>
        <table>
          <tr>
            <td>
              <div>
                <a href="#">
                  <span class="highlight">
                    <em>CN999888</em>
                  </span>
                </a>
              </div>
            </td>
            <td>
              <div class="wrapper">
                <span class="name">
                  Complex Company Name Ltd
                </span>
              </div>
            </td>
            <td>20/11/2024</td>
            <td>Birmingham</td>
            <td>Services</td>
          </tr>
        </table>
      </body>
      </html>
      """

      {:ok, document} = Floki.parse_document(html)
      rows = Floki.find(document, "tr")

      td_data =
        Enum.reduce(rows, [], fn
          {"tr", [], cells}, acc -> [cells | acc]
          _, acc -> acc
        end)

      # Use Floki.text for deeply nested structures
      cases =
        Enum.reduce(td_data, [], fn
          [
            {"td", _, regulator_id_content},
            {"td", _, offender_name_content},
            {"td", _, offence_action_date_content},
            {"td", _, offender_local_authority_content},
            {"td", _, offender_main_activity_content}
          ],
          acc ->
            [
              %{
                regulator_id: Floki.text(regulator_id_content) |> String.trim(),
                offender_name: Floki.text(offender_name_content) |> String.trim(),
                offence_action_date: Floki.text(offence_action_date_content) |> String.trim(),
                offender_local_authority:
                  Floki.text(offender_local_authority_content) |> String.trim(),
                offender_main_activity:
                  Floki.text(offender_main_activity_content) |> String.trim()
              }
              | acc
            ]

          _, acc ->
            acc
        end)

      assert length(cases) == 1
      assert hd(cases).regulator_id == "CN999888"
      assert hd(cases).offender_name == "Complex Company Name Ltd"
      assert hd(cases).offender_local_authority == "Birmingham"
    end
  end

  # Helper functions

  defp create_test_agency do
    {:ok, agency} =
      Enforcement.create_agency(%{
        name: "Health and Safety Executive",
        code: :hse,
        base_url: "https://hse.gov.uk"
      })

    agency
  end

  defp create_test_offender do
    {:ok, offender} =
      Enforcement.create_offender(%{
        name: "Test Company Limited"
      })

    offender
  end
end
