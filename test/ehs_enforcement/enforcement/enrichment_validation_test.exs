defmodule EhsEnforcement.Enforcement.EnrichmentValidationTest do
  use EhsEnforcement.DataCase, async: true

  require Ash.Query
  import Ash.Expr

  alias EhsEnforcement.Enforcement

  setup do
    # Create test user (professional validator) with OAuth
    unique_id = System.unique_integer([:positive])

    user_info = %{
      "email" => "validator-#{unique_id}@example.com",
      "name" => "Test Validator",
      "login" => "testvalidator#{unique_id}",
      "id" => unique_id,
      "avatar_url" => "https://github.com/images/avatars/testvalidator",
      "html_url" => "https://github.com/testvalidator"
    }

    oauth_tokens = %{
      "access_token" => "test_access_token",
      "token_type" => "Bearer"
    }

    {:ok, user} =
      Ash.create(
        EhsEnforcement.Accounts.User,
        %{
          user_info: user_info,
          oauth_tokens: oauth_tokens
        },
        action: :register_with_github
      )

    # Create test agency, offender, and case
    {:ok, agency} =
      Enforcement.create_agency(%{
        code: :hse,
        name: "Health and Safety Executive"
      })

    {:ok, offender} =
      Enforcement.create_offender(%{
        name: "Test Company Ltd",
        local_authority: "Manchester"
      })

    {:ok, test_case} =
      Enforcement.create_case(%{
        agency_id: agency.id,
        offender_id: offender.id,
        regulator_id: "HSE001",
        offence_result: "Guilty",
        offence_fine: Decimal.new("10000.00"),
        offence_action_date: ~D[2024-01-15],
        offence_breaches: "Health and Safety at Work etc. Act 1974"
      })

    # Create test enrichment
    {:ok, enrichment} =
      Enforcement.create_enrichment(%{
        case_id: test_case.id,
        regulation_links: [
          %{"act" => "HSE Act 1974", "section" => "Section 2", "relevance_score" => 0.95}
        ],
        benchmark_analysis: %{"average_fine" => 15000},
        layperson_summary: "Test summary",
        professional_summary: "Professional summary",
        model_version: "gpt-4-turbo"
      })

    %{
      user: user,
      agency: agency,
      offender: offender,
      test_case: test_case,
      enrichment: enrichment
    }
  end

  describe "enrichment_validation resource - creation" do
    test "creates validation with all fields", %{enrichment: enrichment, user: user} do
      attrs = %{
        enrichment_id: enrichment.id,
        user_id: user.id,
        section: :regulation_links,
        rating: 5,
        corrections: "All regulation references are accurate and comprehensive",
        validation_notes: "Verified against official legislation database"
      }

      assert {:ok, validation} = Enforcement.create_validation(attrs)

      assert validation.enrichment_id == enrichment.id
      assert validation.user_id == user.id
      assert validation.section == :regulation_links
      assert validation.rating == 5
      assert validation.corrections =~ "accurate"
      assert validation.validation_notes =~ "official legislation"
      assert validation.validated_at != nil
    end

    test "creates minimal validation", %{enrichment: enrichment, user: user} do
      attrs = %{
        enrichment_id: enrichment.id,
        user_id: user.id,
        section: :benchmark_analysis,
        rating: 4
      }

      assert {:ok, validation} = Enforcement.create_validation(attrs)

      assert validation.section == :benchmark_analysis
      assert validation.rating == 4
      assert validation.corrections == nil
    end

    test "creates validations for all section types", %{enrichment: enrichment, user: user} do
      sections = [
        :regulation_links,
        :benchmark_analysis,
        :pattern_detection,
        :layperson_summary,
        :professional_summary,
        :auto_tags,
        :overall
      ]

      for section <- sections do
        attrs = %{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: section,
          rating: 4
        }

        assert {:ok, validation} = Enforcement.create_validation(attrs)
        assert validation.section == section
      end
    end
  end

  describe "enrichment_validation resource - validation rules" do
    test "requires enrichment_id", %{user: user} do
      attrs = %{
        user_id: user.id,
        section: :regulation_links,
        rating: 5
      }

      assert {:error, %Ash.Error.Invalid{}} = Enforcement.create_validation(attrs)
    end

    test "requires user_id", %{enrichment: enrichment} do
      attrs = %{
        enrichment_id: enrichment.id,
        section: :regulation_links,
        rating: 5
      }

      assert {:error, %Ash.Error.Invalid{}} = Enforcement.create_validation(attrs)
    end

    test "requires section", %{enrichment: enrichment, user: user} do
      attrs = %{
        enrichment_id: enrichment.id,
        user_id: user.id,
        rating: 5
      }

      assert {:error, %Ash.Error.Invalid{}} = Enforcement.create_validation(attrs)
    end

    test "requires rating", %{enrichment: enrichment, user: user} do
      attrs = %{
        enrichment_id: enrichment.id,
        user_id: user.id,
        section: :regulation_links
      }

      assert {:error, %Ash.Error.Invalid{}} = Enforcement.create_validation(attrs)
    end

    test "enforces rating between 1 and 5", %{enrichment: enrichment, user: user} do
      # Test rating too low
      attrs_low = %{
        enrichment_id: enrichment.id,
        user_id: user.id,
        section: :regulation_links,
        rating: 0
      }

      assert {:error, %Ash.Error.Invalid{}} = Enforcement.create_validation(attrs_low)

      # Test rating too high
      attrs_high = %{
        enrichment_id: enrichment.id,
        user_id: user.id,
        section: :regulation_links,
        rating: 6
      }

      assert {:error, %Ash.Error.Invalid{}} = Enforcement.create_validation(attrs_high)

      # Test valid ratings
      for rating <- 1..5 do
        attrs = %{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :"section_#{rating}",
          rating: rating
        }

        # Use appropriate section enum values
        section =
          case rating do
            1 -> :regulation_links
            2 -> :benchmark_analysis
            3 -> :pattern_detection
            4 -> :layperson_summary
            5 -> :professional_summary
          end

        attrs = Map.put(attrs, :section, section)

        case Enforcement.create_validation(attrs) do
          {:ok, validation} ->
            assert validation.rating == rating

          {:error, error} ->
            # May fail due to unique constraint if already created
            flunk("Failed to create validation: #{inspect(error)}")
        end
      end
    end

    test "prevents duplicate validation for same section by same user", %{
      enrichment: enrichment,
      user: user
    } do
      attrs = %{
        enrichment_id: enrichment.id,
        user_id: user.id,
        section: :regulation_links,
        rating: 5
      }

      # First validation succeeds
      assert {:ok, _validation} = Enforcement.create_validation(attrs)

      # Second validation for same section by same user should fail
      assert {:error, %Ash.Error.Invalid{}} = Enforcement.create_validation(attrs)
    end

    test "allows different users to validate same section", %{enrichment: enrichment, user: user} do
      # Create second user with OAuth
      unique_id = System.unique_integer([:positive])

      user_info2 = %{
        "email" => "validator2-#{unique_id}@example.com",
        "name" => "Test Validator 2",
        "login" => "testvalidator2#{unique_id}",
        "id" => unique_id
      }

      oauth_tokens2 = %{
        "access_token" => "test_access_token_2",
        "token_type" => "Bearer"
      }

      {:ok, user2} =
        Ash.create(
          EhsEnforcement.Accounts.User,
          %{
            user_info: user_info2,
            oauth_tokens: oauth_tokens2
          },
          action: :register_with_github
        )

      # First user validates
      attrs1 = %{
        enrichment_id: enrichment.id,
        user_id: user.id,
        section: :regulation_links,
        rating: 5
      }

      assert {:ok, _} = Enforcement.create_validation(attrs1)

      # Second user validates same section - should succeed
      attrs2 = %{
        enrichment_id: enrichment.id,
        user_id: user2.id,
        section: :regulation_links,
        rating: 4
      }

      assert {:ok, validation2} = Enforcement.create_validation(attrs2)
      assert validation2.user_id == user2.id
    end

    test "allows same user to validate different sections", %{enrichment: enrichment, user: user} do
      # Validate regulation_links
      {:ok, _} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 5
        })

      # Validate benchmark_analysis - should succeed
      {:ok, validation2} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :benchmark_analysis,
          rating: 4
        })

      assert validation2.section == :benchmark_analysis
    end
  end

  describe "enrichment_validation resource - query actions" do
    test "queries validations by enrichment", %{enrichment: enrichment, user: user} do
      # Create multiple validations for the enrichment
      {:ok, _v1} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 5
        })

      {:ok, _v2} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :benchmark_analysis,
          rating: 4
        })

      # Query all validations for this enrichment
      {:ok, validations} = Enforcement.list_validations_by_enrichment(enrichment.id)

      assert length(validations) == 2
      assert Enum.all?(validations, fn v -> v.enrichment_id == enrichment.id end)
    end

    test "queries validations by user", %{
      enrichment: enrichment,
      user: user,
      test_case: test_case
    } do
      # Create another enrichment
      {:ok, enrichment2} =
        Enforcement.create_enrichment(%{
          case_id: test_case.id,
          professional_summary: "Another case enrichment",
          model_version: "gpt-4"
        })

      # Create validations by same user on different enrichments
      {:ok, _v1} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 5
        })

      {:ok, _v2} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment2.id,
          user_id: user.id,
          section: :professional_summary,
          rating: 4
        })

      # Query all validations by this user
      {:ok, validations} = Enforcement.list_validations_by_user(user.id)

      assert length(validations) == 2
      assert Enum.all?(validations, fn v -> v.user_id == user.id end)
    end

    test "queries validations by section", %{enrichment: enrichment, user: user} do
      # Create validations for different sections
      {:ok, _} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 5
        })

      {:ok, _} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :benchmark_analysis,
          rating: 4
        })

      # Query by specific section
      {:ok, reg_validations} = Enforcement.list_validations_by_section(:regulation_links)

      assert length(reg_validations) >= 1
      assert Enum.all?(reg_validations, fn v -> v.section == :regulation_links end)
    end

    test "queries high quality validations (4-5 stars)", %{enrichment: enrichment, user: user} do
      # Create mix of ratings
      {:ok, _low} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 2
        })

      {:ok, _high1} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :benchmark_analysis,
          rating: 4
        })

      {:ok, _high2} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :pattern_detection,
          rating: 5
        })

      # Query high quality validations
      {:ok, high_quality} = Enforcement.list_high_quality_validations()

      # Should only include ratings >= 4
      assert Enum.all?(high_quality, fn v -> v.rating >= 4 end)
    end

    test "queries validations needing attention (1-2 stars)", %{
      enrichment: enrichment,
      user: user
    } do
      # Create mix of ratings
      {:ok, _low1} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 1
        })

      {:ok, _low2} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :benchmark_analysis,
          rating: 2
        })

      {:ok, _high} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :pattern_detection,
          rating: 5
        })

      # Query validations needing attention
      {:ok, needs_attention} = Enforcement.list_validations_needing_attention()

      # Should only include ratings <= 2
      assert Enum.all?(needs_attention, fn v -> v.rating <= 2 end)
    end

    test "queries recent validations (last 30 days)", %{enrichment: enrichment, user: user} do
      {:ok, validation} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 5
        })

      {:ok, recent} = Enforcement.list_recent_validations()

      # Should include our just-created validation
      assert Enum.any?(recent, fn v -> v.id == validation.id end)
    end
  end

  describe "enrichment_validation resource - update and delete" do
    test "updates validation rating and corrections", %{enrichment: enrichment, user: user} do
      {:ok, validation} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 4,
          corrections: "Original corrections"
        })

      # Update validation
      {:ok, updated} =
        Enforcement.update_validation(validation, %{
          rating: 5,
          corrections: "Updated corrections after review"
        })

      assert updated.rating == 5
      assert updated.corrections == "Updated corrections after review"

      # enrichment_id, user_id, section should be immutable
      assert updated.enrichment_id == enrichment.id
      assert updated.user_id == user.id
      assert updated.section == :regulation_links
    end

    test "destroys validation", %{enrichment: enrichment, user: user} do
      {:ok, validation} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 5
        })

      assert :ok = Enforcement.destroy_validation(validation)

      # Should not be found
      assert_raise Ash.Error.Invalid, fn ->
        Enforcement.get_validation!(validation.id)
      end
    end
  end

  describe "enrichment_validation resource - calculations" do
    test "is_positive calculation for high ratings", %{enrichment: enrichment, user: user} do
      {:ok, high_rating} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 5
        })

      loaded = Enforcement.get_validation!(high_rating.id, load: [:is_positive])
      assert loaded.is_positive == true

      {:ok, low_rating} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :benchmark_analysis,
          rating: 2
        })

      loaded2 = Enforcement.get_validation!(low_rating.id, load: [:is_positive])
      assert loaded2.is_positive == false
    end

    test "is_negative calculation for low ratings", %{enrichment: enrichment, user: user} do
      {:ok, low_rating} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 1
        })

      loaded = Enforcement.get_validation!(low_rating.id, load: [:is_negative])
      assert loaded.is_negative == true

      {:ok, high_rating} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :benchmark_analysis,
          rating: 5
        })

      loaded2 = Enforcement.get_validation!(high_rating.id, load: [:is_negative])
      assert loaded2.is_negative == false
    end

    test "has_corrections calculation", %{enrichment: enrichment, user: user} do
      {:ok, with_corrections} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 4,
          corrections: "Some corrections here"
        })

      loaded = Enforcement.get_validation!(with_corrections.id, load: [:has_corrections])
      assert loaded.has_corrections == true

      {:ok, without_corrections} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :benchmark_analysis,
          rating: 5
        })

      loaded2 = Enforcement.get_validation!(without_corrections.id, load: [:has_corrections])
      assert loaded2.has_corrections == false
    end
  end

  describe "enrichment_validation resource - helper functions" do
    test "calculates validation percentage for enrichment", %{enrichment: enrichment, user: user} do
      # Create validations for 3 out of 5 main sections
      {:ok, _} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 5
        })

      {:ok, _} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :benchmark_analysis,
          rating: 4
        })

      {:ok, _} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :pattern_detection,
          rating: 5
        })

      # Calculate percentage (3 out of 5 sections = 60%)
      percentage =
        EhsEnforcement.Enforcement.EnrichmentValidation.calculate_validation_percentage(
          enrichment.id
        )

      assert percentage == 60
    end

    test "calculates average rating for enrichment", %{enrichment: enrichment, user: user} do
      # Create validations with different ratings
      {:ok, _} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 5
        })

      {:ok, _} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :benchmark_analysis,
          rating: 4
        })

      {:ok, _} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :pattern_detection,
          rating: 3
        })

      # Calculate average (5 + 4 + 3 = 12 / 3 = 4.0)
      average =
        EhsEnforcement.Enforcement.EnrichmentValidation.calculate_average_rating(enrichment.id)

      assert average == 4.0
    end

    test "calculates reputation score for user", %{
      enrichment: enrichment,
      user: user,
      test_case: test_case
    } do
      # Create multiple high-quality validations (4-5 stars)
      {:ok, _} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 5
        })

      {:ok, _} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :benchmark_analysis,
          rating: 4
        })

      # Create another enrichment and validation
      {:ok, enrichment2} =
        Enforcement.create_enrichment(%{
          case_id: test_case.id,
          professional_summary: "Another enrichment",
          model_version: "gpt-4"
        })

      {:ok, _} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment2.id,
          user_id: user.id,
          section: :professional_summary,
          rating: 5
        })

      # Calculate reputation score (should be 3 high-quality validations)
      score =
        EhsEnforcement.Enforcement.EnrichmentValidation.calculate_reputation_score(user.id)

      assert score == 3
    end
  end

  describe "enrichment_validation resource - relationships" do
    test "loads enrichment relationship", %{enrichment: enrichment, user: user} do
      {:ok, validation} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 5
        })

      loaded = Enforcement.get_validation!(validation.id, load: [:enrichment])

      assert loaded.enrichment.id == enrichment.id
      assert loaded.enrichment.model_version == "gpt-4-turbo"
    end

    test "loads user relationship", %{enrichment: enrichment, user: user} do
      {:ok, validation} =
        Enforcement.create_validation(%{
          enrichment_id: enrichment.id,
          user_id: user.id,
          section: :regulation_links,
          rating: 5
        })

      loaded = Enforcement.get_validation!(validation.id, load: [:user])

      assert loaded.user.id == user.id
      assert loaded.user.email == user.email
    end
  end
end
