defmodule Bonfire.UI.Boundaries.InstancePermissionsRoleCoherenceTest do
  use Bonfire.UI.Boundaries.ConnCase, async: true
  @moduletag :ui

  alias Bonfire.UI.Boundaries.InstancePermissionsLive
  alias Bonfire.Boundaries.Roles

  @instance_roles [:read, :interact, :contribute, :moderate, :administer]

  test "every capability is fully granted or fully absent for each seeded role (no partials)" do
    capabilities = InstancePermissionsLive.capabilities()

    for role <- @instance_roles do
      role_verbs = Roles.get(role, scope: :instance_wide)[:can_verbs] || []
      role_verb_set = MapSet.new(role_verbs)

      for capability <- capabilities do
        cap_verbs = MapSet.new(capability.verbs)
        granted = MapSet.intersection(cap_verbs, role_verb_set)

        assert MapSet.size(granted) == 0 or MapSet.equal?(granted, cap_verbs),
               """
               Capability #{inspect(capability.key)} (verbs #{inspect(capability.verbs)}) \
               straddles role #{inspect(role)}: it grants only #{inspect(MapSet.to_list(granted))} \
               of its verbs, which would render as a permanent :partial state.
               Realign the capability's verbs to a single role tier.
               """
      end
    end
  end

  test "capabilities only use instance-scoped verbs" do
    instance_verbs =
      Bonfire.Boundaries.Verbs.verbs()
      |> Enum.filter(fn {_slug, v} -> v[:scope] == :instance end)
      |> Enum.map(fn {slug, _v} -> slug end)
      |> MapSet.new()

    for capability <- InstancePermissionsLive.capabilities(),
        verb <- capability.verbs do
      assert MapSet.member?(instance_verbs, verb),
             "Capability #{inspect(capability.key)} uses non-instance verb #{inspect(verb)}; " <>
               "content verbs don't belong on the instance permissions page."
    end
  end
end
