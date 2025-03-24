defmodule Bonfire.UI.Boundaries.AddToCircleLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.UI.Boundaries.AddToCircleWidgetLive

  prop circles, :list, default: []
  prop user_id, :any, default: nil
  prop parent_id, :any, default: nil
  prop name, :any, default: nil
  prop as_icon, :boolean, default: false
  prop label, :any, default: nil
end
