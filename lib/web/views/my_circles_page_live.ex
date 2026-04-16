defmodule Bonfire.UI.Boundaries.MyCirclesPageLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  declare_nav_link(l("Circles"),
    page: "circles",
    icon: "ph:circle-duotone"
  )

  declare_module_optional(l("Circles page link in sidebar nav"),
    default: true
  )

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: l("My Circles"),
       page: "circles",
       scope: nil,
       back: true,
       page_header_icon: "ph:circle-duotone",
       page_header_aside: [
         {Bonfire.UI.Boundaries.NewCircleButtonLive,
          [
            # id: "page_new_circle",
            scope: nil,
            setting_boundaries: false
          ]}
       ]
     )}
  end
end
