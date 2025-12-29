defmodule Bonfire.UI.Boundaries.GeneralAccessListLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Boundaries.LiveHandler

  prop hide_presets, :boolean, default: false
  prop boundary_preset, :any, default: nil
  prop set_action, :string, default: nil
  prop set_opts, :map, default: %{}
  prop my_acls, :any, default: nil
  prop to_boundaries, :any, default: nil
  prop hide_custom, :boolean, default: false
  prop hide_private, :boolean, default: true
  prop is_customizable, :boolean, default: false
  prop scope, :any, default: :user

  def render(%{my_acls: nil} = assigns) do
    # Data should be preloaded by parent (CustomizeBoundaryLive) - fallback to empty list
    err("my_acls should be preloaded by parent component, not fetched in render")

    assigns
    |> assign(my_acls: [])
    |> render_sface()
  end

  def render(assigns) do
    render_sface(assigns)
  end

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
end
