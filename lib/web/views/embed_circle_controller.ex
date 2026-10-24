defmodule Bonfire.UI.Boundaries.EmbedCircleController do
  use Bonfire.UI.Common.Web, :controller

  def index(conn, params),
    do:
      live_render(conn, Bonfire.UI.Boundaries.EmbedCircleLive,
        layout: {Bonfire.UI.Common.LayoutView, :iframe},
        # conn assigns and params don't reach a controller-rendered LiveView's mount, so pass the params through the session; the layout assigns come from `ThemeHelper.setup_embed` in the mount
        session: %{"params" => params}
      )
end
