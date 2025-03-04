defmodule Bonfire.UI.Boundaries.SidebarCirclesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.LiveHandler

  declare_nav_component("Links to user's personal and subscribed circles", exclude_from_nav: false)

  def update(assigns, socket) do
    # scope = LiveHandler.scope_origin(assigns, socket)
    # |> IO.inspect
    %{page_info: page_info, edges: edges} = LiveHandler.my_circles_paginated(current_user(socket))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       loaded: true,
       circles: edges,
       page_info: page_info
      #  settings_section_title: "Create and manage your circles",
      #  settings_section_description: "Create and manage your circles."
     )}
  end

end
