defmodule EhsEnforcement.Enforcement.Legislation do
  @moduledoc """
  Represents legislation that can be referenced in enforcement actions.

  This is a lookup/reference table for normalizing legislation data across
  cases, notices, and offences. Contains core legislation information like
  Acts, Regulations, and Orders.

  Examples:
  - Health and Safety at Work etc. Act 1974
  - The Construction (Design and Management) Regulations 2015
  - The Work at Height Regulations 2005
  """

  use Ash.Resource,
    domain: EhsEnforcement.Enforcement,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("legislation")
    repo(EhsEnforcement.Repo)

    custom_indexes do
      # Unique constraint for legislation.gov.uk identification (Year + Number + Type Code)
      index([:legislation_year, :legislation_number, :legislation_type_code],
        name: "legislation_gov_uk_unique",
        unique: true,
        where:
          "legislation_year IS NOT NULL AND legislation_number IS NOT NULL AND legislation_type_code IS NOT NULL"
      )

      # Unique constraint for legacy title-based identification (for scraped data without legislation.gov.uk codes)
      index([:legislation_title, :legislation_year, :legislation_number],
        name: "legislation_title_year_number_unique",
        unique: true,
        where: "legislation_type_code IS NULL"
      )

      # Performance indexes for filtering and search
      index([:legislation_type], name: "legislation_type_index")
      index([:legislation_type_code], name: "legislation_type_code_index")
      index([:legislation_year], name: "legislation_year_index")

      # pg_trgm GIN index for fuzzy text search on legislation titles
      index([:legislation_title], name: "legislation_title_gin_trgm", using: "GIN")
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :legislation_title, :string do
      allow_nil?(false)
      description "Full title of the legislation (e.g., 'Health and Safety at Work etc. Act')"
    end

    attribute :legislation_year, :integer do
      description "Year the legislation was enacted (e.g., 1974)"
      constraints(min: 1800, max: 2100)
    end

    attribute :legislation_number, :string do
      description "Official number/chapter of the legislation (can be alphanumeric for old laws, e.g., '33', 'c.33')"
    end

    attribute :legislation_type, :atom do
      allow_nil?(false)
      description "Type of legislation (high-level categorization)"
      constraints(one_of: [:act, :regulation, :order, :acop, :measure, :rule, :scheme])
      default(:act)
    end

    attribute :legislation_type_code, :string do
      description "legislation.gov.uk type code (e.g., 'ukpga', 'uksi', 'ukla', 'asp', 'anaw', 'ssi', 'wsi')"
    end

    attribute :legislation_url, :string do
      description "Canonical URL from legislation.gov.uk"
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  relationships do
    has_many :offences, EhsEnforcement.Enforcement.Offence
  end

  identities do
    # Primary identity for legislation.gov.uk data (Year + Number + Type Code)
    identity :unique_gov_uk, [:legislation_year, :legislation_number, :legislation_type_code] do
      nils_distinct?(false)
    end

    # Secondary identity for legacy scraped data (Title + Year + Number)
    identity :unique_legislation, [:legislation_title, :legislation_year, :legislation_number] do
      nils_distinct?(false)
    end

    # Tertiary identity for title + year only (useful for fuzzy matching)
    identity :unique_title_year, [:legislation_title, :legislation_year] do
      nils_distinct?(false)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :legislation_title,
        :legislation_year,
        :legislation_number,
        :legislation_type,
        :legislation_type_code,
        :legislation_url
      ])

      validate(present(:legislation_title))
      validate(present(:legislation_type))

      # Normalize title before creation
      change(fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :legislation_title) do
          nil ->
            changeset

          title ->
            normalized_title = EhsEnforcement.Utility.normalize_legislation_title(title)
            Ash.Changeset.force_change_attribute(changeset, :legislation_title, normalized_title)
        end
      end)

      # Auto-determine type if not provided
      change(fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :legislation_type) do
          nil ->
            title = Ash.Changeset.get_attribute(changeset, :legislation_title)

            if title do
              auto_type = EhsEnforcement.Utility.determine_legislation_type(title)
              Ash.Changeset.force_change_attribute(changeset, :legislation_type, auto_type)
            else
              changeset
            end

          _type ->
            changeset
        end
      end)

      # Validate year range if provided
      validate(fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :legislation_year) do
          nil ->
            :ok

          year when year >= 1800 and year <= 2100 ->
            :ok

          invalid_year ->
            {:error,
             field: :legislation_year,
             message: "Year must be between 1800 and 2100, got: #{invalid_year}"}
        end
      end)

      # Validate number if provided (now accepts alphanumeric strings)
      validate(fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :legislation_number) do
          nil ->
            :ok

          number when is_binary(number) and byte_size(number) > 0 ->
            :ok

          invalid_number ->
            {:error,
             field: :legislation_number,
             message: "Number must be a non-empty string, got: #{invalid_number}"}
        end
      end)
    end

    update :update do
      primary?(true)

      accept([
        :legislation_title,
        :legislation_year,
        :legislation_number,
        :legislation_type,
        :legislation_type_code,
        :legislation_url
      ])

      require_atomic?(false)

      # Normalize title on update as well
      change(fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :legislation_title) do
          nil ->
            changeset

          title ->
            normalized_title = EhsEnforcement.Utility.normalize_legislation_title(title)
            Ash.Changeset.force_change_attribute(changeset, :legislation_title, normalized_title)
        end
      end)
    end

    read :by_type do
      argument(:legislation_type, :atom, allow_nil?: false)
      filter(expr(legislation_type == ^arg(:legislation_type)))
    end

    read :by_year_range do
      argument(:start_year, :integer, allow_nil?: false)
      argument(:end_year, :integer, allow_nil?: false)

      filter(expr(legislation_year >= ^arg(:start_year) and legislation_year <= ^arg(:end_year)))
    end

    read :search_title do
      argument(:search_term, :string, allow_nil?: false)

      filter(expr(fragment("? % ?", legislation_title, ^arg(:search_term))))
    end
  end

  calculations do
    calculate :full_reference, :string do
      description "Complete legislation reference including year and number"

      calculation(
        expr(
          cond do
            is_nil(legislation_year) and is_nil(legislation_number) ->
              legislation_title

            is_nil(legislation_number) ->
              legislation_title <> " " <> to_string(legislation_year)

            is_nil(legislation_year) ->
              legislation_title <> " No. " <> to_string(legislation_number)

            true ->
              legislation_title <>
                " " <> to_string(legislation_year) <> " No. " <> to_string(legislation_number)
          end
        )
      )
    end
  end

  code_interface do
    define(:create)
    define(:by_type)
    define(:by_year_range)
    define(:search_title)
  end
end
