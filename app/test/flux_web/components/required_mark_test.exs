defmodule FluxWeb.CoreComponents.RequiredMarkTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias FluxWeb.CoreComponents

  describe "input/1 required marker" do
    test "renders a * immediately after the label when required" do
      html =
        render_component(&CoreComponents.input/1,
          name: "x",
          value: "",
          label: "Bucket Name",
          type: "text",
          required: true
        )

      assert html =~ ~r{Bucket Name<span class="text-error}
    end

    test "renders no marker when not required" do
      html =
        render_component(&CoreComponents.input/1,
          name: "x",
          value: "",
          label: "Region",
          type: "text"
        )

      refute html =~ "text-error"
    end
  end

  describe "field_label/1 required marker" do
    test "renders a * after the text when required" do
      html = render_component(&CoreComponents.field_label/1, text: "Queue Name", required: true)
      assert html =~ ~r{Queue Name<span class="text-error}
    end

    test "renders no marker when not required" do
      html = render_component(&CoreComponents.field_label/1, text: "Prefetch Count")
      refute html =~ "text-error"
    end
  end
end
