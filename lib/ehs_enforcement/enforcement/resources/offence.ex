defmodule EhsEnforcement.Enforcement.Offence do
  @moduledoc """
  Unified resource representing legislative breaches and violations in enforcement actions.

  Consolidates the previous `breaches` (HSE) and `violations` (EA) tables into a single
  resource that can handle both use cases:

  - HSE Cases: Simple breach descriptions with legislation references
  - EA Cases: Complex multi-violation scenarios with individual fines and sequences

  Each offence:
  - Can be associated with a case (court action) and/or notice (enforcement notice)
  - References specific legislation through normalized lookup
  - May have financial penalties and sequence information (EA pattern)
  """

  use Ash.Resource,
    domain: EhsEnforcement.Enforcement,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshEvents.Events],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table("offences")
    repo(EhsEnforcement.Repo)

    identity_wheres_to_sql(
      unique_offence_reference: "offence_reference IS NOT NULL",
      unique_case_sequence: "case_id IS NOT NULL AND sequence_number IS NOT NULL"
    )

    custom_indexes do
      # Foreign key indexes for performance
      index([:case_id], name: "offences_case_id_index")
      index([:notice_id], name: "offences_notice_id_index")
      index([:legislation_id], name: "offences_legislation_id_index")

      # Composite indexes for common query patterns
      index([:case_id, :sequence_number], name: "offences_case_sequence_index")
      index([:legislation_id, :fine], name: "offences_legislation_fine_index")

      # Performance indexes for filtering
      index([:fine], name: "offences_fine_index")
      index([:sequence_number], name: "offences_sequence_index")

      # Unique constraints
      index([:offence_reference],
        name: "offences_reference_unique",
        unique: true,
        where: "offence_reference IS NOT NULL"
      )

      # pg_trgm GIN indexes for fuzzy text search
      index([:offence_description], name: "offences_description_gin_trgm", using: "GIN")
      index([:offence_reference], name: "offences_reference_gin_trgm", using: "GIN")
      index([:legislation_part], name: "offences_legislation_part_gin_trgm", using: "GIN")
    end
  end

  pub_sub do
    module(EhsEnforcement.PubSub)
    prefix("offence")

    publish(:create, ["created", :id])
    publish(:create, ["created"])
    publish(:update, ["updated", :id])
    publish(:update, ["updated"])
    publish(:destroy, ["deleted", :id])
    publish(:bulk_create, ["bulk_created"])
  end

  attributes do
    uuid_primary_key(:id)

    # Core offence details
    attribute :offence_description, :string do
      description "Description of the specific breach or violation"
    end

    attribute :offence_reference, :string do
      description "External reference for the offence (e.g., EA case reference 'SW/A/2010/2051079/01')"
    end

    # Legislation details
    attribute :legislation_part, :string do
      description "Specific part, section, or regulation of the legislation (e.g., 'Section 33', 'Regulation 4')"
    end

    # Financial and sequence information (primarily for EA cases)
    attribute :fine, :decimal do
      description "Fine amount for this specific offence"
      constraints(min: 0)
    end

    attribute :sequence_number, :integer do
      description "Order/sequence within parent case (for multi-violation EA cases)"
      constraints(min: 1)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :case, EhsEnforcement.Enforcement.Case do
      description "Associated enforcement case (court action)"
    end

    belongs_to :notice, EhsEnforcement.Enforcement.Notice do
      description "Associated enforcement notice"
    end

    belongs_to :legislation, EhsEnforcement.Enforcement.Legislation do
      allow_nil?(false)
      description "Referenced legislation for this offence"
    end
  end

  identities do
    identity(:unique_offence_reference, [:offence_reference],
      where: expr(not is_nil(offence_reference))
    )

    identity(:unique_case_sequence, [:case_id, :sequence_number],
      where: expr(not is_nil(case_id) and not is_nil(sequence_number))
    )
  end

  events do
    event_log(EhsEnforcement.Events.Event)
    current_action_versions(create: 1, update: 1, bulk_create: 1)
    only_actions([:create, :update, :bulk_create])
  end

  actions do
    defaults([:read, :update, :destroy])

    create :create do
      primary?(true)

      accept([
        :offence_description,
        :offence_reference,
        :legislation_part,
        :fine,
        :sequence_number,
        :case_id,
        :notice_id,
        :legislation_id
      ])

      validate(present(:legislation_id))

      # At least one of case_id or notice_id should be present
      validate(fn changeset, _context ->
        case_id = Ash.Changeset.get_attribute(changeset, :case_id)
        notice_id = Ash.Changeset.get_attribute(changeset, :notice_id)

        if is_nil(case_id) and is_nil(notice_id) do
          {:error,
           field: :base, message: "Offence must be associated with either a case or notice"}
        else
          :ok
        end
      end)
    end

    # Query actions
    read :by_case do
      argument(:case_id, :uuid, allow_nil?: false)
      filter(expr(case_id == ^arg(:case_id)))

      prepare(fn query, _context ->
        Ash.Query.sort(query, [:sequence_number, :created_at])
      end)
    end

    read :by_notice do
      argument(:notice_id, :uuid, allow_nil?: false)
      filter(expr(notice_id == ^arg(:notice_id)))
    end

    read :by_legislation do
      argument(:legislation_id, :uuid, allow_nil?: false)
      filter(expr(legislation_id == ^arg(:legislation_id)))
    end

    read :by_reference do
      argument(:offence_reference, :string, allow_nil?: false)
      filter(expr(offence_reference == ^arg(:offence_reference)))
    end

    read :with_fines do
      filter(expr(not is_nil(fine) and fine > 0))

      prepare(fn query, _context ->
        Ash.Query.sort(query, fine: :desc)
      end)
    end

    read :search_description do
      argument(:search_term, :string, allow_nil?: false)

      filter(expr(fragment("? % ?", offence_description, ^arg(:search_term))))
    end

    # Bulk creation for EA multi-violation scenarios
    create :bulk_create do
      description "Batch processing for creating multiple offences efficiently"

      argument(:offences_data, {:array, :map}, allow_nil?: false)
      argument(:case_id, :uuid)
      argument(:notice_id, :uuid)

      change(fn changeset, _context ->
        offences_data = Ash.Changeset.get_argument(changeset, :offences_data)
        case_id = Ash.Changeset.get_argument(changeset, :case_id)
        notice_id = Ash.Changeset.get_argument(changeset, :notice_id)

        # Validate at least one parent is provided
        if is_nil(case_id) and is_nil(notice_id) do
          Ash.Changeset.add_error(changeset,
            field: :base,
            message: "Either case_id or notice_id must be provided for bulk creation"
          )
        else
          results = %{created: 0, errors: []}

          final_results =
            Enum.reduce(offences_data, results, fn offence_data, acc ->
              # Add parent reference to each offence
              enhanced_data =
                offence_data
                |> maybe_add_parent(:case_id, case_id)
                |> maybe_add_parent(:notice_id, notice_id)

              case Ash.create(__MODULE__, enhanced_data, domain: EhsEnforcement.Enforcement) do
                {:ok, _offence} ->
                  %{acc | created: acc.created + 1}

                {:error, error} ->
                  error_msg = "Failed to create offence: #{inspect(error)}"
                  %{acc | errors: [error_msg | acc.errors]}
              end
            end)

          success_msg = "Bulk create completed: #{final_results.created} offences created"

          if length(final_results.errors) > 0 do
            error_msg = "#{success_msg}, #{length(final_results.errors)} errors"
            Ash.Changeset.add_error(changeset, field: :bulk_errors, message: error_msg)
          else
            Ash.Changeset.add_error(changeset, field: :bulk_result, message: success_msg)
          end
        end
      end)
    end
  end

  calculations do
    calculate :total_financial_penalty, :decimal do
      description "Total financial penalty (fine + any additional costs)"
      calculation(expr(coalesce(fine, 0)))
    end

    calculate :legislation_reference, :string do
      description "Combined legislation and part reference"

      calculation(
        expr(
          if is_nil(legislation_part) do
            legislation.legislation_title
          else
            legislation.legislation_title <> " - " <> legislation_part
          end
        )
      )

      load([:legislation])
    end

    calculate :parent_type, :string do
      description "Type of parent record: 'Case' or 'Notice'"

      calculation(
        expr(
          cond do
            not is_nil(case_id) -> "Case"
            not is_nil(notice_id) -> "Notice"
            true -> "Unknown"
          end
        )
      )
    end

    calculate :parent_reference, :string do
      description "Reference number from parent case or notice"

      calculation(
        expr(
          cond do
            not is_nil(case_id) -> case.case_reference
            not is_nil(notice_id) -> notice.regulator_ref_number
            true -> nil
          end
        )
      )

      load([:case, :notice])
    end

    calculate :severity_category, :string do
      description "Severity category based on fine amount: Low (< £1000), Medium (£1000-£10000), High (> £10000)"

      calculation(
        expr(
          cond do
            is_nil(fine) or fine == 0 -> "None"
            fine < 1000 -> "Low"
            fine < 10000 -> "Medium"
            true -> "High"
          end
        )
      )
    end

    calculate :has_sequence, :boolean do
      description "True if this offence is part of a multi-violation sequence"
      calculation(expr(not is_nil(sequence_number)))
    end
  end

  code_interface do
    define(:create)
    define(:by_case)
    define(:by_notice)
    define(:by_legislation)
    define(:by_reference)
    define(:with_fines)
    define(:search_description)
    define(:bulk_create)
  end

  # Helper function for bulk creation
  defp maybe_add_parent(data, _key, nil), do: data
  defp maybe_add_parent(data, key, value), do: Map.put(data, key, value)
end
