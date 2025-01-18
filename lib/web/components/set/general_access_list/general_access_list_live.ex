defmodule Bonfire.UI.Boundaries.GeneralAccessListLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop hide_presets, :boolean, default: false
  prop boundary_preset, :any, default: nil
  prop set_action, :string, default: nil
  prop set_opts, :map, default: %{}
  prop my_acls, :any, default: nil
  prop to_boundaries, :any, default: nil
  prop hide_custom, :boolean, default: false
  prop is_customizable, :boolean, default: false

  def matches?({preset, _}, preset), do: true
  def matches?([{preset, _}], preset), do: true
  def matches?(preset, preset), do: true
  def matches?(_, _), do: false
end
