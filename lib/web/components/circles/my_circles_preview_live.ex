defmodule Bonfire.UI.Boundaries.Web.MyCirclesPreviewLive do
  use Bonfire.UI.Common.Web, :stateless_component
  # alias Bonfire.Boundaries.Integration
  alias Bonfire.UI.Boundaries.LiveHandler

  prop selected_tab, :any, default: "timeline"
  prop loading, :boolean, default: false
  prop hide_tabs, :boolean, default: false
  prop showing_within, :atom, default: :profile
  prop user, :map

  slot header
  slot widget
end
