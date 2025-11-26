defmodule EhsEnforcement.Enforcement.BreachParser do
  @moduledoc """
  Parses breach/violation text from scraped enforcement data into structured Offence records.

  Handles:
  - Extracting legislation references (Act name, year, section/regulation numbers)
  - Parsing fine information from breach text
  - Creating structured data for Offence record creation
  - Supporting both HSE and EA breach formats

  ## Examples

  ### HSE Format:
  "Health and Safety at Work etc Act 1974, Section 2(1)"
  "Construction (Design and Management) Regulations 2015, Regulation 13(1)"

  ### EA Format:
  "Environmental Permitting (England and Wales) Regulations 2016, Regulation 38(1)"
  """

  require Logger

  @doc """
  Parse a single breach description into structured offence data.

  Returns map with:
  - `:offence_description` - Full breach text
  - `:legislation_reference` - Extracted legislation reference
  - `:legislation_part` - Section/Regulation number (e.g., "Section 2(1)")
  - `:act_name` - Act/Regulation name
  - `:act_year` - Year of legislation
  - `:fine` - Extracted fine amount (if present in text)
  """
  def parse_breach(breach_text) when is_binary(breach_text) do
    breach_text = String.trim(breach_text)

    %{
      offence_description: breach_text,
      legislation_reference: extract_legislation_reference(breach_text),
      legislation_part: extract_legislation_part(breach_text),
      act_name: extract_act_name(breach_text),
      act_year: extract_act_year(breach_text),
      fine: extract_fine_from_text(breach_text)
    }
  end

  @doc """
  Parse multiple breach descriptions (from semicolon-separated string or list).

  Returns list of structured offence data maps.
  """
  def parse_breaches(breaches) when is_binary(breaches) do
    breaches
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index(1)
    |> Enum.map(fn {breach_text, sequence} ->
      breach_text
      |> parse_breach()
      |> Map.put(:sequence_number, sequence)
    end)
  end

  def parse_breaches(breaches) when is_list(breaches) do
    breaches
    |> Enum.with_index(1)
    |> Enum.map(fn {breach_text, sequence} ->
      breach_text
      |> parse_breach()
      |> Map.put(:sequence_number, sequence)
    end)
  end

  # Extract full legislation reference (e.g., "Health and Safety at Work etc Act 1974, Section 2(1)")
  defp extract_legislation_reference(text) do
    # Match patterns like "Act YYYY" or "Regulations YYYY"
    case Regex.run(~r/(.+?(?:Act|Regulations|Order)\s+\d{4})(?:,\s*(.+))?/i, text) do
      [_, act_part, section_part] when is_binary(section_part) ->
        "#{String.trim(act_part)}, #{String.trim(section_part)}"

      [_, act_part] ->
        String.trim(act_part)

      _ ->
        nil
    end
  end

  # Extract legislation part (e.g., "Section 2(1)", "Regulation 13")
  defp extract_legislation_part(text) do
    cond do
      # Match "Section X" or "Section X(Y)" patterns
      match = Regex.run(~r/Section\s+(\d+(?:\([^)]+\))?(?:\s+and\s+\d+(?:\([^)]+\))?)*)/i, text) ->
        "Section #{elem(List.to_tuple(match), 1)}"

      # Match "Regulation X" or "Regulation X(Y)" patterns
      match =
          Regex.run(~r/Regulation\s+(\d+(?:\([^)]+\))?(?:\s+and\s+\d+(?:\([^)]+\))?)*)/i, text) ->
        "Regulation #{elem(List.to_tuple(match), 1)}"

      # Match "Article X" patterns
      match = Regex.run(~r/Article\s+(\d+(?:\([^)]+\))?)/i, text) ->
        "Article #{elem(List.to_tuple(match), 1)}"

      # Match "Rule X" patterns
      match = Regex.run(~r/Rule\s+(\d+(?:\([^)]+\))?)/i, text) ->
        "Rule #{elem(List.to_tuple(match), 1)}"

      true ->
        nil
    end
  end

  # Extract Act/Regulation name (e.g., "Health and Safety at Work etc Act 1974")
  defp extract_act_name(text) do
    case Regex.run(~r/(.+?(?:Act|Regulations|Order)\s+\d{4})/i, text) do
      [_, act_name] -> String.trim(act_name)
      _ -> nil
    end
  end

  # Extract year from Act/Regulation name
  defp extract_act_year(text) do
    case Regex.run(~r/(?:Act|Regulations|Order)\s+(\d{4})/i, text) do
      [_, year_str] ->
        case Integer.parse(year_str) do
          {year, ""} -> year
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # Extract fine amount from breach text (if mentioned)
  # Some breach descriptions include fine info like "Fine: £5,000"
  defp extract_fine_from_text(text) do
    case Regex.run(~r/[Ff]ine:?\s*£([\d,]+(?:\.\d{2})?)/, text) do
      [_, fine_str] ->
        fine_str
        |> String.replace(",", "")
        |> Decimal.new()

      _ ->
        nil
    end
  end

  @doc """
  Determine legislation title from breach text.

  Extracts Act/Regulation name and year, formats as title.
  Falls back to generic title if parsing fails.
  """
  def extract_legislation_title(breach_text) when is_binary(breach_text) do
    case extract_act_name(breach_text) do
      nil -> "Unknown Legislation"
      act_name -> act_name
    end
  end

  @doc """
  Determine legislation type from breach text.

  Returns atom: :act, :regulation, :order, or nil
  """
  def extract_legislation_type(breach_text) when is_binary(breach_text) do
    cond do
      String.contains?(breach_text, "Act") -> :act
      String.contains?(breach_text, "Regulations") -> :regulation
      String.contains?(breach_text, "Order") -> :order
      true -> nil
    end
  end

  @doc """
  Clean and normalize breach text for storage.

  - Removes excess whitespace
  - Normalizes line breaks
  - Trims special characters
  """
  def clean_breach_text(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/[\r\n]+/, " ")
  end
end
