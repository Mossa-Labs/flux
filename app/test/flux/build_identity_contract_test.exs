defmodule Flux.BuildIdentityContractTest do
  use ExUnit.Case, async: true

  # MOS-596. Flux.BuildInfo is compiled from build-time environment, so no test
  # that merely runs the app can see whether the Dockerfile actually supplies it.
  # An image tagged 0.2.1 shipped an app reporting 0.2.0 and every existing test
  # stayed green, because the variable was declared only in the runtime stage —
  # where it reaches the OCI labels and /etc/flux-release but never the compiler.
  #
  # So assert the Dockerfile's structure. It is what was broken, and it is the
  # only artefact in this repo that records the wiring.

  @dockerfile Path.expand("../../Dockerfile.release", __DIR__)

  # Everything from the builder `FROM` up to the runtime `FROM`. Splitting on
  # `FROM` at line start gives [preamble (ARG defaults), builder, runtime].
  setup_all do
    source = File.read!(@dockerfile)
    [_preamble, builder, runtime] = String.split(source, ~r/^FROM /m)

    %{source: source, builder: builder, runtime: runtime}
  end

  describe "compile-time build identity" do
    test "every variable config.exs reads is declared AND promoted to ENV in the builder stage",
         %{builder: builder} do
      # ARG alone is not enough: an ARG is visible to Docker, not to the process
      # running `mix compile`. Without the ENV promotion the compiler sees
      # nothing and Flux.BuildInfo bakes the fallback.
      for var <- ~w(FLUX_VERSION FLUX_CORE_SHA FLUX_BUILD_TIME) do
        assert builder =~ ~r/^ARG #{var}\b/m,
               "#{var} feeds the compiled build identity but the builder stage never declares it"

        assert builder =~ ~r/ENV [^\n]*#{var}=\$\{#{var}\}/,
               "#{var} is declared in the builder but never promoted to ENV, " <>
                 "so `mix compile` cannot see it"
      end
    end

    test "the runtime stage records the version resolved by the builder, not its own guess",
         %{builder: builder, runtime: runtime} do
      # The release directory name is the one version that is true by
      # construction, so the builder reads it back off the release and hands it
      # forward. Stamping the raw build arg is what let the label and the app
      # disagree.
      assert builder =~ "start_erl.data",
             "the builder must read the resolved version off the release itself"

      assert runtime =~ ~r/COPY --from=builder [^\n]*FLUX_VERSION/,
             "the runtime stage must take the version from the builder"
    end

    test "no stage invents a numeric version default", %{source: source} do
      # `ARG FLUX_VERSION=0.1.0` was plausible enough to be believed and false in
      # every build that ever existed. An unclaimed build should say "dev".
      refute source =~ ~r/ARG FLUX_VERSION=\d/,
             "a numeric default is a plausible lie; leave it unset so an " <>
               "unclaimed build is labelled dev"
    end
  end
end
