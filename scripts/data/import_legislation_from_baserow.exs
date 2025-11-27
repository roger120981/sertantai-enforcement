#!/usr/bin/env elixir

# Import legislation data from Baserow export CSV
#
# Usage:
#   mix run scripts/data/import_legislation_from_baserow.exs ~/Downloads/export-UK-grid.csv
#
# This script imports UK legislation data exported from Baserow into the
# legislation table. It maps Baserow columns to our schema and constructs
# legislation.gov.uk URLs.

require Ash.Query
alias EhsEnforcement.Enforcement

defmodule LegislationImporter do
  @moduledoc """
  Imports legislation data from Baserow CSV export.

  CSV Columns:
  - Title_EN → legislation_title
  - type_code → legislation_type_code (e.g., "ukpga", "uksi")
  - Year → legislation_year
  - Number → legislation_number
  - type_class → legislation_type (:act, :regulation, :order, :acop)
  - Type → (ignored - it's just type_code spelled out)
  """

  def run(csv_path) do
    IO.puts("\n🔄 Importing legislation from Baserow export...")
    IO.puts("📄 File: #{csv_path}\n")

    unless File.exists?(csv_path) do
      IO.puts("❌ File not found: #{csv_path}")
      System.halt(1)
    end

    csv_path
    |> File.stream!()
    |> CSV.decode!(headers: true)
    |> Enum.with_index(1)
    |> Enum.reduce(%{imported: 0, skipped: 0, errors: []}, fn {row, line_num}, acc ->
      process_row(row, line_num, acc)
    end)
    |> print_summary()
  end

  defp process_row(row, line_num, acc) do
    case parse_row(row) do
      {:ok, attrs} ->
        case import_legislation(attrs) do
          {:ok, _legislation} ->
            if rem(acc.imported, 10) == 0 do
              IO.write(".")
            end

            %{acc | imported: acc.imported + 1}

          {:error, reason} ->
            error = "Line #{line_num}: #{inspect(reason)}"
            IO.puts("\n⚠️  #{error}")
            %{acc | errors: [error | acc.errors]}
        end

      {:skip, reason} ->
        IO.puts("⏭️  Line #{line_num}: #{reason}")
        %{acc | skipped: acc.skipped + 1}
    end
  end

  defp parse_row(row) do
    title = get_field(row, "Title_EN")
    type_code = get_field(row, "type_code")
    year = get_field(row, "Year")
    number = get_field(row, "Number")
    type_class = get_field(row, "type_class")

    # Skip rows with missing required fields
    cond do
      is_nil(title) or title == "" ->
        {:skip, "Missing title"}

      is_nil(type_code) or type_code == "" ->
        {:skip, "Missing type_code"}

      is_nil(year) or year == "" ->
        {:skip, "Missing year"}

      is_nil(number) or number == "" ->
        {:skip, "Missing number"}

      true ->
        {:ok,
         %{
           legislation_title: title,
           legislation_type_code: type_code,
           legislation_year: parse_year(year),
           legislation_number: to_string(number),
           legislation_type: parse_type_class(type_class),
           legislation_url: build_url(type_code, year, number)
         }}
    end
  end

  defp get_field(row, key) do
    case Map.get(row, key) do
      nil -> nil
      "" -> nil
      value -> String.trim(value)
    end
  end

  defp parse_year(year_str) do
    case Integer.parse(to_string(year_str)) do
      {year, _} -> year
      :error -> nil
    end
  end

  defp parse_type_class(nil), do: :act
  defp parse_type_class(""), do: :act

  defp parse_type_class(type_class) do
    normalized = String.downcase(type_class)

    cond do
      # Acts
      normalized == "act" -> :act
      String.contains?(normalized, "public general act") -> :act
      # Measures (Welsh Assembly Measures)
      normalized == "measure" -> :measure
      # Regulations (includes statutory instruments)
      normalized == "regulation" -> :regulation
      normalized == "regulations" -> :regulation
      String.contains?(normalized, "statutory instrument") -> :regulation
      String.contains?(normalized, "statutory rule") -> :regulation
      # Rules (procedural rules)
      normalized == "rules" -> :rule
      # Schemes (administrative schemes)
      normalized == "scheme" -> :scheme
      # Orders
      normalized == "order" -> :order
      normalized == "orders" -> :order
      # ACOP
      normalized == "acop" -> :acop
      # Skip junk data (numbers, etc.) - default to :regulation
      true -> :regulation
    end
  end

  defp build_url(type_code, year, number) do
    # Construct legislation.gov.uk URL
    # Format: https://www.legislation.gov.uk/{type_code}/{year}/{number}
    # Example: https://www.legislation.gov.uk/ukpga/1974/37
    "https://www.legislation.gov.uk/#{type_code}/#{year}/#{number}"
  end

  defp import_legislation(attrs) do
    # Check if legislation already exists using the unique gov.uk identity
    query =
      Enforcement.Legislation
      |> Ash.Query.filter(
        legislation_year == ^attrs.legislation_year and
          legislation_number == ^attrs.legislation_number and
          legislation_type_code == ^attrs.legislation_type_code
      )

    case Ash.read(query) do
      {:ok, [existing | _]} ->
        # Already exists, update it
        Ash.update(existing, attrs)

      {:ok, []} ->
        # Doesn't exist, create it
        Ash.create(Enforcement.Legislation, attrs)

      {:error, error} ->
        {:error, error}
    end
  end

  defp print_summary(%{imported: imported, skipped: skipped, errors: errors}) do
    IO.puts("\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("✅ Import Complete!")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("✅ Imported: #{imported}")
    IO.puts("⏭️  Skipped:  #{skipped}")
    IO.puts("❌ Errors:   #{length(errors)}")

    if length(errors) > 0 do
      IO.puts("\n❌ Errors:")
      Enum.each(errors, fn error -> IO.puts("   #{error}") end)
    end

    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
  end
end

# Get CSV path from command line args
csv_path =
  case System.argv() do
    [path] ->
      Path.expand(path)

    [] ->
      Path.expand("~/Downloads/export-UK-grid.csv")

    _ ->
      IO.puts("Usage: mix run #{__ENV__.file} [csv_path]")
      System.halt(1)
  end

# Run the importer
LegislationImporter.run(csv_path)
