defmodule Bonfire.UI.Boundaries.AclSubjectsPreviewLive do
  @moduledoc """
  Compact inline preview of a boundary preset's grant subjects: a count plus a
  small avatar group (people show their avatar, circles/named subjects show a
  fallback icon). Shared by the custom and system preset rows in `MyAclsLive`.
  """
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Common.Media
  alias Bonfire.Boundaries.Grants

  prop grants, :any, default: []
  # label shown after the subject count (defaults to "items")
  prop count_label, :string, default: nil
  # tailwind colour class for the fallback (circle/named) subject icon
  prop accent_class, :string, default: "text-primary"
end
