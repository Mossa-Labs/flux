defmodule Flux.Repo.Migrations.AddRequireMfaToSecuritySettings do
  use Ecto.Migration

  def change do
    alter table(:security_settings) do
      # Per-org "require MFA for all members" toggle. Enterprise-gated
      # (:mfa_enforcement); ungated builds keep it off (MOS-591).
      add :require_mfa, :boolean, null: false, default: false
    end
  end
end
