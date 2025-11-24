defmodule EhsEnforcementWeb.Api.MatchReviewsController do
  use EhsEnforcementWeb, :controller

  alias EhsEnforcement.Enforcement

  @doc """
  List offender match reviews with optional filtering by status.

  GET /api/match-reviews?status=pending
  """
  def index(conn, params) do
    current_user = conn.assigns[:current_user]
    status = params["status"]

    result =
      if status do
        # Convert string status to atom
        atom_status = String.to_existing_atom(status)
        Enforcement.reviews_by_status(atom_status, actor: current_user)
      else
        # List all reviews (default to pending)
        Enforcement.pending_reviews(actor: current_user)
      end

    case result do
      {:ok, reviews} ->
        conn
        |> json(%{
          success: true,
          data: serialize_reviews(reviews)
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to load reviews",
          details: inspect(reason)
        })
    end
  end

  @doc """
  Get a single match review by ID with full details.

  GET /api/match-reviews/:id
  """
  def show(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]

    case Enforcement.get_review(id, actor: current_user, load: [:offender, :reviewed_by]) do
      {:ok, review} ->
        conn
        |> json(%{
          success: true,
          data: serialize_review_detail(review)
        })

      {:error, %Ash.Error.Query.NotFound{}} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          error: "Review not found"
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to load review",
          details: inspect(reason)
        })
    end
  end

  @doc """
  Approve a match review and update the offender with selected company number.

  POST /api/match-reviews/:id/approve
  Body: %{"company_number" => "12345678"}
  """
  def approve(conn, %{"id" => id, "company_number" => company_number}) do
    current_user = conn.assigns[:current_user]

    with {:ok, review} <- Enforcement.get_review(id, actor: current_user),
         {:ok, updated_review} <-
           Enforcement.approve_match(
             review,
             [reviewed_by_id: current_user.id, selected_company_number: company_number],
             actor: current_user
           ) do
      conn
      |> json(%{
        success: true,
        message: "Match approved successfully",
        data: serialize_review_detail(updated_review)
      })
    else
      {:error, %Ash.Error.Query.NotFound{}} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          error: "Review not found"
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: "Failed to approve match",
          details: inspect(reason)
        })
    end
  end

  @doc """
  Skip/reject a match review.

  POST /api/match-reviews/:id/skip
  """
  def skip(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]

    with {:ok, review} <- Enforcement.get_review(id, actor: current_user),
         {:ok, updated_review} <-
           Enforcement.skip_match(review, reviewed_by_id: current_user.id) do
      conn
      |> json(%{
        success: true,
        message: "Match skipped successfully",
        data: serialize_review_detail(updated_review)
      })
    else
      {:error, %Ash.Error.Query.NotFound{}} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          error: "Review not found"
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: "Failed to skip match",
          details: inspect(reason)
        })
    end
  end

  @doc """
  Flag a match review for later review.

  POST /api/match-reviews/:id/flag
  Body: %{"notes" => "Need to verify company details"}
  """
  def flag(conn, %{"id" => id} = _params) do
    current_user = conn.assigns[:current_user]

    with {:ok, review} <- Enforcement.get_review(id, actor: current_user),
         {:ok, updated_review} <-
           Enforcement.flag_for_later(review, reviewed_by_id: current_user.id) do
      conn
      |> json(%{
        success: true,
        message: "Review flagged for later",
        data: serialize_review_detail(updated_review)
      })
    else
      {:error, %Ash.Error.Query.NotFound{}} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          error: "Review not found"
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: "Failed to flag review",
          details: inspect(reason)
        })
    end
  end

  # Private serialization functions

  defp serialize_reviews(reviews) do
    Enum.map(reviews, &serialize_review_summary/1)
  end

  defp serialize_review_summary(review) do
    %{
      id: review.id,
      offender_id: review.offender_id,
      offender_name: if(review.offender, do: review.offender.name, else: nil),
      status: review.status,
      confidence_score: review.confidence_score,
      candidate_count: length(review.candidate_companies || []),
      searched_at: review.searched_at,
      reviewed_at: review.reviewed_at,
      reviewed_by_id: review.reviewed_by_id
    }
  end

  defp serialize_review_detail(review) do
    %{
      id: review.id,
      offender_id: review.offender_id,
      offender: serialize_offender(review.offender),
      status: review.status,
      confidence_score: review.confidence_score,
      candidate_companies: review.candidate_companies || [],
      selected_company_number: review.selected_company_number,
      review_notes: review.review_notes,
      searched_at: review.searched_at,
      reviewed_at: review.reviewed_at,
      reviewed_by_id: review.reviewed_by_id,
      reviewed_by: serialize_reviewer(review.reviewed_by),
      inserted_at: review.inserted_at,
      updated_at: review.updated_at
    }
  end

  defp serialize_offender(nil), do: nil

  defp serialize_offender(offender) do
    %{
      id: offender.id,
      name: offender.name,
      company_registration_number: offender.company_registration_number,
      town: offender.town,
      county: offender.county,
      postcode: offender.postcode
    }
  end

  defp serialize_reviewer(nil), do: nil

  defp serialize_reviewer(user) do
    %{
      id: user.id,
      email: user.email
    }
  end
end
