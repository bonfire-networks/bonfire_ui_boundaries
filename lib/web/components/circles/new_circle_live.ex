defmodule Bonfire.UI.Boundaries.NewCircleLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop setting_boundaries, :atom, default: nil
  prop event_target, :any, default: %{}
  prop scope, :any, default: nil
end
