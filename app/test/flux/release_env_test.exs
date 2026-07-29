defmodule Flux.ReleaseEnvTest do
  use ExUnit.Case, async: true

  # `rel/env.sh.eex` decides what this node is called, and a wrong answer is not
  # a cosmetic problem: `bin/flux rpc|remote|stop` all target the name this file
  # computes, so getting it wrong makes a healthy node look dead.
  #
  # These tests RUN the script under a real `sh` rather than pattern-matching its
  # source. The bug this guards against was invisible to inspection — the file
  # looked correct, and only the interaction between "sourced afresh on every
  # invocation" and "docker exec inherits nothing PID 1 exported" broke it.

  @template Path.expand("../../rel/env.sh.eex", __DIR__)
  @release "flux"

  setup_all do
    source = EEx.eval_file(@template, assigns: [release: %{name: @release}])
    %{source: source}
  end

  # Runs the script with the given environment and returns whatever it settled on.
  # `RELEASE_ROOT`/`NAME`/`VSN`/`COMMAND` are exported by the generated bin script
  # before it sources env.sh, so the harness has to supply them too.
  defp run(source, env, opts \\ []) do
    dir = Path.join(System.tmp_dir!(), "flux-env-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit_rm(dir)

    script = Path.join(dir, "env.sh")
    File.write!(script, source)

    # Echo the values back out; `set -a` is not needed since we read them directly.
    probe = Path.join(dir, "probe.sh")

    File.write!(probe, """
    . "#{script}"
    printf 'NODE=%s\\n' "$RELEASE_NODE"
    printf 'DIST=%s\\n' "$RELEASE_DISTRIBUTION"
    printf 'AFLAGS=%s\\n' "$ERL_AFLAGS"
    """)

    base = [
      {"RELEASE_ROOT", dir},
      {"RELEASE_NAME", @release},
      {"RELEASE_VSN", "9.9.9"},
      {"RELEASE_TMP", Keyword.get(opts, :tmp, Path.join(dir, "tmp"))}
    ]

    {out, status} =
      System.cmd("sh", [probe], env: base ++ env, stderr_to_stdout: true)

    parsed =
      for line <- String.split(out, "\n", trim: true),
          [k, v] <- [String.split(line, "=", parts: 2)],
          into: %{} do
        {k, v}
      end

    %{
      status: status,
      out: out,
      node: parsed["NODE"],
      dist: parsed["DIST"],
      aflags: parsed["AFLAGS"]
    }
  end

  defp node_file(dir), do: Path.join([dir, "tmp", "#{@release}-9.9.9.node"])

  defp on_exit_rm(dir), do: ExUnit.Callbacks.on_exit(fn -> File.rm_rf(dir) end)

  describe "the script itself" do
    test "is valid POSIX sh", %{source: source} do
      dir = Path.join(System.tmp_dir!(), "flux-env-syntax-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit_rm(dir)
      path = Path.join(dir, "env.sh")
      File.write!(path, source)

      assert {_, 0} = System.cmd("sh", ["-n", path], stderr_to_stdout: true)
    end

    test "uses no bashisms", %{source: source} do
      # It is sourced by the generated bin script, which runs under /bin/sh —
      # dash on Debian/Ubuntu, where these all fail.
      #
      # Scan CODE, not comments: the file's own header documents which constructs
      # to avoid, and naming them there must not trip the check that enforces it.
      code =
        source
        |> String.split("\n")
        |> Enum.reject(&(String.trim(&1) =~ ~r/^#/))
        |> Enum.join("\n")

      refute code =~ ~r/\[\[/, "uses [[ ]]"
      refute code =~ ~r/^\s*local\s/m, "uses `local`"
      refute code =~ ~r/\w\+=/, "uses += append"
      refute code =~ ~r/\$\{[A-Za-z_]+\[/, "uses array subscripting"
    end
  end

  describe "boot" do
    test "derives the node name from POD_IP", %{source: source} do
      r = run(source, [{"RELEASE_COMMAND", "start"}, {"POD_IP", "10.1.2.3"}])
      assert r.node == "flux@10.1.2.3"
    end

    test "records the booted name so later commands can read it", %{source: source} do
      dir = Path.join(System.tmp_dir!(), "flux-env-rec-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, "tmp"))
      on_exit_rm(dir)

      r =
        run(source, [{"RELEASE_COMMAND", "start"}, {"POD_IP", "10.4.5.6"}],
          tmp: Path.join(dir, "tmp")
        )

      assert r.node == "flux@10.4.5.6"
      assert File.read!(node_file(dir)) |> String.trim() == "flux@10.4.5.6"
    end

    test "an explicit RELEASE_NODE wins over derivation", %{source: source} do
      r =
        run(source, [
          {"RELEASE_COMMAND", "start"},
          {"POD_IP", "10.1.1.1"},
          {"RELEASE_NODE", "flux@chosen.example"}
        ])

      assert r.node == "flux@chosen.example"
    end

    test "refuses to boot unclustered when it is meant to cluster", %{source: source} do
      # No POD_IP and no resolvable address, but DNS_CLUSTER_QUERY set: booting as
      # 127.0.0.1 would serve traffic and never join, and an unclustered peer
      # duplicates work rather than sharing it.
      r =
        run(source, [
          {"RELEASE_COMMAND", "start"},
          {"DNS_CLUSTER_QUERY", "flux-nodes"},
          {"PATH", "/nonexistent"}
        ])

      assert r.status == 1
      assert r.out =~ "DNS_CLUSTER_QUERY is set"
    end

    test "falls back to loopback when nothing suggests clustering", %{source: source} do
      r = run(source, [{"RELEASE_COMMAND", "start"}, {"PATH", "/nonexistent"}])

      assert r.status == 0
      assert r.node == "flux@127.0.0.1"
    end
  end

  describe "exec'd subcommands" do
    test "read back the name the running node booted with", %{source: source} do
      # THE REGRESSION TEST. `docker exec` inherits nothing PID 1 exported, so
      # POD_IP is absent here — exactly the condition that used to produce
      # flux@127.0.0.1 and `:noconnection` against a perfectly healthy node.
      dir = Path.join(System.tmp_dir!(), "flux-env-rpc-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, "tmp"))
      on_exit_rm(dir)
      File.write!(node_file(dir), "flux@192.168.5.5\n")

      r = run(source, [{"RELEASE_COMMAND", "rpc"}], tmp: Path.join(dir, "tmp"))

      assert r.node == "flux@192.168.5.5"
    end

    test "still produce a qualified name with no recorded file", %{source: source} do
      r = run(source, [{"RELEASE_COMMAND", "rpc"}])

      # Never a bare "flux@" — that would fail in a way that looks like a bug in
      # distribution rather than a missing address.
      assert r.node =~ ~r/^flux@\S+$/
    end

    test "an explicit RELEASE_NODE still wins", %{source: source} do
      dir = Path.join(System.tmp_dir!(), "flux-env-exp-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, "tmp"))
      on_exit_rm(dir)
      File.write!(node_file(dir), "flux@recorded\n")

      r =
        run(source, [{"RELEASE_COMMAND", "rpc"}, {"RELEASE_NODE", "flux@override"}],
          tmp: Path.join(dir, "tmp")
        )

      assert r.node == "flux@override"
    end

    test "an unwritable tmp does not break the command", %{source: source} do
      r = run(source, [{"RELEASE_COMMAND", "rpc"}], tmp: "/nonexistent/definitely/not/here")

      assert r.status == 0
      assert r.node =~ ~r/^flux@/
    end
  end

  describe "distribution settings" do
    test "long names by default, since the node name contains dots", %{source: source} do
      r = run(source, [{"RELEASE_COMMAND", "start"}, {"POD_IP", "10.0.0.1"}])
      assert r.dist == "name"
    end

    test "an operator's choice of distribution survives", %{source: source} do
      # `none` is a legitimate choice — it starts without epmd.
      r =
        run(source, [
          {"RELEASE_COMMAND", "start"},
          {"POD_IP", "10.0.0.1"},
          {"RELEASE_DISTRIBUTION", "none"}
        ])

      assert r.dist == "none"
    end

    test "ERL_AFLAGS is appended, not replaced", %{source: source} do
      # Assigning would silently discard an operator's TLS-distribution or
      # scheduler flags.
      r =
        run(source, [
          {"RELEASE_COMMAND", "start"},
          {"POD_IP", "10.0.0.1"},
          {"ERL_AFLAGS", "-kernel inet_dist_use_interface {127,0,0,1}"}
        ])

      assert r.aflags =~ "-proto_dist inet_tcp"
      assert r.aflags =~ "inet_dist_use_interface"
    end
  end
end
