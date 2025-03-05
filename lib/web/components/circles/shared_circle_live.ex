defmodule Bonfire.UI.Boundaries.SharedCircleLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias Bonfire.Boundaries.Circles

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(params, _session, socket) do
    with {:ok, data} <-
           load_circle(
             e(params, "id", nil),
             current_user: current_user(socket)
           ) do
      name = e(data, :name, nil)

      {:ok,
       socket
       |> assign(:page_title, name)
       |> assign(:members, [])
       |> assign(:nav_items, Bonfire.Common.ExtensionModule.default_nav())
       |> assign(data)
       |> assign(
         feed_name: nil,
         feed_title: name,
         feed_filters: %{subject_circles: [e(data, :circle, :id, nil)]}
       )}
    else
      _ ->
        raise(Bonfire.Fail, :not_found)
    end
  end

  def handle_params(%{"tab" => "members"}, _session, socket) do
    with {:ok, data} <- load_members(e(assigns(socket), :circle, nil)) do
      {:noreply, socket |> assign(:selected_tab, "members") |> assign(data)}
    end
  end

  def handle_params(_, _session, socket) do
    {:noreply,
     socket
     |> assign(:selected_tab, nil)}
  end

  def load_circle(id, opts) do
    with %{id: id} = circle <-
           Circles.get(id, opts)
           |> repo().maybe_preload(caretaker: [caretaker: [:profile, :character]])
           |> repo().maybe_preload(:extra_info)
           |> ok_unwrap() do
      creator_name =
        e(circle, :caretaker, :caretaker, :profile, :name, nil) ||
          e(circle, :caretaker, :caretaker, :character, :username, "Unknown")

      creator_username = e(circle, :caretaker, :caretaker, :character, :username, "Unknown")
      creator_id = e(circle, :caretaker, :caretaker, :character, :id, nil)

      {:ok,
       %{
         circle:
           circle
           |> Map.drop([:caretaker])
           |> Map.put(:creator_id, creator_id)
           |> Map.put(:creator_name, creator_name)
           |> Map.put(:creator_username, creator_username),
         name: e(circle, :named, :name, nil),
         loaded: true
       }}
    end
  end

  def load_members(circle, _opts \\ []) do
    with %{id: _id} = circle <-
           circle
           |> repo().maybe_preload(encircles: [subject: [:profile, :character]])
           |> repo().maybe_preload(encircles: [subject: [:named]])
           |> ok_unwrap() do
      members =
        e(circle, :encircles, [])
        |> Enum.map(& &1.subject)
        |> debug("members")

      {:ok,
       %{
         members: members || []
       }}
    end
  end
end
