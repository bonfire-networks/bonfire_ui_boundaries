defmodule Bonfire.UI.Boundaries.WidgetCirclesLive do
  @moduledoc "Dashboard widget linking to the current user's circles."
  use Bonfire.UI.Common.Web, :stateful_component

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.LiveHandler

  prop widget_title, :string, default: nil

  @impl true
  def update(assigns, %{assigns: %{circles: _circles}} = socket) do
    {:ok, assign(socket, assigns)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    circles =
      Circles.list_my_for_sidebar(current_user_or_id(socket),
        exclude_stereotypes: true,
        exclude_built_ins: true
      )

    {:ok, assign(socket, circles: circles)}
  end
end
