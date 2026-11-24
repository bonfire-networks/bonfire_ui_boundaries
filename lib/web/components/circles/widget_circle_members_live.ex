defmodule Bonfire.UI.Boundaries.WidgetCircleMembersLive do
  @moduledoc """
  The members of a circle, as the viewer may see them (a guest sees only a circle shared with everyone, without those who chose to be undiscoverable): in a main area as a grid (`Bonfire.UI.Me.UsersGridLive`, `:links` or `:portrait`), in a sidebar as a list.

  The circle is the `circle` prop (eg. `?circle=` when embedded), else the one chosen in the widget settings (`[__MODULE__, :circle]`, see `Bonfire.UI.Boundaries.WidgetCircleSelectLive`). With no circle, or nobody to show, it renders nothing, so places hide it.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.Boundaries.Circles

  declare_widget(l("Circle members"), id: :circle_members)

  @doc "A circle or its id; the one chosen in the widget settings when not given."
  prop circle, :any, default: nil
  prop variant, :atom, default: :links, values: [:links, :portrait]
  prop showing_within, :atom, default: :sidebar

  @doc "Its props when embedded on another site (see `Bonfire.UI.Common.EmbedWidgetLive`): `?circle=` and `?variant=portrait` for avatar tiles."
  def embed_props(params),
    do: [
      circle: params["circle"],
      variant: if(params["variant"] == "portrait", do: :portrait, else: :links),
      showing_within: :main
    ]

  @doc "The circle and up to 48 of its members, as `viewer` may see them, or nil."
  def load(circle, viewer) do
    with id when is_binary(id) <- Bonfire.Common.Types.uid(circle),
         {:ok, circle} <- Circles.get(id, current_user: viewer),
         [_ | _] = members <-
           circle
           |> Circles.list_members(current_user: viewer, limit: 48)
           |> e(:edges, [])
           |> Enum.map(&e(&1, :subject, nil))
           |> Enum.reject(&is_nil/1) do
      {circle, members}
    else
      _ -> nil
    end
  end

  def render(assigns) do
    viewer = current_user(assigns[:__context__])

    assigns
    |> assign(
      :loaded,
      load(
        assigns.circle ||
          Bonfire.Common.Settings.get([__MODULE__, :circle], nil, current_user: viewer),
        viewer
      )
    )
    |> render_sface()
  end
end
