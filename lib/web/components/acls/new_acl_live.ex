defmodule Bonfire.UI.Boundaries.NewAclLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop setting_boundaries, :atom, default: nil
  prop scope, :any, default: nil
end
