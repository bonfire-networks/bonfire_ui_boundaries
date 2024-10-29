defmodule Bonfire.UI.Boundaries.Web.ExcludeBoundaries do
  use Bonfire.UI.Common
  alias Bonfire.UI.Boundaries.Web.SetBoundariesLive

  def handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket) do
    SetBoundariesLive.live_select_change(live_select_id, search, :exclude_circles, socket)
  end

  def handle_event(
        event,
        params,
        socket
      ) do
    SetBoundariesLive.handle_event(
      event,
      params,
      socket
    )
  end
end
