defmodule FluxWeb.PipelineLive.BuilderServerCredentialsTest do
  # async: false — toggles the global :aws_server_credentials application env,
  # which BuilderTest (async) reads with its default value.
  use FluxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  setup do
    previous = Application.get_env(:flux, :aws_server_credentials)
    Application.put_env(:flux, :aws_server_credentials, :disabled)
    on_exit(fn -> Application.put_env(:flux, :aws_server_credentials, previous) end)
    :ok
  end

  defp select_source(lv, source_config) do
    render_hook(lv, "select_node", %{
      "nodeId" => "node_1",
      "nodeType" => "source",
      "nodeData" => %{"label" => "My Source", "sourceConfig" => source_config}
    })
  end

  defp save(lv, source_config) do
    ir = %{"nodes" => [%{"type" => "source", "sourceConfig" => source_config}]}
    render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})
    render_click(lv, "save")
  end

  @iam_role_option "select[name='sourceConfig[authMode]'] option[value='iam_role']"
  @sqs %{
    "type" => "sqs",
    "queueUrl" => "https://sqs.us-east-1.amazonaws.com/1/q",
    "region" => "us-east-1"
  }
  @kinesis %{"type" => "kinesis", "streamName" => "events", "region" => "us-east-1"}

  describe "config panel" do
    test "a new SQS source offers no IAM role and opens on static keys", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")
      html = select_source(lv, %{"type" => "sqs"})

      refute has_element?(lv, @iam_role_option)
      assert has_element?(lv, "#sqs-server-credentials-disabled")
      assert html =~ ~s(name="sourceConfig[accessKeyId]")
      assert html =~ ~s(name="sourceConfig[secretAccessKey]")
    end

    test "an SQS assume_role source asks for base keys", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")
      html = select_source(lv, %{"type" => "sqs", "authMode" => "assume_role"})

      assert html =~ "Base Access Key ID"
      assert html =~ "Base Secret Access Key"
      assert html =~ ~s(name="sourceConfig[roleArn]")
    end

    test "a new Kinesis source offers only static keys", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")
      html = select_source(lv, %{"type" => "kinesis"})

      refute has_element?(lv, @iam_role_option)
      assert has_element?(lv, "#kinesis-server-credentials-disabled")
      assert html =~ ~s(name="sourceConfig[accessKeyId]")
    end

    test "a node saved with IAM role shows it disabled so another mode can be picked",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")
      select_source(lv, %{"type" => "kinesis", "authMode" => "iam_role"})

      assert has_element?(lv, @iam_role_option <> "[disabled][selected]")
      assert has_element?(lv, "#kinesis-server-credentials-disabled")
    end
  end

  describe "save" do
    test "refuses an SQS source signing with an IAM role", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")
      html = save(lv, Map.put(@sqs, "authMode", "iam_role"))

      assert html =~ "Server AWS credentials are disabled by your administrator"
      refute html =~ "Pipeline saved"
    end

    test "refuses a Kinesis source signing with an IAM role", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")
      html = save(lv, Map.put(@kinesis, "authMode", "iam_role"))

      assert html =~ "Server AWS credentials are disabled by your administrator"
    end

    test "a source with no mode picked needs the static keys it opens on", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")
      html = save(lv, @kinesis)

      assert html =~ "Access Key ID"
      refute html =~ "disabled by your administrator"
    end

    test "an SQS assume_role source needs base keys", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        save(
          lv,
          Map.merge(@sqs, %{
            "authMode" => "assume_role",
            "roleArn" => "arn:aws:iam::123456789012:role/flux"
          })
        )

      assert html =~ "Base Access Key ID"
      assert html =~ "Base Secret Access Key"
      refute html =~ "Pipeline saved"
    end

    test "an SQS assume_role source with base keys passes the credential checks",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        save(
          lv,
          Map.merge(@sqs, %{
            "authMode" => "assume_role",
            "roleArn" => "arn:aws:iam::123456789012:role/flux",
            "accessKeyId" => "AKIAUSER",
            "secretAccessKey" => "secret"
          })
        )

      refute html =~ "disabled by your administrator"
      refute html =~ "Base Access Key ID"
    end
  end
end
