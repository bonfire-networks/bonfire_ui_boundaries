defmodule Bonfire.UI.Boundaries.WidgetCirclesLive do
  @moduledoc "Dashboard widget linking to the current user's circles."
  use Bonfire.UI.Common.Web, :stateful_component

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.LiveHandler

  prop widget_title, :string, default: nil

  @doc """
  Returns a short visual identifier derived from a circle name.

  ## Examples

      iex> Bonfire.UI.Boundaries.WidgetCirclesLive.circle_initials("Fosdem")
      "F"

      iex> Bonfire.UI.Boundaries.WidgetCirclesLive.circle_initials("mutual aid")
      "MA"

      iex> Bonfire.UI.Boundaries.WidgetCirclesLive.circle_initials("")
      "•"
  """
  def circle_initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> case do
      [] ->
        "•"

      [word] ->
        String.first(word)

      words ->
        [List.first(words), List.last(words)]
        |> Enum.map_join(&String.first/1)
    end
    |> String.upcase()
  end

  def circle_initials(_name), do: "•"

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
