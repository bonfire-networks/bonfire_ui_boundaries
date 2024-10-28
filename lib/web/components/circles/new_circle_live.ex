defmodule Bonfire.UI.Boundaries.Web.NewCircleLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop setting_boundaries, :boolean, default: false
  prop event_target, :any, default: %{}
  prop scope, :any, default: nil
end
