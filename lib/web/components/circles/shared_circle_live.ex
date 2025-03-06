defmodule Bonfire.UI.Boundaries.SharedCircleLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias Bonfire.Boundaries.Circles

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(params, _session, socket) do
    id = e(params, "id", nil)
    assign_circle(id, socket, :ok)
  end

  def handle_params(%{"tab" => "members"}, _session, socket) do
    with {:ok, data} <- load_members(e(assigns(socket), :circle, nil)) do
      {:noreply, socket |> assign(:selected_tab, "members") |> assign(data)}
    end
  end

  def handle_params(params, _session, socket) do
    id = e(params, "id", nil)

    if id not in ["circle", e(assigns(socket), :circle, :id, nil)] do
      assign_circle(id, socket, :noreply)
    else
      {:noreply,
       socket
       |> assign(:selected_tab, nil)}
    end
  end

  def assign_circle(id, socket, ok_atom) do
    with {:ok, data} <-
           load_circle(
             id,
             current_user: current_user(socket)
           ) do
      name = e(data, :name, nil)

      {ok_atom,
       socket
       |> assign(:page_title, name)
       |> assign(:selected_tab, nil)
       |> assign(:members, [])
       |> assign(:nav_items, Bonfire.Common.ExtensionModule.default_nav())
       |> assign(data)
       |> assign(
         feed_name: :custom,
         feed_title: name,
         feed_filters: %{subject_circles: [e(data, :circle, :id, nil)]}
       )}
    else
      {:error, :not_found} ->
        {:ok,
         socket
         |> redirect_to(
           if(id, do: "/boundaries/scope/user/circle/#{id}", else: "boundaries/circles")
         )}

      e ->
        error(e)
        raise(Bonfire.Fail, e)
    end
  end

  def load_circle(id, opts) do
    with {:ok, %{id: id} = circle} <-
           Circles.get(id, opts)
           |> repo().maybe_preload(caretaker: [caretaker: [:profile, :character]])
           |> repo().maybe_preload(:extra_info) do
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
