defmodule Bonfire.UI.Boundaries.BoundariesDropdownLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop to_boundaries, :any, default: nil
  prop to_circles, :list, default: []
  prop exclude_circles, :list, default: []
  prop thread_mode, :atom, default: nil
  prop showing_within, :atom, default: nil
  prop create_object_type, :any, default: nil
end
