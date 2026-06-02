defmodule Flux.Mailer do
  @moduledoc "Email delivery module using Swoosh."
  use Swoosh.Mailer, otp_app: :flux
end
