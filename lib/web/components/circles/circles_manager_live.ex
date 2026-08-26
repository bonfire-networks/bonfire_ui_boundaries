defmodule Bonfire.UI.Boundaries.CirclesManagerLive do
  @moduledoc "Manages circles from either the overview or a specific circle's detail view."
  use Bonfire.UI.Common.Web, :stateful_component

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Circles.LiveHandler

  prop widget_id, :string, default: nil
  # DOM id of the reusable modal hosting this manager; when nil, resolved via ReusableModalLive.modal_id/1 (which picks the sticky-context singleton when applicable)
  prop modal_id, :string, default: nil
  prop scope, :any, default: nil
  prop circle_id, :string, default: nil
  # the host page's own (enriched) circle assign: when set, saved changes are merged into it and sent back to the host LiveView
  prop host_circle, :map, default: nil
  prop start_in_create, :boolean, default: false

  @impl true
  def update(assigns, %{assigns: %{loaded: true}} = socket) do
    {:ok, assign(socket, assigns)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    socket = LiveHandler.load_manager(socket, e(assigns, :circle_id, nil))

    socket =
      if e(assigns, :start_in_create, false) do
        LiveHandler.show_manager_create(socket)
      else
        socket
      end

    {:ok, socket}
  end
end
