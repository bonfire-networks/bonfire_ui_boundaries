defmodule Bonfire.UI.Boundaries.VerbGroupLive do
  @moduledoc """
  A collapsible section displaying verbs in a semantic category.
  Used within RoleCardLive to group permissions by type (Visibility, Participation, etc).
  """
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.UI.Boundaries.RolesLive

  prop id, :string, required: true
  prop group_key, :atom, required: true
  prop group, :map, required: true
  prop role_name, :any, required: true
  prop read_only, :boolean, default: false
  prop event_target, :any, default: nil

  defdelegate defined_count(role_verbs), to: RolesLive

  @doc "Get up to 3 defined permissions for collapsed display summary"
  def permission_summary(role_verbs) do
    (role_verbs || [])
    |> Enum.filter(fn {_verb, status} -> status in [:can, :cannot] end)
    |> Enum.take(3)
    |> Enum.map(fn {verb, status} -> {Recase.to_title(to_string(verb)), status} end)
    |> case do
      [] -> nil
      list -> list
    end
  end
end
