defmodule Bonfire.UI.Boundaries.NewCircleButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component
  # alias Bonfire.Boundaries.Circles

  prop scope, :any, default: nil
  prop setting_boundaries, :atom, default: nil
end
