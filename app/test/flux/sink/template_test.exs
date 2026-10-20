defmodule Flux.Sink.TemplateTest do
  use ExUnit.Case, async: true

  alias Flux.Sink.Template

  doctest Flux.Sink.Template

  @data %{
    "id" => 7,
    "ok" => true,
    "name" => "Ada",
    "order" => %{"id" => "A-1", "items" => [1, 2]},
    "html" => "<script>alert('x')</script> & co"
  }

  describe "interpolate/2" do
    test "resolves top-level and dot-path fields" do
      assert Template.interpolate("{name} {order.id}", @data) == "Ada A-1"
    end

    test "renders numbers and booleans as text" do
      assert Template.interpolate("{id}/{ok}", @data) == "7/true"
    end

    test "renders maps and lists as JSON" do
      assert Template.interpolate("{order.items}", @data) == "[1,2]"
      assert Template.interpolate("{order}", @data) =~ ~s("id":"A-1")
    end

    test "a missing path renders empty" do
      assert Template.interpolate("[{missing}] [{order.nope}] [{name.deeper}]", @data) ==
               "[] [] []"
    end

    test "leaves text that isn't a placeholder alone" do
      assert Template.interpolate("{ } {a b} {}", @data) == "{ } {a b} {}"
    end

    test "does not escape" do
      assert Template.interpolate("{html}", @data) == @data["html"]
    end
  end

  describe "interpolate_html/2" do
    test "escapes substituted values but not the template's own markup" do
      result = Template.interpolate_html("<b>{html}</b>", @data)

      assert result ==
               "<b>&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt; &amp; co</b>"
    end
  end

  describe "interpolate_header/2" do
    test "collapses line breaks injected through a value" do
      data = %{"title" => "hello\r\nBcc: evil@example.com"}

      assert Template.interpolate_header("Re: {title}", data) ==
               "Re: hello Bcc: evil@example.com"
    end

    test "collapses line breaks in the template itself" do
      assert Template.interpolate_header("a\nb\t c", %{}) == "a b c"
    end
  end
end
