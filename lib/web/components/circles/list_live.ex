defmodule Bonfire.UI.Boundaries.ListLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Circles

  prop circle_id, :string, default: nil
  prop circle, :map, default: %{}
  prop members, :map, default: []
  prop page_info, :map, default: nil

  def update(assigns, %{assigns: %{loaded: true}} = socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    params = e(assigns(socket), :__context__, :current_params, %{})

    {:ok,
     assign(
       socket,
       if(socket_connected?(socket),
         do:
           load_circle(
             (e(assigns, :circle_id, nil) || e(params, "id", nil))
             |> debug("circle_id"),
             current_user: current_user(socket)
           )
       ) || []
     )}
  end

  # def handle_event("load_more", attrs, socket) do
  #   %{page_info: page_info, users: users} = load_circle(e(assigns(socket), :show, :local), attrs)

  #   {:noreply,
  #    socket
  #    |> assign(
  #      loaded: true,
  #      #  users: e(assigns(socket), :users, []) ++ users,
  #      users: users,
  #      page_info: page_info
  #    )}
  # end

  def load_circle(id, opts) do
    with %{id: id} = circle <-
           Circles.get(id, opts)
           |> repo().maybe_preload(encircles: [subject: [:profile, :character]])
           |> repo().maybe_preload(encircles: [subject: [:named]])
           |> ok_unwrap() do
      debug(circle, "circle")

      members =
        e(circle, :encircles, [])
        |> Enum.map(& &1.subject)
        # |> Map.new()
        |> debug("members")

      %{
        circle: circle |> Map.drop([:encircles]),
        members: members || %{},
        # page_info: page_info,
        loaded: true
      }
    end
  end
end
