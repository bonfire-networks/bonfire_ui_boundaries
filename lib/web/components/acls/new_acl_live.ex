defmodule Bonfire.UI.Boundaries.NewAclLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop setting_boundaries, :boolean, default: false
  prop scope, :any, default: nil
end
