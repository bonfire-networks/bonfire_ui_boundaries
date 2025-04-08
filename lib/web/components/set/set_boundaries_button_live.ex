defmodule Bonfire.UI.Boundaries.SetBoundariesButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Utils

  prop to_boundaries, :any, default: nil
  prop boundary_preset, :any, default: nil
  prop to_circles, :any, default: []
  prop exclude_circles, :any, default: []

  def clone_context(to_boundaries) do
    case to_boundaries do
      [{:clone_context, boundary_name}] -> boundary_name
      [{"clone_context", boundary_name}] -> boundary_name
      _ -> false
    end
  end
end
