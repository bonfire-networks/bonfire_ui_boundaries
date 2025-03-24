defmodule Bonfire.UI.Boundaries.SharedCircleLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias Bonfire.Boundaries.Circles

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(params, _session, socket) do
    id = e(params, "id", nil)
    assign_circle(id, socket, :ok)
  end

  def handle_params(%{"tab" => "members"}, _session, socket) do
    with {:ok, data} <-
           load_members(
             e(assigns(socket), :circle_id, nil) || e(assigns(socket), :circle, :id, nil)
           ) do
      {:noreply, socket |> assign(:selected_tab, "members") |> assign(data)}
    end
  end

  def handle_params(params, _session, socket) do
    id = e(params, "id", nil)

    if id not in [
         "circle",
         e(assigns(socket), :circle_id, nil) || e(assigns(socket), :circle, :id, nil)
       ] do
      assign_circle(id, socket, :noreply)
    else
      {:noreply,
       socket
       |> assign(:selected_tab, nil)}
    end
  end

  def assign_circle(id, socket, ok_atom) do
    current_user = current_user(socket)

    with {:ok, data} <-
           load_circle(
             id,
             current_user: current_user
           )
           |> debug("load_circle") do
      name = e(data, :name, nil)

      {ok_atom,
       socket
       |> assign(
         nav_items: Bonfire.Common.ExtensionModule.default_nav(),
         page_title: name,
         selected_tab: nil,
         members: [],
         feed_name: :custom,
         feed_title: name,
         feed_filters: %{subject_circles: [e(data, :circle, :id, nil)]},
         page_info: nil
       )
       |> assign(data)}
    else
      {:error, :not_found} ->
        if current_user do
          {:ok,
           socket
           |> redirect_to(
             if(id, do: "/boundaries/scope/user/circle/#{id}", else: "boundaries/circles")
           )}
        else
          error(id, "Not found or permitted")
          raise(Bonfire.Fail, :not_found)
        end

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
         circle_id: id,
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

  def load_members(circle, opts \\ []) do
    # Get the total count for display purposes
    total_members_count = nil
    # Circles.count_members(id)
    # |> debug("total_members_count")

    # Load members with cursor-based pagination
    %{edges: members, page_info: page_info} =
      Circles.list_members(
        Enums.id(circle),
        opts
      )
      |> debug("paginated_members")

    {:ok,
     %{
       total_members_count: total_members_count,
       page_info: page_info,
       members: members || []
     }}
  end
end
