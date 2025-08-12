defmodule Bonfire.UI.Boundaries.EditAclLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop acl_subject_verb_grants, :any, default: nil
  prop setting_boundaries, :boolean, default: false
  prop scope, :any, default: nil
  prop usage, :any, default: :all
  prop read_only, :boolean, default: false
end
