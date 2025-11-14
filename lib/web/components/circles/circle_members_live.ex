defmodule Bonfire.UI.Boundaries.CircleMembersLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Blocks
  alias Bonfire.Boundaries.Circles.LiveHandler

  prop circle_id, :any, default: nil
  prop circle, :any, default: nil
  prop circle_type, :atom, default: nil
  prop blocked_intersection_ids, :list, default: nil
  prop name, :string, default: nil
  prop title, :string, default: nil
  prop description, :string, default: nil
  prop parent_back, :any, default: nil
  prop setting_boundaries, :atom, default: nil
  prop scope, :any, default: nil
  prop showing_within, :atom, default: nil
  prop feedback_title, :string, default: nil
  prop feedback_message, :string, default: nil
  prop read_only, :boolean, default: false
  prop show_add, :boolean, default: nil
  prop show_remove, :boolean, default: nil
  prop with_batch_follow, :boolean, default: false

  slot default, required: false

  def update(assigns, %{assigns: %{loaded: true} = socket_assigns} = socket) do
    # When already loaded, we still need to update the page_title if a new title is provided
    title_from_assigns = e(assigns, :title, nil)

    if title_from_assigns do
      # Get the circle from socket assigns
      circle = e(socket_assigns, :circle, nil)

      # Update page_title with the new title
      final_title =
        title_from_assigns ||
          e(circle, :named, :name, nil) ||
          e(circle, :stereotyped, :named, :name, nil) ||
          l("Circle")

      if socket_connected?(socket),
        do: send_self(page_title: final_title)
    end

    {
      :ok,
      socket
      |> assign(Enums.filter_empty(assigns, []))
    }
  end

  def update(assigns, socket) do
    current_user = current_user(assigns) || current_user(socket)

    params =
      e(assigns, :__context__, :current_params, %{})
      |> debug("current_params")

    id =
      (e(assigns, :circle_id, nil) || e(params, "id", nil))
      |> debug("circle_id")

    socket =
      socket
      |> assign(assigns)
      |> assign(
        # page_title: l("Circle"),
        # section: e(params, "section", "members"),
        settings_section_description: l("Create and manage your circle.")
      )

    with %{id: id} = circle <-
           (e(assigns, :circle, nil) ||
              Circles.get_for_caretaker(id, current_user, scope: e(assigns(socket), :scope, nil)))
           |> repo().maybe_preload(:extra_info)
           |> from_ok() do
      # Get the total count for display purposes
      total_members_count = nil
      # Circles.count_members(id)
      # |> debug("total_members_count")

      # Load members with cursor-based pagination
      %{edges: members, page_info: page_info} =
        Circles.list_members(
          id,
          current_user: current_user
        )
        |> debug("paginated_members")

      # Filter to intersection if blocked tab
      {members, page_info} =
        if intersection_ids = e(assigns, :blocked_intersection_ids, nil) do
          filtered = Enum.filter(members, fn member -> member.subject_id in intersection_ids end)
          {filtered, %{}}
        else
          {members, page_info}
        end

      # TODO: handle pagination
      # followed =
      #   Bonfire.Social.Graph.Follows.list_my_followed(current_user,
      #     paginate: false,
      #     exclude_ids: member_ids
      #   )

      # already_seen_ids = member_ids ++ Enum.map(followed, & &1.edge.object_id)

      # # |> debug
      # followers =
      #   Bonfire.Social.Graph.Follows.list_my_followers(current_user,
      #     paginate: false,
      #     exclude_ids: already_seen_ids
      #   )

      # # |> debug

      # suggestions =
      #   Enum.map(followers ++ followed ++ [current_user], fn follow ->
      #     u = f(follow)
      #     {uid(u), u}
      #   end)
      #   |> Map.new()
      #   |> debug

      stereotype_id = e(circle, :stereotyped, :stereotype_id, nil)

      follow_stereotypes = Circles.stereotypes(:follow)

      read_only = e(assigns, :read_only, nil) || e(assigns(socket), :read_only, nil)

      read_only =
        if is_nil(read_only) do
          Circles.is_built_in?(circle) ||
            stereotype_id in follow_stereotypes
        else
          read_only
        end

      if socket_connected?(socket),
        do:
          send_self(
            read_only: read_only,
            page_title:
              e(assigns, :title, nil) || e(assigns(socket), :title, nil) ||
                e(circle, :named, :name, nil) || e(assigns(socket), :name, nil) ||
                e(circle, :stereotyped, :named, :name, nil) || l("Circle"),
            back: true
            # circle: circle
            # page_header_aside: [
            #   {Bonfire.UI.Boundaries.HeaderCircleLive,
            #    [
            #      circle: circle,
            #      stereotype_id: stereotype_id,
            #      #  suggestions: suggestions,
            #      read_only: read_only
            #    ]}
            # ]
          )

      {:ok,
       assign(
         socket,
         loaded: true,
         circle_id: id,
         # |> Map.drop([:encircles]),
         circle: circle,
         members:
           Enum.map(members, &{&1.subject_id, &1})
           |> Map.new(),
         #  page_title: l("Circle"),
         #  suggestions: suggestions,
         #  stereotype_id: stereotype_id,
         read_only: read_only,
         #  settings_section_title: "Manage " <> e(circle, :named, :name, "") <> " circle",
         page_info: page_info,
         total_count: total_members_count
       )}

      # else other ->
      #   error(other)
      #   {:ok, socket
      #     |> assign_flash(:error, l "Could not find circle")
      #     |> assign(
      #       circle: nil,
      #       members: [],
      #       suggestions: [],
      #       read_only: true
      #     )
      #     # |> redirect_to("/boundaries/circles")
      #   }
    end
  end

  # Handle LiveSelect member selection - single mode (expects JSON string)
  def handle_event(
        "change",
        %{"_target" => ["multi_select", field_name], "multi_select" => multi_select_data} =
          params,
        socket
      )
      when is_map_key(multi_select_data, field_name) and
             is_binary(:erlang.map_get(field_name, multi_select_data)) and
             :erlang.map_get(field_name, multi_select_data) != "" do
    debug(params, "LiveSelect member selection")
    json_string = multi_select_data[field_name]
    selected_member = decode_selected_member(json_string)

    if selected_member do
      LiveHandler.add_member(selected_member, socket)
    else
      {:noreply, socket}
    end
  end

  # Handle LiveSelect clear selection - dynamic field names (like SelectRecipientsLive)
  def handle_event(
        "change",
        %{"_target" => ["multi_select", field_name], "multi_select" => multi_select_data} =
          params,
        socket
      )
      when is_map_key(multi_select_data, field_name) do
    case {String.ends_with?(field_name, "_empty_selection"), multi_select_data[field_name]} do
      {true, ""} ->
        debug(params, "LiveSelect clearing selection")
        # Clear operation - no action needed for member selection
        {:noreply, socket}

      _ ->
        # Non-empty selection, should be handled by first handler
        {:noreply, socket}
    end
  end

  # Catch-all handler for other change event patterns
  def handle_event("change", _params, socket) do
    {:noreply, socket}
  end

  #  special case needed for tests that don't go through live_select
  def handle_event("multi_select", %{"data" => data, "text" => text}, socket) do
    debug(data, "multi_select_circle_live")
    LiveHandler.add_member(input_to_atoms(data), socket)
  end

  def handle_event(
        "multi_select",
        %{
          "Elixir.Bonfire.UI.Boundaries.CircleMembersLive_text_input" => "",
          "Elixir.Bonfire.UI.Boundaries.CircleMembersLive" => ""
        },
        socket
      ) do
    {:noreply, socket}
  end

  def handle_event(
        "multi_select",
        %{"_target" => _target, "add_to_circles" => multi_select_data},
        socket
      ) do
    debug(multi_select_data, "multi_select_data")
    {:noreply, socket}
  end

  # Catch-all for other multi_select events
  def handle_event("multi_select", params, socket) do
    debug(params, "unhandled_multi_select")
    {:noreply, socket}
  end

  def handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket)
      when is_binary(search) do
    debug(search, "LiveSelect autocomplete search")
    handle_member_search(search, live_select_id, socket)
  end

  def handle_event(
        "live_select_change",
        %{"id" => live_select_id, "text" => search},
        %{assigns: %{circle_type: circle_type}} = socket
      )
      when circle_type in [:silence, :ghost, :block] and is_binary(search) do
    debug(search, "LiveSelect autocomplete search for blocking circles")
    handle_member_search_with_exclusion(search, live_select_id, socket)
  end

  def handle_event(
        "remove",
        %{"subject" => id} = _attrs,
        %{assigns: %{scope: scope, circle_type: circle_type}} = socket
      )
      when is_binary(id) and circle_type in [:silence, :ghost, :block] do
    with {:ok, _} <-
           Blocks.unblock(id, circle_type, scope || current_user(socket)) do
      {:noreply,
       socket
       |> update(:members, &Map.drop(&1, [id]))
       |> assign_flash(:info, l("Unblocked!"))}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not unblock"))}
    end
  end

  def handle_event("remove", %{"subject" => id} = _attrs, socket) when is_binary(id) do
    with {1, _} <-
           Circles.remove_from_circles(id, e(assigns(socket), :circle, nil)) do
      {:noreply,
       socket
       |> update(:members, &Map.drop(&1, [id]))
       |> assign_flash(:info, l("Removed from circle!"))}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not remove from circle"))}
    end
  end

  def handle_event(event, params, socket) do
    debug(event, "Unmatched event")
    debug(params, "Unmatched event params")
    {:noreply, socket}
  end

  # Handle member search for autocomplete - use provided live_select_id
  defp handle_member_search(search, live_select_id, socket) when byte_size(search) >= 2 do
    search_results = do_results_for_multiselect(search)
    maybe_send_update(LiveSelect.Component, live_select_id, options: search_results)
    {:noreply, socket}
  end

  defp handle_member_search(_search, _live_select_id, socket) do
    {:noreply, socket}
  end

  # Handle member search with current user exclusion for blocking circles
  defp handle_member_search_with_exclusion(search, live_select_id, socket)
       when byte_size(search) >= 2 do
    current_user_id =
      current_user_id(socket)
      |> debug("avoid blocking myself")

    search_results =
      do_results_for_multiselect(search)
      |> Enum.reject(fn {_name, %{id: id}} -> id == current_user_id end)

    maybe_send_update(LiveSelect.Component, live_select_id, options: search_results)
    {:noreply, socket}
  end

  defp handle_member_search_with_exclusion(_search, _live_select_id, socket) do
    {:noreply, socket}
  end

  # Decode selected member from LiveSelect JSON string (single mode)
  defp decode_selected_member(json_string) when is_binary(json_string) do
    decode_single_member(json_string)
  end

  defp decode_selected_member(_), do: nil

  defp decode_single_member(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, data} -> format_decoded_member(data)
      {:error, _} -> nil
    end
  end

  defp decode_single_member(data) when is_map(data) do
    format_decoded_member(data)
  end

  defp decode_single_member(_), do: nil

  defp format_decoded_member(data) do
    %{
      id: data["id"] || data[:id],
      username: data["username"] || data[:username],
      name: data["name"] || data[:name] || "Unnamed",
      icon: data["icon"] || data[:icon],
      type: data["type"] || data[:type] || "user",
      field: data["field"] || data[:field]
    }
  end

  def do_results_for_multiselect(search) do
    Bonfire.Common.Utils.maybe_apply(
      Bonfire.Me.Users,
      :search,
      [search]
    )
    |> Enum.map(fn
      %Needle.Pointer{activity: %{object: user}} -> user
      other -> other
    end)
    |> Bonfire.UI.Boundaries.SetBoundariesLive.results_for_multiselect()
    |> debug("results_for_multiselect")
  end

  # def f(%{edge: %{object: %{profile: _} = user}}), do: user
  # def f(%{edge: %{subject: %{profile: _} = user}}), do: user
  # def f(user), do: user
end
