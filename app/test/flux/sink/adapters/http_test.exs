defmodule Flux.Sink.Adapters.HTTPTest do
  use ExUnit.Case, async: true

  alias Flux.Sink.Adapters.HTTP

  describe "validate_config/1" do
    test "valid config with url returns :ok" do
      config = %{"url" => "https://example.com/webhook"}
      assert :ok = HTTP.validate_config(config)
    end

    test "missing url returns error" do
      assert {:error, errors} = HTTP.validate_config(%{})
      assert "url is required" in errors
    end

    test "invalid url without scheme returns error" do
      config = %{"url" => "not-a-url"}
      assert {:error, errors} = HTTP.validate_config(config)
      assert Enum.any?(errors, &String.contains?(&1, "url must be a valid HTTP/HTTPS URL"))
    end

    test "invalid HTTP method returns error" do
      config = %{"url" => "https://example.com", "method" => "TRACE"}
      assert {:error, errors} = HTTP.validate_config(config)
      assert Enum.any?(errors, &String.contains?(&1, "method must be"))
    end

    test "GET method is valid" do
      config = %{"url" => "https://example.com", "method" => "GET"}
      assert :ok = HTTP.validate_config(config)
    end

    test "POST method is valid" do
      config = %{"url" => "https://example.com", "method" => "POST"}
      assert :ok = HTTP.validate_config(config)
    end

    test "PUT method is valid" do
      config = %{"url" => "https://example.com", "method" => "PUT"}
      assert :ok = HTTP.validate_config(config)
    end

    test "PATCH method is valid" do
      config = %{"url" => "https://example.com", "method" => "PATCH"}
      assert :ok = HTTP.validate_config(config)
    end

    test "DELETE method is valid" do
      config = %{"url" => "https://example.com", "method" => "DELETE"}
      assert :ok = HTTP.validate_config(config)
    end

    test "bearer auth with token is valid" do
      config = %{
        "url" => "https://example.com",
        "auth" => %{"type" => "bearer", "token" => "secret"}
      }

      assert :ok = HTTP.validate_config(config)
    end

    test "basic auth with username and password is valid" do
      config = %{
        "url" => "https://example.com",
        "auth" => %{"type" => "basic", "username" => "user", "password" => "pass"}
      }

      assert :ok = HTTP.validate_config(config)
    end

    test "api_key auth with header_name and key is valid" do
      config = %{
        "url" => "https://example.com",
        "auth" => %{"type" => "api_key", "header_name" => "X-API-Key", "key" => "my-key"}
      }

      assert :ok = HTTP.validate_config(config)
    end

    test "incomplete bearer auth missing token returns error" do
      config = %{
        "url" => "https://example.com",
        "auth" => %{"type" => "bearer"}
      }

      assert {:error, errors} = HTTP.validate_config(config)

      assert Enum.any?(
               errors,
               &String.contains?(&1, "auth type 'bearer' requires proper configuration")
             )
    end

    test "incomplete basic auth missing password returns error" do
      config = %{
        "url" => "https://example.com",
        "auth" => %{"type" => "basic", "username" => "user"}
      }

      assert {:error, errors} = HTTP.validate_config(config)

      assert Enum.any?(
               errors,
               &String.contains?(&1, "auth type 'basic' requires proper configuration")
             )
    end

    test "config without auth is valid" do
      config = %{"url" => "https://example.com"}
      assert :ok = HTTP.validate_config(config)
    end

    test "http scheme url is valid" do
      config = %{"url" => "http://localhost:4000/webhook"}
      assert :ok = HTTP.validate_config(config)
    end
  end
end
