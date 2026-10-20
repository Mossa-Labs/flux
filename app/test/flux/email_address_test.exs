defmodule Flux.EmailAddressTest do
  use ExUnit.Case, async: true

  alias Flux.EmailAddress

  doctest Flux.EmailAddress

  @local64 String.duplicate("a", 64)
  # 64 + "@" + 189 = 254 octets: 63 + "." + 63 + "." + 61 = 189
  @addr254 @local64 <>
             "@" <>
             String.duplicate("b", 63) <>
             "." <> String.duplicate("c", 63) <> "." <> String.duplicate("d", 61)

  describe "validate/1 accepts" do
    for address <- [
          "a@b.co",
          "first.last+tag@sub.example.com",
          "o'neil@x.io",
          "user_name-1@example-domain.org",
          "x!#$%&*/=?^`{|}~@example.com",
          "a@xn--bcher-kva.de"
        ] do
      test "#{address}" do
        assert {:ok, _} = EmailAddress.validate(unquote(address))
      end
    end

    test "a 64-character local part" do
      assert {:ok, _} = EmailAddress.validate(@local64 <> "@example.com")
    end

    test "a 254-character address" do
      assert byte_size(@addr254) == 254
      assert {:ok, _} = EmailAddress.validate(@addr254)
    end
  end

  describe "validate/1 rejects" do
    for {label, address} <- [
          {"a 65-character local part", String.duplicate("a", 65) <> "@example.com"},
          {"a 64-character domain label", "a@" <> String.duplicate("b", 64) <> ".com"},
          {"a leading dot", ".a@x.com"},
          {"a trailing dot", "a.@x.com"},
          {"consecutive dots", "a..b@x.com"},
          {"a single-label domain", "a@x"},
          {"localhost", "ops@localhost"},
          {"a label starting with a hyphen", "a@-x.com"},
          {"a label ending with a hyphen", "a@x-.com"},
          {"a numeric TLD", "a@x.123"},
          {"an IP literal", "a@[1.2.3.4]"},
          {"a quoted local part", ~s("q"@x.com)},
          {"a space", "a b@x.com"},
          {"a CRLF header injection", "a@x.com\r\nBcc: evil@y.com"},
          {"a non-ASCII local part", "ü@x.com"},
          {"a non-ASCII domain", "a@bücher.de"},
          {"two @ signs", "a@@x.com"},
          {"no @", "example.com"},
          {"an empty local part", "@x.com"},
          {"an empty domain label", "a@x..com"},
          {"an underscore in the domain", "a@x_y.com"},
          {"blank", "   "}
        ] do
      test label do
        assert {:error, reason} = EmailAddress.validate(unquote(address))
        assert is_binary(reason)
      end
    end

    test "a 255-character address" do
      address = "a" <> @addr254
      assert byte_size(address) == 255
      assert {:error, _} = EmailAddress.validate(address)
    end

    test "non-strings" do
      assert {:error, _} = EmailAddress.validate(nil)
      assert {:error, _} = EmailAddress.validate(42)
    end

    test "non-ASCII with a message that says why" do
      assert {:error, reason} = EmailAddress.validate("ü@x.com")
      assert reason =~ "internationalized"
    end
  end

  describe "validate/1 normalization" do
    test "trims and lower-cases the domain but keeps the local part's case" do
      assert {:ok, "John.Doe@example.com"} = EmailAddress.validate("  John.Doe@EXAMPLE.com ")
    end
  end

  describe "validate_list/1" do
    test "splits on commas, semicolons and newlines and drops blanks" do
      assert {:ok, ["a@x.com", "b@x.com", "c@x.com", "d@x.com"]} =
               EmailAddress.validate_list("a@x.com, b@x.com;c@x.com\n\nd@x.com,")
    end

    test "accepts a list" do
      assert {:ok, ["a@x.com"]} = EmailAddress.validate_list(["a@x.com", " "])
    end

    test "de-duplicates case-insensitively, keeping the first spelling" do
      assert {:ok, ["Ops@x.com"]} = EmailAddress.validate_list("Ops@x.com, ops@X.COM")
    end

    test "nil is an empty list" do
      assert {:ok, []} = EmailAddress.validate_list(nil)
    end

    test "names each bad address in its error" do
      assert {:error, [first, second]} =
               EmailAddress.validate_list("good@x.com, bob@@x.com, nope")

      assert first =~ ~s("bob@@x.com")
      assert second =~ ~s("nope")
    end

    test "never echoes control characters back" do
      assert {:error, [message]} = EmailAddress.validate_list(["a@x.com\r\nBcc: e@y.com"])
      refute message =~ "\r"
      refute message =~ "\n"
    end
  end
end
