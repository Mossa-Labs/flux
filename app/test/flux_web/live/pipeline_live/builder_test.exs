defmodule FluxWeb.PipelineLive.BuilderTest do
  use FluxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "builder page" do
    test "mounts and renders the pipeline-builder container", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/pipelines/builder")

      assert html =~ ~s(id="pipeline-builder")
      assert html =~ "Visual Pipeline Builder"
    end

    test "shows Save Pipeline button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/pipelines/builder")

      assert html =~ "Save Pipeline"
    end

    test "shows node palette in sidebar", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/pipelines/builder")

      assert html =~ "Nodes"
      assert html =~ "Source"
      assert html =~ "Filter"
      assert html =~ "Transform"
    end
  end

  describe "config panel selection" do
    test "select_node focuses the config panel on the selected node", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/pipelines/builder")

      # Starts with nothing selected.
      assert html =~ "Select a node to configure"

      # Selecting a node (as the React canvas does after adding/clicking one)
      # focuses the config panel on it.
      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{"label" => "My Source", "sourceConfig" => %{"type" => "queue"}}
        })

      assert html =~ "Source Node"
      assert html =~ "My Source"
      refute html =~ "Select a node to configure"

      # The mandatory Queue Name field carries a required marker.
      assert html =~ ~s(Queue Name<span class="text-error)
    end

    test "pubsub source renders its Pro config form with required markers", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{"label" => "My Source", "sourceConfig" => %{"type" => "pubsub"}}
        })

      # The Pub/Sub type is offered but gated (Community lacks the license).
      assert html =~ "Google Pub/Sub"
      assert html =~ "requires a Pro license"
      # Mandatory fields carry required markers.
      assert html =~ ~s(Project ID<span class="text-error)
      assert html =~ ~s(Subscription<span class="text-error)
    end

    test "rabbitmq_external source renders its Pro config form with required markers", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{
            "label" => "My Source",
            "sourceConfig" => %{"type" => "rabbitmq_external"}
          }
        })

      # The RabbitMQ (External) type is offered but gated (Community lacks the license).
      assert html =~ "RabbitMQ (External)"
      assert html =~ "requires a Pro license"
      # Mandatory fields carry required markers.
      assert html =~ ~s(Host<span class="text-error)
      assert html =~ ~s(Queue<span class="text-error)
    end

    test "mqtt source renders its Pro config form with required markers", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{"label" => "My Source", "sourceConfig" => %{"type" => "mqtt"}}
        })

      # The MQTT type is offered but gated (Community lacks the license).
      assert html =~ "MQTT Broker"
      assert html =~ "requires a Pro license"
      # Mandatory fields carry required markers.
      assert html =~ ~s(Host<span class="text-error)
      assert html =~ ~s(Topic<span class="text-error)
    end

    test "mqtt username_password auth reveals credential fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{
            "label" => "My Source",
            "sourceConfig" => %{"type" => "mqtt", "authMode" => "username_password"}
          }
        })

      assert html =~ ~s(name="sourceConfig[username]")
      assert html =~ ~s(name="sourceConfig[password]")
    end

    test "mqtt mtls auth reveals client certificate fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{
            "label" => "My Source",
            "sourceConfig" => %{"type" => "mqtt", "authMode" => "mtls"}
          }
        })

      assert html =~ ~s(name="sourceConfig[sslCertfile]")
      assert html =~ ~s(name="sourceConfig[sslKeyfile]")
      # The username/password inputs belong to a different auth mode.
      refute html =~ ~s(name="sourceConfig[username]")
    end

    test "mqtt jwt auth reveals the token field", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{
            "label" => "My Source",
            "sourceConfig" => %{"type" => "mqtt", "authMode" => "jwt"}
          }
        })

      assert html =~ ~s(name="sourceConfig[jwt]")
    end

    test "kinesis source exposes Stream ARN and reveals static creds when selected", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{
            "label" => "My Source",
            "sourceConfig" => %{"type" => "kinesis", "authMode" => "static"}
          }
        })

      # Stream ARN is always available as an alternative to Stream Name.
      assert html =~ ~s(name="sourceConfig[streamArn]")
      # Static auth reveals the AWS key inputs.
      assert html =~ ~s(name="sourceConfig[accessKeyId]")
      assert html =~ ~s(name="sourceConfig[secretAccessKey]")
    end

    test "kinesis AT_TIMESTAMP start reveals the timestamp field", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{
            "label" => "My Source",
            "sourceConfig" => %{"type" => "kinesis", "startingPosition" => "AT_TIMESTAMP"}
          }
        })

      assert html =~ ~s(name="sourceConfig[atTimestamp]")
    end

    test "sqs static auth reveals AWS credential fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{
            "label" => "My Source",
            "sourceConfig" => %{"type" => "sqs", "authMode" => "static"}
          }
        })

      assert html =~ ~s(name="sourceConfig[accessKeyId]")
      assert html =~ ~s(name="sourceConfig[secretAccessKey]")
    end

    test "aws static creds stay hidden under non-static (iam_role) auth", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{
            "label" => "My Source",
            "sourceConfig" => %{"type" => "kinesis", "authMode" => "iam_role"}
          }
        })

      refute html =~ ~s(name="sourceConfig[accessKeyId]")
      refute html =~ ~s(name="sourceConfig[secretAccessKey]")
    end

    test "sftp source renders its Pro config form with required markers", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{"label" => "My Source", "sourceConfig" => %{"type" => "sftp"}}
        })

      # The SFTP type is offered but gated (Community lacks the license).
      assert html =~ "SFTP"
      assert html =~ "requires a Pro license"
      # Mandatory fields carry required markers.
      assert html =~ ~s(Host<span class="text-error)
      assert html =~ ~s(Username<span class="text-error)
      assert html =~ ~s(Remote Path<span class="text-error)
      # Default auth mode (password) reveals the password input.
      assert html =~ ~s(name="sourceConfig[password]")
    end

    test "sftp private_key auth reveals the private key field", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{
            "label" => "My Source",
            "sourceConfig" => %{"type" => "sftp", "authMode" => "private_key"}
          }
        })

      assert html =~ ~s(name="sourceConfig[privateKey]")
      # The password input belongs to a different auth mode.
      refute html =~ ~s(name="sourceConfig[password]")
    end

    test "sftp move after-processing reveals the archive path field", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html =
        render_hook(lv, "select_node", %{
          "nodeId" => "node_1",
          "nodeType" => "source",
          "nodeData" => %{
            "label" => "My Source",
            "sourceConfig" => %{"type" => "sftp", "afterProcessing" => "move"}
          }
        })

      assert html =~ ~s(name="sourceConfig[archivePath]")
    end

    test "empty select_node clears the config panel back to the empty state", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      render_hook(lv, "select_node", %{
        "nodeId" => "node_1",
        "nodeType" => "source",
        "nodeData" => %{"label" => "My Source"}
      })

      html = render_hook(lv, "select_node", %{})

      assert html =~ "Select a node to configure"
      refute html =~ "My Source"
    end
  end

  describe "save validation" do
    test "saving the default (valid) pipeline succeeds", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      html = render_click(lv, "save")

      assert html =~ "Pipeline saved"
    end

    test "saving a source with a missing mandatory field shows an error toast", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      # A webhook source with no webhookPath — the mandatory field is blank.
      ir = %{"nodes" => [%{"type" => "source", "sourceConfig" => %{"type" => "webhook"}}]}
      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})

      html = render_click(lv, "save")

      assert html =~ "Webhook Path"
      refute html =~ "Pipeline saved"
    end

    test "saving with no source node shows an error toast", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(%{"nodes" => []})})

      html = render_click(lv, "save")

      assert html =~ "Add and configure a source node"
      refute html =~ "Pipeline saved"
    end

    test "saving a kinesis source with neither stream name nor ARN shows an error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      ir = %{
        "nodes" => [
          %{"type" => "source", "sourceConfig" => %{"type" => "kinesis", "region" => "us-east-1"}}
        ]
      }

      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})
      html = render_click(lv, "save")

      assert html =~ "Stream Name or Stream ARN"
      refute html =~ "Pipeline saved"
    end

    test "saving a static-auth kinesis source missing keys shows an error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      ir = %{
        "nodes" => [
          %{
            "type" => "source",
            "sourceConfig" => %{
              "type" => "kinesis",
              "streamName" => "events",
              "region" => "us-east-1",
              "authMode" => "static"
            }
          }
        ]
      }

      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})
      html = render_click(lv, "save")

      assert html =~ "Access Key ID"
      refute html =~ "Pipeline saved"
    end

    test "saving an AT_TIMESTAMP kinesis source missing the timestamp shows an error", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      ir = %{
        "nodes" => [
          %{
            "type" => "source",
            "sourceConfig" => %{
              "type" => "kinesis",
              "streamName" => "events",
              "region" => "us-east-1",
              "startingPosition" => "AT_TIMESTAMP"
            }
          }
        ]
      }

      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})
      html = render_click(lv, "save")

      assert html =~ "At Timestamp"
      refute html =~ "Pipeline saved"
    end

    test "saving an assume_role SQS source missing the role ARN shows an error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      ir = %{
        "nodes" => [
          %{
            "type" => "source",
            "sourceConfig" => %{
              "type" => "sqs",
              "queueUrl" => "https://sqs.us-east-1.amazonaws.com/1/q",
              "region" => "us-east-1",
              "authMode" => "assume_role"
            }
          }
        ]
      }

      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})
      html = render_click(lv, "save")

      assert html =~ "Role ARN"
      refute html =~ "Pipeline saved"
    end

    test "saving an MQTT source missing host and topic shows an error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      ir = %{"nodes" => [%{"type" => "source", "sourceConfig" => %{"type" => "mqtt"}}]}
      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})
      html = render_click(lv, "save")

      assert html =~ "Host"
      assert html =~ "Topic"
      refute html =~ "Pipeline saved"
    end

    test "saving an SFTP source missing host/username/path shows an error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      ir = %{"nodes" => [%{"type" => "source", "sourceConfig" => %{"type" => "sftp"}}]}
      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})

      html = render_click(lv, "save")

      assert html =~ "Host"
      assert html =~ "Remote Path"
      refute html =~ "Pipeline saved"
    end

    test "saving a private_key SFTP source missing the key shows an error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      ir = %{
        "nodes" => [
          %{
            "type" => "source",
            "sourceConfig" => %{
              "type" => "sftp",
              "host" => "sftp.example.com",
              "username" => "flux",
              "path" => "inbound/",
              "authMode" => "private_key"
            }
          }
        ]
      }

      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})
      html = render_click(lv, "save")

      assert html =~ "Private Key"
      refute html =~ "Pipeline saved"
    end

    test "saving a move-mode SFTP source missing the archive path shows an error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      ir = %{
        "nodes" => [
          %{
            "type" => "source",
            "sourceConfig" => %{
              "type" => "sftp",
              "host" => "sftp.example.com",
              "username" => "flux",
              "path" => "inbound/",
              "password" => "secret",
              "afterProcessing" => "move"
            }
          }
        ]
      }

      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})
      html = render_click(lv, "save")

      assert html =~ "Archive Path"
      refute html =~ "Pipeline saved"
    end
  end

  describe "source queue derivation" do
    test "a webhook source node persists the webhooks.<path> queue", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      ir = %{
        "nodes" => [
          %{
            "type" => "source",
            "label" => "GitHub Events",
            "sourceConfig" => %{"type" => "webhook", "webhookPath" => "github"}
          }
        ]
      }

      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})
      html = render_click(lv, "save")
      assert html =~ "Pipeline saved"

      pipeline = List.last(Flux.Pipelines.list_pipelines(scope.organization_id))
      assert pipeline.source_queue == "webhooks.github"
    end

    test "a scheduled_poll source node persists the polling.<slug> queue", %{
      conn: conn,
      scope: scope
    } do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      ir = %{
        "nodes" => [
          %{
            "type" => "source",
            "label" => "My Poller",
            "sourceConfig" => %{
              "type" => "scheduled_poll",
              "pollUrl" => "https://api.example.com/events"
            }
          }
        ]
      }

      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})
      html = render_click(lv, "save")
      assert html =~ "Pipeline saved"

      pipeline = List.last(Flux.Pipelines.list_pipelines(scope.organization_id))
      assert pipeline.source_queue == "polling.my-poller"
    end

    test "a webhook path with slashes, case and punctuation is slugified", %{
      conn: conn,
      scope: scope
    } do
      {:ok, lv, _html} = live(conn, ~p"/pipelines/builder")

      # Only the last path segment is used, lower-cased, with runs of unsafe
      # characters collapsed to a single hyphen and trimmed.
      ir = %{
        "nodes" => [
          %{
            "type" => "source",
            "label" => "Webhook",
            "sourceConfig" => %{"type" => "webhook", "webhookPath" => "/api/My Webhook!"}
          }
        ]
      }

      render_hook(lv, "update_ir", %{"ir" => Jason.encode!(ir)})
      html = render_click(lv, "save")
      assert html =~ "Pipeline saved"

      pipeline = List.last(Flux.Pipelines.list_pipelines(scope.organization_id))
      assert pipeline.source_queue == "webhooks.my-webhook"
    end
  end
end
