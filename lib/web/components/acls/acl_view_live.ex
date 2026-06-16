defmodule Bonfire.UI.Boundaries.AclViewLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop acl, :any, default: nil
  prop acl_subject_verb_grants, :any, default: %{}
  prop description, :string, default: nil
end
