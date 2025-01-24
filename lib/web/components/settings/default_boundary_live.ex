defmodule Bonfire.UI.Boundaries.DefaultBoundaryLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop scope, :any, default: nil

  declare_settings_component(l("Default boundary"),
    icon: "fluent:people-team-16-filled",
    description: l("Specify your default boundary when publishing a new activity")
  )
end
