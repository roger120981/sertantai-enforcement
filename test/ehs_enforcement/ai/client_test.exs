defmodule EhsEnforcement.AI.ClientTest do
  @moduledoc """
  Tests for the AI Client behaviour and implementations.
  """

  use ExUnit.Case, async: true

  alias EhsEnforcement.AI.Client
  alias EhsEnforcement.AI.Client.Mock

  describe "Client.get_client/0" do
    test "returns Mock client by default (dev config)" do
      # In test environment, provider defaults to :mock
      client = Client.get_client()
      assert client == EhsEnforcement.AI.Client.Mock
    end
  end

  describe "Mock client" do
    test "complete/2 returns successful response with default mock" do
      messages = [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: "Hello"}
      ]

      assert {:ok, response} = Mock.complete(messages)
      assert is_binary(response.content)
      assert response.model == "mock-model-v1"
      assert response.usage.prompt_tokens > 0
      assert response.usage.completion_tokens > 0
      assert response.latency_ms > 0
    end

    test "complete/2 respects custom mock response via process dictionary" do
      custom_response = %{
        content: "Custom response content",
        model: "custom-model",
        usage: %{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30},
        latency_ms: 50
      }

      Process.put(:ai_mock_response, {:ok, custom_response})

      messages = [%{role: "user", content: "Test"}]
      assert {:ok, ^custom_response} = Mock.complete(messages)
    after
      Process.delete(:ai_mock_response)
    end

    test "complete/2 returns custom error via process dictionary" do
      Process.put(:ai_mock_response, {:error, :custom_error})

      messages = [%{role: "user", content: "Test"}]
      assert {:error, :custom_error} = Mock.complete(messages)
    after
      Process.delete(:ai_mock_response)
    end

    test "complete/2 supports custom function for dynamic responses" do
      custom_fn = fn messages, opts ->
        content =
          if Keyword.get(opts, :json_mode) do
            ~s({"result": "json mode enabled"})
          else
            "plain text response"
          end

        {:ok,
         %{
           content: content,
           model: "dynamic-mock",
           usage: %{prompt_tokens: 5, completion_tokens: 10, total_tokens: 15},
           latency_ms: 10
         }}
      end

      Process.put(:ai_mock_response, custom_fn)

      messages = [%{role: "user", content: "Test"}]

      # Without json_mode
      {:ok, response1} = Mock.complete(messages)
      assert response1.content == "plain text response"

      # With json_mode
      {:ok, response2} = Mock.complete(messages, json_mode: true)
      assert response2.content =~ "json mode enabled"
    after
      Process.delete(:ai_mock_response)
    end

    test "health_check/0 returns available status" do
      assert {:ok, %{status: :available, provider: :mock}} = Mock.health_check()
    end

    test "generates regulation-focused response for regulation prompts" do
      messages = [
        %{role: "system", content: "Analyze regulation references in this case"},
        %{role: "user", content: "Case details..."}
      ]

      {:ok, response} = Mock.complete(messages)

      # Should contain regulation-related JSON
      assert response.content =~ "Health and Safety at Work Act"
    end

    test "generates benchmark response for benchmark prompts" do
      messages = [
        %{role: "system", content: "Provide benchmark analysis for this fine"},
        %{role: "user", content: "Fine: £50,000"}
      ]

      {:ok, response} = Mock.complete(messages)

      # Should contain benchmark-related JSON
      assert response.content =~ "fine_percentile"
    end

    test "generates pattern response for pattern prompts" do
      messages = [
        %{role: "system", content: "Detect patterns in this enforcement data"},
        %{role: "user", content: "Case details..."}
      ]

      {:ok, response} = Mock.complete(messages)

      # Should contain pattern-related JSON
      assert response.content =~ "industry_pattern"
    end

    test "generates summary for summary prompts" do
      messages = [
        %{role: "system", content: "Provide a layperson summary of this case"},
        %{role: "user", content: "Case details..."}
      ]

      {:ok, response} = Mock.complete(messages)

      # Should be readable text
      assert is_binary(response.content)
      assert String.length(response.content) > 50
    end

    test "generates tags for tag prompts" do
      messages = [
        %{role: "system", content: "Generate tags for this enforcement case"},
        %{role: "user", content: "Case details..."}
      ]

      {:ok, response} = Mock.complete(messages)

      # Should be a JSON array of tags (content varies due to random selection)
      assert is_binary(response.content)
      # Parse as JSON array
      assert {:ok, tags} = Jason.decode(response.content)
      assert is_list(tags)
      assert length(tags) >= 3
    end
  end

  describe "Client.get_config/0" do
    test "returns configuration keyword list" do
      config = Client.get_config()
      assert is_list(config)
      # Config may be empty in test env, just verify it's a keyword list
      assert Keyword.keyword?(config) or config == []
    end
  end
end
