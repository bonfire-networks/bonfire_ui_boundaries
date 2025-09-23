defmodule Bonfire.UI.Boundaries.BoundaryItemLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop value, :any, default: nil

  prop verb, :any, default: nil
  prop verb_slug, :any, default: nil

  prop read_only, :boolean, default: true
  prop event_target, :any, default: nil
end
