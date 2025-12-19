defmodule Bonfire.UI.Boundaries.SidebarCirclesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.LiveHandler

  declare_nav_component("Links to user's personal and subscribed circles",
    exclude_from_nav: false
  )

  def update(assigns, %{assigns: %{circles: _}} = socket) do
    debug("already loaded")

    {:ok,
     socket
     |> assign(assigns)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)

    # scope = LiveHandler.scope_origin(assigns, socket)
    # |> IO.inspect
    %{page_info: page_info, edges: circles} =
      if circles = e(assigns(socket), :__context__, :my_circles, nil) || assigns(socket)[:my_circles] do
        debug("my_circles was preloaded at top level")
        %{page_info: nil, edges: circles}
      else
        Bonfire.Boundaries.Circles.LiveHandler.my_circles_paginated(current_user(socket))
      end

    # Always append the suggested profiles circle if not already present # TODO: add a way to hide in settings?
    suggested = Bonfire.Boundaries.Circles.get_built_in(:suggested_profiles)

    {:ok,
     socket
     |> assign(
       loaded: true,
       circles: circles ++ [suggested],
       page_info: page_info
       #  settings_section_title: "Create and manage your circles",
       #  settings_section_description: "Create and manage your circles."
     )}
  end
end
