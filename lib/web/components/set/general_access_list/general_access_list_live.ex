defmodule Bonfire.UI.Boundaries.GeneralAccessListLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop hide_presets, :boolean, default: false
  prop boundary_preset, :any, default: nil
  prop set_action, :string, default: nil
  prop set_opts, :map, default: %{}
  prop my_acls, :any, default: []
  prop to_boundaries, :any, default: nil
  prop hide_custom, :boolean, default: false
  prop hide_private, :boolean, default: true
  prop is_customizable, :boolean, default: false
  prop scope, :any, default: :user

  def matches?({preset, _}, preset), do: true
  def matches?([{preset, _}], preset), do: true
  def matches?(preset, preset), do: true

  def matches?(acls, preset) when is_list(acls) do
    Enum.any?(acls, fn
      %{id: id} -> id == preset
      {p, _} -> p == preset
      p -> p == preset
    end)
  end

  def matches?(_, _), do: false

  @doc """
  Short, one-line descriptions shown in the compact preset picker.

  Falls back to the (often longer) description in the preset config for
  unknown slugs. Built-in slugs use tightened copy to keep the picker scannable.
  """
  def short_description(slug) do
    case slug do
      "public" -> l("Visible to everyone.")
      "local" -> l("Everyone on this instance.")
      "mentions" -> l("Only people you @mention.")
      "follows" -> l("Only people you follow.")
      "private" -> l("Only you.")
      _ -> e(Bonfire.Boundaries.Presets.for_preset(slug), :description, nil)
    end
  end
end
