defmodule Bonfire.UI.Boundaries.CustomBoundaryButtonLive do
  @moduledoc "The composer visibility menu's \"Custom boundaries\" entry, opening the existing boundary editor for per-action rules."
  use Bonfire.UI.Common.Web, :stateless_component

  prop boundary_preset, :any, default: nil
  prop to_circles, :any, default: []
  prop exclude_circles, :any, default: []
  prop to_boundaries, :any, default: []
  prop verb_permissions, :any, default: %{}
  prop setting_boundaries, :atom, default: nil
end
