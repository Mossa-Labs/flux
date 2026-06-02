alias Flux.Repo
alias Flux.Accounts.User
alias Flux.Structure.Organization
alias Flux.Structure.OrganizationMember
alias Flux.Structure.Team
alias Flux.Structure.TeamMember

# Shared password for seed users
seed_password = "password1234"

Repo.transaction(fn ->
  # Create users: admin, member, viewer
  base_attrs = %{
    password: seed_password,
    confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
  }

  admin =
    %User{}
    |> User.email_changeset(%{email: "admin@flux.dev"})
    |> User.password_changeset(Map.merge(base_attrs, %{password_confirmation: seed_password}))
    |> Repo.insert!()

  member =
    %User{}
    |> User.email_changeset(%{email: "member@flux.dev"})
    |> User.password_changeset(Map.merge(base_attrs, %{password_confirmation: seed_password}))
    |> Repo.insert!()

  viewer =
    %User{}
    |> User.email_changeset(%{email: "viewer@flux.dev"})
    |> User.password_changeset(Map.merge(base_attrs, %{password_confirmation: seed_password}))
    |> Repo.insert!()

  # Create organization
  org =
    Repo.insert!(%Organization{
      name: "Flux Development",
      slug: "flux-dev",
      user_id: admin.id
    })

  # Organization members (for :org_centric mode)
  for {user, role} <- [{admin, "owner"}, {member, "member"}, {viewer, "viewer"}] do
    Repo.insert!(%OrganizationMember{
      organization_id: org.id,
      user_id: user.id,
      role: role
    })
  end

  # Teams: Core, Analytics (under the org)
  core_team =
    Repo.insert!(%Team{
      name: "Core",
      organization_id: org.id,
      user_id: admin.id
    })

  analytics_team =
    Repo.insert!(%Team{
      name: "Analytics",
      organization_id: org.id,
      user_id: admin.id
    })

  # Team members: Core — admin, member; Analytics — admin, viewer
  for {user, team, role} <- [
        {admin, core_team, "admin"},
        {member, core_team, "member"},
        {admin, analytics_team, "admin"},
        {viewer, analytics_team, "viewer"}
      ] do
    Repo.insert!(%TeamMember{
      user_id: user.id,
      team_id: team.id,
      role: role
    })
  end

  IO.puts("Seed data created:")

  IO.puts(
    "  Users: admin@flux.dev, member@flux.dev, viewer@flux.dev (password: #{seed_password})"
  )

  IO.puts("  Org: Flux Development (flux-dev)")
  IO.puts("  Teams: Core, Analytics")
  IO.puts("  Team members: Core (admin, member), Analytics (admin, viewer)")
  IO.puts("  Organization members: admin→owner, member→member, viewer→viewer")
end)
