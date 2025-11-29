defmodule EhsEnforcement.Scraping.Shared.DateParser do
  @moduledoc """
  Shared utility for parsing dates from various string formats.

  This module consolidates date parsing logic that was previously
  duplicated across HSE and EA processors.

  Supports multiple date formats commonly found in UK regulatory data:
  - ISO 8601: YYYY-MM-DD
  - UK format with slashes: DD/MM/YYYY
  - UK format with dashes: DD-MM-YYYY
  - Already parsed Date structs (passthrough)

  ## Usage

      iex> DateParser.parse_date("23/10/2025")
      ~D[2025-10-23]

      iex> DateParser.parse_date("2025-10-23")
      ~D[2025-10-23]

      iex> DateParser.parse_date("23-10-2025")
      ~D[2025-10-23]

      iex> DateParser.parse_date(nil)
      nil

      iex> DateParser.parse_date("invalid")
      nil
  """

  @doc """
  Parses a date from various string formats to a Date struct.

  Attempts to parse dates in the following order:
  1. ISO 8601 format (YYYY-MM-DD) - fastest path
  2. UK slash format (DD/MM/YYYY)
  3. UK dash format (DD-MM-YYYY)
  4. ISO format with manual parsing (YYYY-MM-DD)

  ## Parameters
  - `date` - Date string, Date struct, or nil

  ## Returns
  - `%Date{}` - Parsed date struct
  - `nil` - If date is nil, empty string, or invalid format
  """
  def parse_date(nil), do: nil
  def parse_date(""), do: nil

  def parse_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed_date} ->
        parsed_date

      {:error, _} ->
        # Try parsing other common UK formats
        try_parse_date_formats(date)
    end
  end

  def parse_date(%Date{} = date), do: date
  def parse_date(_), do: nil

  # Private helper functions for different date formats

  defp try_parse_date_formats(date_string) do
    # Try DD/MM/YYYY format (most common in UK data)
    case Regex.run(~r/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/, String.trim(date_string)) do
      [_, day, month, year] ->
        build_date(year, month, day) || try_parse_dash_format(date_string)

      _ ->
        try_parse_dash_format(date_string)
    end
  end

  defp try_parse_dash_format(date_string) do
    # Try DD-MM-YYYY format
    case Regex.run(~r/^(\d{1,2})-(\d{1,2})-(\d{4})$/, String.trim(date_string)) do
      [_, day, month, year] ->
        build_date(year, month, day) || try_parse_iso_format(date_string)

      _ ->
        try_parse_iso_format(date_string)
    end
  end

  defp try_parse_iso_format(date_string) do
    # Try YYYY-MM-DD format with manual parsing
    case Regex.run(~r/^(\d{4})-(\d{1,2})-(\d{1,2})$/, String.trim(date_string)) do
      [_, year, month, day] ->
        build_date(year, month, day)

      _ ->
        try_parse_long_format(date_string)
    end
  end

  @month_map %{
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

  defp try_parse_long_format(date_string) do
    # Try long format: "16 July 2025", "9 January 2025"
    case Regex.run(~r/^(\d{1,2})\s+(\w+)\s+(\d{4})$/i, String.trim(date_string)) do
      [_, day, month_name, year] ->
        month = Map.get(@month_map, String.downcase(month_name))

        if month do
          build_date(year, Integer.to_string(month), day)
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp build_date(year, month, day) do
    case Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  @doc """
  Parses a list of date strings, filtering out nil and invalid values.

  Useful for processing multiple dates at once.

  ## Parameters
  - `date_strings` - List of date strings or nil values

  ## Returns
  - List of successfully parsed Date structs (excludes nil/invalid dates)

  ## Examples

      iex> DateParser.parse_dates(["23/10/2025", "2025-10-24", nil, "invalid"])
      [~D[2025-10-23], ~D[2025-10-24]]
  """
  def parse_dates(date_strings) when is_list(date_strings) do
    date_strings
    |> Enum.map(&parse_date/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Converts a Date struct or date string to ISO 8601 format (YYYY-MM-DD).

  ## Parameters
  - `date` - Date struct or string

  ## Returns
  - String in YYYY-MM-DD format or nil

  ## Examples

      iex> DateParser.to_iso8601(~D[2025-10-23])
      "2025-10-23"

      iex> DateParser.to_iso8601("23/10/2025")
      "2025-10-23"

      iex> DateParser.to_iso8601(nil)
      nil
  """
  def to_iso8601(nil), do: nil
  def to_iso8601(""), do: nil

  def to_iso8601(%Date{} = date) do
    Date.to_iso8601(date)
  end

  def to_iso8601(date_string) when is_binary(date_string) do
    case parse_date(date_string) do
      %Date{} = date -> Date.to_iso8601(date)
      nil -> nil
    end
  end

  @doc """
  Converts a Date struct or date string to UK format (DD/MM/YYYY).

  ## Parameters
  - `date` - Date struct or string

  ## Returns
  - String in DD/MM/YYYY format or nil

  ## Examples

      iex> DateParser.to_uk_format(~D[2025-10-23])
      "23/10/2025"

      iex> DateParser.to_uk_format("2025-10-23")
      "23/10/2025"
  """
  def to_uk_format(nil), do: nil
  def to_uk_format(""), do: nil

  def to_uk_format(%Date{day: day, month: month, year: year}) do
    day_str = String.pad_leading("#{day}", 2, "0")
    month_str = String.pad_leading("#{month}", 2, "0")
    "#{day_str}/#{month_str}/#{year}"
  end

  def to_uk_format(date_string) when is_binary(date_string) do
    case parse_date(date_string) do
      %Date{} = date -> to_uk_format(date)
      nil -> nil
    end
  end
end
