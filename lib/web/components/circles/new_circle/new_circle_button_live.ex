defmodule Bonfire.UI.Boundaries.Web.NewCircleButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component
  # alias Bonfire.Boundaries.Circles

  prop scope, :any, default: nil
  prop setting_boundaries, :boolean, default: false
end
