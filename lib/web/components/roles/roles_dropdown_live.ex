defmodule Bonfire.UI.Boundaries.RolesDropdownLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop circle_id, :string, default: nil
  prop role, :any, default: nil
  prop roles, :any, default: nil
  prop scope, :any, default: nil
  prop usage, :any, default: nil
  prop extra_roles, :list, default: []
  prop setting_boundaries, :atom, default: nil
  prop field, :atom, default: :to_circles
  prop read_only, :boolean, default: false
end
