defmodule Bonfire.UI.Boundaries.AclModalLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop subject_id, :any, default: nil
  prop grants, :any, default: false
  prop verbs, :any, default: nil
  prop myself, :any, default: nil
  prop role_title, :atom, default: nil
end
