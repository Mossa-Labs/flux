defmodule FluxWeb.RequestBodyLimitTest do
  @moduledoc "MOS-450: request bodies over 10 MB are rejected with 413 at the parser."
  use FluxWeb.ConnCase, async: true

  test "rejects a request body larger than 10 MB with 413" do
    # Just over the 10 MB Plug.Parsers cap; the parser raises before routing,
    # so no API key is needed.
    oversized = String.duplicate("x", 10 * 1024 * 1024 + 1)

    assert_error_sent(413, fn ->
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/webhooks/test", oversized)
    end)
  end
end
