defmodule EhsEnforcement.Utility do
  @moduledoc false

  alias EhsEnforcement.Legislation.LegalRegister

  @doc """
  Utility function to time the parser.
  Arose when rm_header was taking 5 seconds!  Faster now :)
  """
  def parse_timer do
    # {:ok, binary} = File.read(Path.absname(Legl.original())) # TODO: Fix this reference
    # {t, binary} = :timer.tc(UK, :rm_header, [binary])
    # display_time("rm_header", t)
    # {t, _binary} = :timer.tc(UK, :rm_explanatory_note, [binary])
    # display_time("rm_explanatory_note", t)
  end

  def parser_timer(arg, func, name) do
    {t, binary} = :timer.tc(func, [arg])
    display_time(name, t)
    binary
  end

  defp display_time(f, t) do
    IO.puts("#{f} takes #{t} microseconds or #{t / 1_000_000} seconds")
  end

  def todays_date do
    DateTime.utc_now()
    |> (&"#{&1.day}/#{&1.month}/#{&1.year}").()
  end

  def csv_header_row(fields, at_csv) do
    Enum.join(fields, ",")
    |> EhsEnforcement.Utility.write_to_csv(at_csv)
  end

  def quote_list(list) when is_list(list) do
    Enum.map(list, fn string ->
      if String.contains?(string, ",") do
        ~s/"#{string}"/
      else
        string
      end
    end)
  end

  def csv_quote_enclosure(list) when is_list(list) do
    Enum.map(list, &csv_quote_enclosure/1)
  end

  def csv_quote_enclosure(string) do
    string = string |> to_string() |> String.trim()

    if "" != string do
      ~s/"#{string}"/
    else
      string
    end
  end

  def csv_list_quote_enclosure(string) do
    ~s/[#{string}]/
  end

  def append_to_csv(binary, filename) do
    {:ok, file} =
      "lib/#{filename}.csv"
      |> Path.absname()
      |> File.open([:utf8, :append])

    :ok = IO.puts(file, binary)
    :ok = File.close(file)
    :ok
  end

  def write_to_csv(binary, "lib" <> _rest = path) do
    {:ok, file} =
      path
      |> Path.absname()
      |> File.open([:utf8, :write])

    :ok = IO.puts(file, binary)
    :ok = File.close(file)
    :ok
  end

  def write_to_csv(binary, filename) do
    {:ok, file} =
      "lib/#{filename}.csv"
      |> Path.absname()
      |> File.open([:utf8, :write])

    :ok = IO.puts(file, binary)
    :ok = File.close(file)
    :ok
  end

  @doc """
  Receives a path as string and returns atom keyed map
  """
  @spec read_json_records(binary()) :: list(map())
  def read_json_records(path) do
    %{records: records} = open_and_parse_json_file(path)
    records
  end

  @spec open_and_parse_json_file(binary()) :: map()
  defp open_and_parse_json_file(path) do
    path
    |> Path.absname()
    |> File.read()
    |> elem(1)
    |> Jason.decode!(keys: :atoms)
  end

  @doc """
  Function to save records as .json
  """
  @spec save_json(list(), binary()) :: :ok
  def save_json(records, path) do
    json = Map.put(%{}, "records", records) |> Jason.encode!(pretty: true)
    save_at_records_to_file(~s/#{json}/, path)
  end

  @spec save_json_returning(list(), binary()) :: {:ok, list()}
  def save_json_returning(records, path) do
    json = Map.put(%{}, "records", records) |> Jason.encode!(pretty: true)
    {save_at_records_to_file(~s/#{json}/, path), records}
  end

  @spec save_structs_as_json(list(struct() | map()), path :: binary(), map()) :: :ok
  def save_structs_as_json(records, path, %{filesave?: true} = _opts) do
    save_structs_as_json(records, path)
  end

  def save_structs_as_json(_, _, _), do: :ok

  @spec save_structs_as_json(list(struct() | map()), binary()) :: :ok
  def save_structs_as_json(records, path) when is_list(records) do
    maps_from_structs(records)
    |> (&Map.put(%{}, "records", &1)).()
    |> Jason.encode!(pretty: true)
    |> save_at_records_to_file(path)
  end

  def save_structs_as_json(_, _), do: :ok

  @spec save_structs_as_json_returning([map()], path :: String.t(), %{filesave?: true}) :: [map()]
  def save_structs_as_json_returning(records, path, %{filesave?: true} = _opts) do
    save_structs_as_json(records, path)
    records
  end

  @doc """

  """
  def save_at_records_to_file(records),
    do: save_at_records_to_file(records, "lib/legl/data_files/txt/airtable.txt")

  def save_at_records_to_file(records, path) when is_list(records) do
    case File.open(path |> Path.absname(), [:utf8, :write]) do
      {:ok, file} ->
        :ok = IO.puts(file, inspect(records, limit: :infinity))
        :ok = File.close(file)
        :ok

      {:error, :enoent} ->
        :ok = IO.puts("ERROR: :enoent #{path}")
        :ok
    end
  end

  def save_at_records_to_file(records, path) when is_binary(records) do
    case File.open(path |> Path.absname(), [:utf8, :write]) do
      {:ok, file} ->
        :ok = IO.puts(file, records)
        :ok = File.close(file)
        :ok

      {:error, :enoent} ->
        :ok = IO.puts("ERROR: :enoent #{path}")
        :ok
    end
  end

  def append_records_to_file(records, path) when is_binary(records) do
    {:ok, file} =
      path
      |> Path.absname()
      |> File.open([:utf8, :append])

    :ok = IO.puts(file, records)
    :ok = File.close(file)
    :ok
  end

  def count_csv_rows(filename) do
    binary =
      ("lib/" <> filename <> ".csv")
      |> Path.absname()
      |> File.read!()

    binary |> String.graphemes() |> Enum.count(&(&1 == "\n"))
  end

  def legislation_gov_uk_id_url(
        %LegalRegister{type_code: type_code, Number: number, Year: year} = record
      )
      when is_struct(record) do
    legislation_gov_uk_id_url(number, type_code, year)
  end

  def legislation_gov_uk_id_url(%{type_code: type_code, Number: number, Year: year} = record)
      when is_map(record) do
    legislation_gov_uk_id_url(number, type_code, year)
  end

  def legislation_gov_uk_id_url(number, type_code, year) do
    ~s[https://legislation.gov.uk/id/#{type_code}/#{year}/#{number}]
  end

  def resource_path(url) do
    case Regex.run(~r"^https:\/\/(?:www\.)?legislation\.gov\.uk(.*)", url) do
      [_, path] -> {:ok, path}
      _ -> {:error, "Problem getting path from url: #{url}"}
    end
  end

  @spec type_number_year(binary()) ::
          {UK.law_type_code(), UK.law_year(), UK.law_number()} | {:error, :no_match}
  def type_number_year("/id" <> path) do
    type_number_year(path)
  end

  # https://webarchive.nationalarchives.gov.uk/eu-exit/20201210174128/https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:12003TN02/16/C
  def type_number_year("https://webarchive.nationalarchives.gov.uk" <> _path) do
    {"eua"}
  end

  def type_number_year(path) do
    case Regex.run(~r/\/([a-z]*?)\/(\d{4})\/(\d+)/, path) do
      [_match, type, year, number] ->
        {type, number, year}

      nil ->
        IO.puts(~s/ERROR: No match for type_code, year & number for this #{path}/)
        {:error, :no_match}
    end
  end

  @spec split_name(String.t()) ::
          {:error, String.t()}
          | {String.t() | {integer(), integer()}, String.t() | {integer(), integer()},
             String.t() | {integer(), integer()}}
  def split_name(name) do
    # UK_TLA_type-code_year_number
    case Regex.run(~r/([a-z]*?)_(\d{4})_(.*)$/, name) do
      [_, type, year, number] ->
        {type, year, number}

      _ ->
        # UK_RSA_ukpga_1960_Eliz2/8-9/34
        case Regex.run(~r/([a-z]*?)_(\d{4})_(.*)$/, name) do
          [_, type, year, number] ->
            {type, year, number}

          nil ->
            {:error, ~s/no match for #{name}/}
        end
    end
  end

  def iso_date(date) do
    date = String.trim(date)

    case String.split(date, "/") do
      [day, month, year] ->
        "#{year}-#{month}-#{day}"

      [date] ->
        case String.split(date, "-") do
          [day, month, year] ->
            "#{year}-#{month}-#{day}"

          _ ->
            date
        end
    end
  end

  def yyyy_mm_dd(date) do
    [_, year, month, day] = Regex.run(~r/(\d{4})-(\d{2})-(\d{2})/, date)
    "#{day}/#{month}/#{year}"
  end

  def get_date_from_at_date_field(date) when is_binary(date) do
  end

  def duplicate_records(list) do
    list
    |> Enum.group_by(& &1)
    |> Enum.filter(fn
      {_, [_, _ | _]} -> true
      _ -> false
    end)
    |> Enum.map(fn {x, _} -> x end)
    |> Enum.sort()
  end

  @doc """
  Removes duped spaces in a line as captured by the marker
  e.g. "\\[::annex::\\]"
  """
  def rm_dupe_spaces(binary, regex) do
    # remove double, triple and quadruple spaces
    Regex.replace(
      ~r/^(#{regex}.*)/m,
      binary,
      fn _, x -> String.replace(x, ~r/[ ]{2,4}/m, " ") end
    )
  end

  @doc """
  %{"1": "A", "2": "B", ...}
  """
  def alphabet_map do
    Enum.reduce(
      Enum.zip(1..24, String.split("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "", trim: true)),
      %{},
      fn {x, y}, acc -> Map.put(acc, :"#{x}", y) end
    )
  end

  @doc """
  %{"A": 1, "B": 2, ...}
  """
  def alphabet_to_numeric_map_base do
    Enum.reduce(
      Enum.zip(String.split("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "", trim: true), 1..26),
      %{},
      fn {x, y}, acc -> Map.put(acc, :"#{x}", y) end
    )
  end

  @doc """
  %{"A" => 65, "B" => 66, ...}
  """
  def alphabet_to_numeric_map do
    Enum.reduce(
      Enum.zip(String.split("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "", trim: true), 65..(65 + 25)),
      %{},
      fn {x, y}, acc -> Map.put(acc, "#{x}", y) end
    )
    |> Map.put("", 64)
  end

  @doc """
  Columns on screen
  """
  def cols do
    {_, cols} = :io.columns()
    cols
  end

  def upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest

  def upcase_first_from_upcase_phrase(string),
    do: string |> String.split(" ") |> Enum.map_join(" ", &upcase_first_from_upcase/1)

  def upcase_first_from_upcase(<<first::utf8, rest::binary>>),
    do: <<first::utf8>> <> String.downcase(rest)

  def numericalise_ordinal(value) do
    ordinals = %{
      "first" => "1",
      "second" => "2",
      "third" => "3",
      "fourth" => "4",
      "fifth" => "5",
      "sixth" => "6",
      "seventh" => "7",
      "eighth" => "8",
      "ninth" => "9",
      "tenth" => "10",
      "eleventh" => "11",
      "twelfth" => "12",
      "thirteenth" => "13",
      "fourteenth" => "14",
      "fifteenth" => "15",
      "sixteenth" => "16",
      "seventeenth" => "17",
      "eighteenth" => "18",
      "nineteenth" => "19",
      "twentieth" => "20"
    }

    search = String.downcase(value)

    case Map.get(ordinals, search) do
      nil -> value
      x -> x
    end
  end

  @spec map_filter_out_empty_members(list()) :: list()
  def map_filter_out_empty_members(records) when is_list(records),
    do: Enum.map(records, &map_filter_out_empty_members(&1))

  @spec map_filter_out_empty_members(map()) :: map()
  def map_filter_out_empty_members(record) when is_map(record) do
    Map.filter(record, fn {_k, v} -> v not in [nil, "", []] end)
  end

  @spec maps_from_structs([]) :: []
  def maps_from_structs([]), do: []

  @spec maps_from_structs(list()) :: list()
  def maps_from_structs(records) when is_list(records) do
    Enum.map(records, &map_from_struct/1)
  end

  @spec map_from_struct(struct() | map()) :: map()
  def map_from_struct(record) when is_struct(record), do: Map.from_struct(record)
  def map_from_struct(record) when is_map(record), do: record

  @doc """
  Function to return the members
  """
  def delta_lists do
    x = ExPrompt.get("Old List")
    y = ExPrompt.get("New List")

    delta_lists(String.split(x, ","), String.split(y, ","))
    |> Enum.sort(:desc)
    |> Enum.join(",")
  end

  @spec delta_lists(list(), list()) :: list()
  def delta_lists(old, new) do
    old = convert_to_mapset(old)
    new = convert_to_mapset(new)

    MapSet.difference(new, old)
    |> MapSet.to_list()
  end

  def convert_to_mapset(list) when list in [nil, ""], do: MapSet.new()

  def convert_to_mapset(csv) when is_binary(csv) do
    csv
    |> String.split(",")
    |> Enum.map(&String.trim(&1))
    |> MapSet.new()
  end

  def convert_to_mapset(list) when is_list(list) do
    Enum.map(list, &String.trim(&1))
    |> MapSet.new()
  end

  def year_as_integer(year) when is_integer(year), do: year
  def year_as_integer(year) when is_binary(year), do: String.to_integer(year)

  @spec to_utf8(binary()) :: String.t()
  def to_utf8(binary), do: to_utf8(binary, "")

  defp to_utf8(<<codepoint::utf8, rest::binary>>, acc) do
    to_utf8(rest, <<acc::binary, codepoint::utf8>>)
  end

  defp to_utf8("", acc), do: acc

  defp to_utf8(_, acc), do: acc

  # ============================================================================
  # Legislation Normalization Functions
  # ============================================================================

  @doc """
  Normalizes legislation titles to prevent duplicates.

  Converts to proper title case with exceptions for small joining words.
  Works for both HSE and EA legislation parsing.

  ## Examples
      iex> normalize_legislation_title("HEALTH AND SAFETY AT WORK ACT")
      "Health and Safety at Work Act"

      iex> normalize_legislation_title("control of substances hazardous to health regulations")
      "Control of Substances Hazardous to Health Regulations"
  """
  @spec normalize_legislation_title(String.t() | nil) :: String.t() | nil
  def normalize_legislation_title(nil), do: nil

  def normalize_legislation_title(title) when is_binary(title) do
    title
    |> String.trim()
    # Strip leading "The " to align with legislation.gov.uk format
    |> strip_leading_the()
    # Strip trailing year (e.g., " 1974", " 2016") - year is stored separately
    |> strip_trailing_year()
    |> String.downcase()
    # Convert to proper title case
    |> String.split(" ")
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {word, index} -> title_case_word(word, index) end)
    |> clean_common_patterns()
  end

  # Strip leading "The " (case-insensitive) to match legislation.gov.uk format
  defp strip_leading_the(title) do
    case Regex.run(~r/^the\s+(.+)$/i, title) do
      [_, rest] -> rest
      _ -> title
    end
  end

  # Strip trailing year pattern (4-digit year at end, optionally with comma)
  # Examples: " 1974", ", 2016", " (2015)" -> removed
  defp strip_trailing_year(title) do
    title
    # Remove year in parentheses at end: "Foo (2015)" -> "Foo"
    |> String.replace(~r/\s*\(\d{4}\)\s*$/, "")
    # Remove year with optional comma: "Foo, 2015" or "Foo 2015" -> "Foo"
    |> String.replace(~r/,?\s+\d{4}\s*$/, "")
    |> String.trim()
  end

  # Words that should remain lowercase in title case (except at start)
  @small_words ~w[at of and the in on for with to by under from etc]

  # Always capitalize first word
  defp title_case_word(word, 0), do: capitalize_with_punctuation(word)
  defp title_case_word(word, _index) when word in @small_words, do: word

  defp title_case_word(word, _index) do
    # Check if word without leading punctuation is a small word
    stripped = String.replace(word, ~r/^[^\p{L}]+/, "")

    if stripped in @small_words do
      word
    else
      capitalize_with_punctuation(word)
    end
  end

  # Handle words with leading punctuation like "(england" -> "(England"
  defp capitalize_with_punctuation(word) do
    case Regex.run(~r/^([^\p{L}]*)(.*)$/, word) do
      [_, prefix, rest] when prefix != "" ->
        prefix <> String.capitalize(rest)

      _ ->
        String.capitalize(word)
    end
  end

  # Clean up common patterns and abbreviations
  defp clean_common_patterns(title) do
    title
    # Fix "etc." placement - must be lowercase
    |> String.replace(~r/\b[Ee]tc\.?\b/, "etc.")
    # Remove double dots that might have been created
    |> String.replace("etc..", "etc.")
    # Standardize "H&S" vs "health and safety"
    |> String.replace(~r/\bh&s\b/i, "Health and Safety")
    # Fix common abbreviations
    |> String.replace(~r/\bcdm\b/i, "Construction (Design and Management)")
    |> String.replace(~r/\bcoshh\b/i, "Control of Substances Hazardous to Health")
    |> String.replace(~r/\bpuwer\b/i, "Provision and Use of Work Equipment Regulations")
    |> String.replace(~r/\bdsear\b/i, "Dangerous Substances and Explosive Atmospheres")
    |> String.replace(~r/\bloler\b/i, "Lifting Operations and Lifting Equipment")
    |> String.replace(~r/\bcomah\b/i, "Control of Major Accident Hazards")
    # Ensure proper spacing
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  Determines legislation type from title and context.

  ## Examples
      iex> determine_legislation_type("Health and Safety at Work etc. Act")
      :act

      iex> determine_legislation_type("Control of Substances Hazardous to Health Regulations")
      :regulation
  """
  @spec determine_legislation_type(String.t()) :: :acop | :act | :order | :regulation
  def determine_legislation_type(title) when is_binary(title) do
    title_lower = String.downcase(title)

    cond do
      String.contains?(title_lower, "acop") or
          String.contains?(title_lower, "approved code of practice") ->
        :acop

      String.contains?(title_lower, "regulation") ->
        :regulation

      String.contains?(title_lower, "order") ->
        :order

      String.contains?(title_lower, "act") ->
        :act

      # Default to act
      true ->
        :act
    end
  end

  @doc """
  Extracts year from legislation title if present.

  ## Examples
      iex> extract_year_from_title("Health and Safety at Work Act 1974")
      1974

      iex> extract_year_from_title("Control of Substances Hazardous to Health Regulations 2002")
      2002

      iex> extract_year_from_title("Some Act without year")
      nil
  """
  @spec extract_year_from_title(String.t()) :: integer() | nil
  def extract_year_from_title(title) when is_binary(title) do
    case Regex.run(~r/\b((19|20)\d{2})\b/, title) do
      [_full_match, year_str, _prefix] -> String.to_integer(year_str)
      nil -> nil
    end
  end

  @doc """
  Extracts legislation number from title or context.

  For HSE: Usually not present in title, comes from lookup table
  For EA: May be present in structured data
  """
  @spec extract_number_from_context(String.t(), map()) :: integer() | nil
  def extract_number_from_context(_title, %{number: number}) when is_integer(number), do: number

  def extract_number_from_context(_title, %{"number" => number}) when is_integer(number),
    do: number

  def extract_number_from_context(_title, %{"number" => number}) when is_binary(number) do
    case Integer.parse(number) do
      {num, _} -> num
      :error -> nil
    end
  end

  def extract_number_from_context(_title, _context), do: nil

  @doc """
  Parses a legislation.gov.uk URL to extract the unique identifier components.

  UK legislation URLs follow the format: https://www.legislation.gov.uk/{type_code}/{year}/{number}

  ## Type Codes

  | Code | Description |
  |------|-------------|
  | ukpga | UK Public General Act |
  | uksi | UK Statutory Instrument |
  | ssi | Scottish Statutory Instrument |
  | wsi | Welsh Statutory Instrument |
  | nisr | Northern Ireland Statutory Rules |
  | nisi | NI Order in Council |
  | asp | Act of Scottish Parliament |
  | nia | NI Assembly Act |
  | apni | Act of NI Parliament |
  | ukla | UK Local Act |
  | mwa | Welsh Assembly Measure |

  ## Examples

      iex> parse_legislation_url("https://www.legislation.gov.uk/ukpga/1974/37")
      {:ok, %{type_code: "ukpga", year: 1974, number: "37"}}

      iex> parse_legislation_url("https://legislation.gov.uk/uksi/2015/51")
      {:ok, %{type_code: "uksi", year: 2015, number: "51"}}

      iex> parse_legislation_url("invalid-url")
      {:error, :invalid_url}

  ## Returns

  - `{:ok, %{type_code: String.t(), year: integer(), number: String.t()}}` on success
  - `{:error, :invalid_url}` if URL doesn't match expected format
  """
  @spec parse_legislation_url(String.t() | nil) ::
          {:ok, %{type_code: String.t(), year: integer(), number: String.t()}}
          | {:error, :invalid_url}
  def parse_legislation_url(nil), do: {:error, :invalid_url}
  def parse_legislation_url(""), do: {:error, :invalid_url}

  def parse_legislation_url(url) when is_binary(url) do
    # Match legislation.gov.uk URLs with type_code/year/number pattern
    # Handles both https://www.legislation.gov.uk and https://legislation.gov.uk
    case Regex.run(~r|legislation\.gov\.uk/(\w+)/(\d{4})/(\d+)|, url) do
      [_, type_code, year_str, number] ->
        {:ok,
         %{
           type_code: type_code,
           year: String.to_integer(year_str),
           number: number
         }}

      _ ->
        {:error, :invalid_url}
    end
  end

  @doc """
  Builds a legislation.gov.uk URL from components.

  ## Examples

      iex> build_legislation_url("ukpga", 1974, "37")
      "https://www.legislation.gov.uk/ukpga/1974/37"

      iex> build_legislation_url("uksi", 2015, 51)
      "https://www.legislation.gov.uk/uksi/2015/51"
  """
  @spec build_legislation_url(String.t(), integer(), String.t() | integer()) :: String.t()
  def build_legislation_url(type_code, year, number) do
    "https://www.legislation.gov.uk/#{type_code}/#{year}/#{number}"
  end

  @doc """
  Validates legislation data completeness.

  Returns {:ok, normalized_data} or {:error, reason}
  """
  @spec validate_legislation_data(map()) :: {:ok, map()} | {:error, String.t()}
  def validate_legislation_data(%{title: title} = data) when is_binary(title) and title != "" do
    normalized_title = normalize_legislation_title(title)
    legislation_type = determine_legislation_type(normalized_title)

    validated_data = %{
      legislation_title: normalized_title,
      legislation_type: legislation_type,
      legislation_year: data[:year] || data["year"] || extract_year_from_title(title),
      legislation_number:
        data[:number] || data["number"] || extract_number_from_context(title, data)
    }

    {:ok, validated_data}
  end

  def validate_legislation_data(%{title: title}) when title in [nil, ""] do
    {:error, "Legislation title cannot be empty"}
  end

  def validate_legislation_data(_data) do
    {:error, "Legislation data must include title"}
  end

  @doc """
  Calculates similarity between two legislation titles using trigram similarity.
  Returns a score between 0.0 and 1.0.
  """
  @spec calculate_title_similarity(String.t(), String.t()) :: float()
  def calculate_title_similarity(title1, title2) when is_binary(title1) and is_binary(title2) do
    # Normalize both titles for comparison
    norm1 = normalize_legislation_title(title1)
    norm2 = normalize_legislation_title(title2)

    # Simple Jaro-Winkler approximation for similarity
    String.jaro_distance(norm1, norm2)
  end

  def calculate_title_similarity(_, _), do: 0.0
end
