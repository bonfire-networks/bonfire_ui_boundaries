defmodule Bonfire.UI.Boundaries.CircleLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias Bonfire.Boundaries.Circles

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:circle, nil)
     |> assign(:circle_id, nil)
     |> assign(:selected_tab, nil)
     |> assign(:read_only, true)
     |> assign(:to_boundaries, nil)
     |> assign(:boundary_preset, nil)
     |> assign(:feed_filters, %{})
     |> assign(:feed_name, nil)
     |> assign(:feed_title, nil)
     |> assign(:page_info, nil)
     |> assign(:members, [])
     |> assign(:member_count, 0)
     |> assign(:preview_members, [])
     |> assign(:is_member, false)
     |> assign(:created_ago, nil)
     |> assign(:is_caretaker, false)
     |> assign(:page, nil)}
  end

  def handle_params(params, _session, socket) do
    id = e(params, "id", nil)

    if id not in [
         "circle",
         e(assigns(socket), :circle_id, nil) || e(assigns(socket), :circle, :id, nil)
       ] do
      socket
      |> assign(:page, id)
      |> assign(:back, true)
      |> assign(:selected_tab, params["tab"])
      |> assign_circle(id, params, :noreply)
    else
      {:noreply,
       socket
       |> assign(:selected_tab, params["tab"])}
    end
  end

  def assign_circle(socket, id, params, ok_atom) do
    current_user = current_user(socket)

    with {:ok, data} <-
           load_circle(
             id,
             current_user
           )
           |> debug("load_circle") do
      name = e(data, :name, nil)

      {ok_atom,
       socket
       |> assign(
         read_only: true,
         page_title: l("Circle"),
         feed_name: :custom,
         feed_title: name,
         feed_filters: %{subject_circles: [e(data, :circle, :id, nil)]},
         page_info: nil,
         show_remove: true,
         sidebar_widgets: []
       )
       |> assign(data)}
    else
      {:error, :not_found} ->
        if current_user do
          scope =
            e(params, "scope", nil) ||
              (id in Bonfire.Boundaries.Scaffold.Instance.global_circles() && "instance") ||
              "user"

          {ok_atom,
           socket
           |> redirect_to(
             if(id,
               do: "/boundaries/scope/#{scope}/circle/#{id}",
               else: "boundaries/circles"
             )
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

  def load_circle(id, current_user) do
    with {:ok, %{id: id} = circle} <-
           Circles.get(id, current_user: current_user)
           |> repo().maybe_preload(caretaker: [caretaker: [:profile, :character]])
           |> repo().maybe_preload(:extra_info) do
      creator_username = e(circle, :caretaker, :caretaker, :character, :username, nil)

      creator_name =
        e(circle, :caretaker, :caretaker, :profile, :name, nil) || creator_username

      creator_id = e(circle, :caretaker, :caretaker, :character, :id, nil)

      preset_acl = Bonfire.Boundaries.Controlleds.get_preset_on_object(id)

      object_boundary =
        Bonfire.Boundaries.boundary_on_object(id, preset_acl, current_user)
        |> debug("boundary_on_object")

      is_caretaker =
        creator_id == id(current_user) or
          Bonfire.Boundaries.can?(current_user, :configure, object_boundary)

      member_count = Circles.count_members(id)

      preview_members =
        case Circles.list_members(id, limit: 5) do
          %{edges: edges} when is_list(edges) -> edges
          list when is_list(list) -> list
          _ -> []
        end

      is_member =
        if current_user,
          do: Circles.is_encircled_by?(current_user, id),
          else: false

      created_ago = DatesTimes.date_from_now(id)

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
         loaded: true,
         to_boundaries: object_boundary,
         boundary_preset:
           if(preset_acl,
             do:
               Bonfire.Boundaries.Presets.preset_boundary_tuple_from_acl(
                 preset_acl,
                 Bonfire.Data.AccessControl.Circle
               ),
             else: {"private", l("Private")}
           )
           |> debug("boundary_preset"),
         member_count: member_count,
         preview_members: preview_members,
         is_member: is_member,
         created_ago: created_ago,
         is_caretaker: is_caretaker,
         read_only:
           is_nil(current_user) or
             !(is_caretaker or
                 Bonfire.Boundaries.can?(current_user, :edit, object_boundary)
                 |> debug("can assign?"))
       }}
    end
  end
end
