defmodule Flux.Repo.Migrations.AddPasswordPolicyToSecuritySettings do
  use Ecto.Migration

  # Per-org password policy (MOS-590). Enterprise-gated: ungated builds ignore
  # these and keep the min-12 default. `password_min_length` defaults to the
  # Community floor (12); complexity flags default off; rotation disabled (nil).
  def change do
    alter table(:security_settings) do
      add :password_min_length, :integer, null: false, default: 12
      add :password_require_upper, :boolean, null: false, default: false
      add :password_require_lower, :boolean, null: false, default: false
      add :password_require_number, :boolean, null: false, default: false
      add :password_require_special, :boolean, null: false, default: false
      add :password_rotation_days, :integer, null: true
    end
  end
end
