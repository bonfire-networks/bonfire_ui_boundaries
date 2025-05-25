defmodule Bonfire.Boundaries.Circles.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler
  alias Bonfire.Boundaries.{Circles, Blocks}

  def handle_params(%{"after" => cursor} = params, _uri, socket) do
    current_user = current_user(socket)
    # Get the current circle
    circle_id = e(assigns(socket), :circle_id, nil) || Enums.id(e(assigns(socket), :circle, nil))

    if circle_id do
      # Load the next page of members
      %{edges: members, page_info: page_info} =
        Circles.list_members(
          circle_id,
          current_user: current_user,
          pagination: input_to_atoms(params)
        )
        |> debug("more_paginated_members")

      {:noreply,
       socket
       |> assign(
         members:
           Enum.map(members, &{&1.subject_id, &1})
           |> Map.new(),
         page_info: page_info
       )}
    else
      debug(assigns(socket), "Dunno what circle to paginate for")
      {:noreply, socket}
    end
  end

  # Add handler for the load_more event
  def handle_event("load_more", %{} = params, socket) do
    current_user = current_user_required!(socket)
    # Get the current circle
    circle_id = e(assigns(socket), :circle_id, nil) || Enums.id(e(assigns(socket), :circle, nil))

    if circle_id do
      # Load the next page of members
      %{edges: members, page_info: page_info} =
        Circles.list_members(
          circle_id,
          current_user: current_user,
          pagination: input_to_atoms(params)
        )
        |> debug("more_paginated_members")

      {:noreply,
       socket
       |> assign(
         members:
           Map.merge(
             e(assigns(socket), :members, %{}),
             Enum.map(members, &{&1.subject_id, &1})
             |> Map.new()
           ),
         page_info: page_info
       )}
    else
      debug(assigns(socket), "Dunno what circle to paginate for")
      {:noreply, socket}
    end
  end

  def handle_event("multi_select", %{"data" => data, "text" => text}, socket) do
    debug(data, "multi_select_circle_live")
    add_member(input_to_atoms(data), socket)
  end

  def handle_event("multi_select", %{"id" => id, "name" => _name}, socket) do
    debug(id, "multi_select_circle_live")
    add_member(input_to_atoms(e(assigns(socket), :suggestions, %{})[id]) || id, socket)
  end

  def handle_event(
        "multi_select",
        %{"_target" => ["multi_select", module_name], "multi_select" => multi_select_data} =
          params,
        socket
      ) do
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "live_select_change",
        %{"field" => _field, "id" => live_select_id, "text" => search},
        socket
      ) do
    current_user = current_user(socket)

    results =
      Bonfire.Me.Users.search(search,
        current_user: current_user,
        paginate: false
      )
      |> prepare_results_for_multiselect()
      |> maybe_filter_current_user(socket)

    maybe_send_update(LiveSelect.Component, live_select_id, options: results)

    {:noreply, socket}
  end

  def handle_event("remove_from_circle", %{"subject_id" => subject}, socket) do
    _current_user = current_user_required!(socket)
    id = uid!(e(assigns(socket), :circle, nil))

    with {:ok, _circle} <-
           Circles.remove_from_circles(subject, id) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Member was removed"))
       |> redirect_to("/boundaries/circles")}
    end
  end

  def handle_event("toggle_circles_nav_visibility", _params, socket) do
    debug("toggle_circles_nav_visibility")

    with {:ok, settings} <-
           Bonfire.Common.Settings.set(
             %{
               Bonfire.UI.Boundaries.MyCirclesLive => %{
                 show_circles_nav_open:
                   !Bonfire.Common.Settings.get(
                     [Bonfire.UI.Boundaries.MyCirclesLive, :show_circles_nav_open],
                     true,
                     socket
                   )
               }
             },
             current_user: current_user(socket)
           ) do
      {
        :noreply,
        socket |> maybe_assign_context(settings)
      }
    end
  end

  def handle_event("create", %{"name" => name} = attrs, socket) do
    circle_create(Map.merge(attrs, %{named: %{name: name}}), socket)
  end

  def handle_event("create", attrs, socket) do
    circle_create(attrs, socket)
  end

  def handle_event("validate_for_create", attrs, socket) do
    {:noreply, socket}
  end

  def handle_event("edit", attrs, socket) do
    debug(e(attrs, "circle_id", nil), "edit circlee")
    id = uid!(e(attrs, "circle_id", nil))

    with {:ok, circle} <-
           Circles.edit(
             id,
             current_user_required!(socket),
             attrs
           ) do
      send_self(page_title: e(circle, :named, :name, nil))
      # maybe_send_update(Bonfire.UI.Boundaries.ManageCircleLive, "view_circle", circle: circle)
      maybe_send_update(Bonfire.UI.Common.ReusableModalLive, "edit_boundary", show: false)

      {:noreply,
       socket
       |> assign_flash(:info, l("Edited!"))
       # Close the modal by setting show to false
       |> assign(show: false)
       |> assign(circle: circle)}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not edit circle"))}
    end
  end

  def handle_event("circle_edit", %{"circle" => circle_params}, socket) do
    # params = input_to_atoms(params)
    id = uid!(e(assigns(socket), :circle, nil))

    with {:ok, _circle} <-
           Circles.edit(id, current_user_required!(socket), %{
             encircles: e(circle_params, "encircle", [])
           }) do
      {:noreply, assign_flash(socket, :info, "OK")}
    end
  end

  def handle_event("circle_delete", _, socket) do
    id = uid!(e(assigns(socket), :circle, nil))

    with {:ok, _circle} <-
           Circles.delete(id, current_user_required!(socket)) |> debug() do
      {:noreply,
       socket
       |> assign_flash(:info, l("Deleted"))
       |> redirect_to("/boundaries/circles")}
    end
  end

  def circle_create(attrs, socket) do
    current_user = current_user_required!(socket)
    scope = maybe_to_atom(e(attrs, "scope", nil))

    with {:ok, %{id: id} = circle} <-
           Circles.create(
             scope || current_user,
             attrs
           ) do
      # Bonfire.UI.Common.OpenModalLive.close()

      socket
      |> assign_flash(:info, "Circle created!")
      |> assign(
        circles: [circle] ++ e(assigns(socket), :circles, []),
        section: nil
      )
      |> maybe_redirect_to(
        ~p"/circle/#{id}",
        attrs
      )
      |> maybe_add_to_acl(circle)
    end
  end

  defp maybe_add_to_acl(socket, subject) do
    _current_user = current_user_required!(socket)

    if e(assigns(socket), :acl, nil) do
      Bonfire.UI.Boundaries.AclLive.add_to_acl(subject, socket)
    else
      {:noreply, socket}
    end
  end

  defp maybe_filter_current_user(results, %{assigns: %{circle_type: circle_type}} = socket)
       when circle_type in [:silence, :ghost] do
    current_user_id = current_user_id(socket)
    Enum.reject(results, fn {_name, id} -> id == current_user_id end)
  end

  defp maybe_filter_current_user(results, _), do: results

  defp prepare_results_for_multiselect({:ok, results}) do
    results
    |> Enum.map(fn user ->
      name = e(user, :profile, :name, nil) || e(user, :character, :username, nil)
      {name, uid(user)}
    end)
  end

  defp prepare_results_for_multiselect(_), do: []

  def add_member(subject, %{assigns: %{scope: scope, circle_type: circle_type}} = socket)
      when circle_type in [:silence, :ghost] do
    with id when is_binary(id) <- uid(subject),
         current_user_id when not is_nil(current_user_id) <- current_user_id(socket),
         false <- id == current_user_id,
         {:ok, _} <- Blocks.block(id, circle_type, scope || current_user(socket)) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Blocked!"))
       |> assign(
         members:
           Map.merge(
             %{id => subject},
             e(assigns(socket), :members, %{})
           )
           |> debug()
       )}
    else
      true ->
        {:noreply, assign_flash(socket, :error, l("Cannot block yourself."))}

      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not block"))}
    end
  end

  def add_member(subject, socket) do
    with id when is_binary(id) <- uid(subject),
         current_user_id when is_binary(current_user_id) <- current_user_id(socket),
         {:ok, _} <- Circles.add_to_circles(id, e(assigns(socket), :circle, nil)) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Added to circle!"))
       |> assign(
         members:
           Map.merge(
             %{id => subject},
             e(assigns(socket), :members, %{})
           )
       )}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not add to circle"))}
    end
  end

  # def set_circles(selected_circles, previous_circles, add_to_previous \\ false) do
  #   # debug(previous_circles: previous_circles)
  #   # selected_circles = Enum.uniq(selected_circles)
  #   # debug(selected_circles: selected_circles)

  #   previous_ids =
  #     Enum.map(previous_circles, fn
  #       {_name, id} -> id
  #       _ -> nil
  #     end)

  #   # debug(previous_ids: previous_ids)

  #   public = Bonfire.Boundaries.Circles.circles()[:guest]

  #   # public/guests defaults to also being visible to local users and federating
  #   selected_circles =
  #     if public in selected_circles and public not in previous_ids do
  #       selected_circles ++
  #         [
  #           Bonfire.Boundaries.Circles.circles()[:local],
  #           Bonfire.Boundaries.Circles.circles()[:admin],
  #           Bonfire.Boundaries.Circles.circles()[:activity_pub]
  #         ]
  #     else
  #       selected_circles
  #     end

  #   # debug(new_selected_circles: selected_circles)

  #   existing =
  #     if add_to_previous,
  #       do: previous_circles,
  #       else: known_circle_tuples(selected_circles, previous_circles)

  #   # fix this ugly thing
  #   (existing ++
  #      Enum.map(selected_circles, &Bonfire.Boundaries.Circles.get_tuple/1))
  #   |> Enums.filter_empty([])
  #   |> Enum.uniq()

  #   # |> debug()
  # end

  # def known_circle_tuples(selected_circles, previous_circles) do
  #   Enum.filter(previous_circles, fn
  #     {%{id: id} = circle, _old_role} -> id in selected_circles
  #     {id, _role} -> id in selected_circles
  #     _ -> nil
  #   end)
  # end

  # def set_circles_tuples(field, circles, socket) do
  #   debug(circles, "set roles for #{field}")
  #   debug(e(socket, :assigns, nil), "set roles for #{field}")

  #   previous_value =
  #     e(assigns(socket), field, [])
  #     |> debug("previous_value")

  #   known_circles =
  #     previous_value
  #     |> Enum.map(fn
  #       {%{id: id} = circle, _old_role} ->
  #         {id, circle}

  #       {%{"id" => id} = circle, _old_role} ->
  #         {id, circle}

  #       _ ->
  #         nil
  #     end)
  #     |> debug("known_circles")

  #   circles =
  #     (circles || [])
  #     |> Enum.map(fn
  #       {circle, roles} ->
  #         Enum.map(roles, &{ed(known_circles, id(circle), nil) || circle, &1})
  #     end)
  #     |> List.flatten()
  #     |> debug("computed")

  #   if previous_value != circles do
  #     # WIP: Here on or boundary_items_live.ex we need to fetch the user or circle id to return a map containing the name and optional image to render on the boundary_items_live.sface
  #     maybe_send_update(
  #       Bonfire.UI.Boundaries.CustomizeBoundaryLive,
  #       "customize_boundary_live",
  #       %{field => circles}
  #     )

  #     socket
  #     |> assign(field, circles)

  #     # |> assign_global(
  #     #   _already_live_selected_:
  #     #     Enum.uniq(e(assigns(socket), :__context, :_already_live_selected_, []) ++ [field])
  #     # )
  #   else
  #     socket
  #   end
  # end

  # def set_circles_tuples(field, circles, socket) do
  #   debug(circles, "set roles for #{field}")

  #   previous_value =
  #     e(assigns(socket), field, [])
  #     |> debug("previous_value")

  #   # Create a lookup map of existing circles by ID
  #   known_circles =
  #     previous_value
  #     |> Enum.map(fn
  #       {%{id: id} = circle, _old_role} -> {id, circle}
  #       {%{"id" => id} = circle, _old_role} -> {id, circle}
  #       {circle, _} when is_binary(circle) -> {circle, circle}
  #       circle when is_binary(circle) -> {circle, circle}
  #       _ -> nil
  #     end)
  #     |> Enum.reject(&is_nil/1)
  #     |> Map.new()
  #     |> debug("known_circles")

  #   # Process incoming circle roles (might be partial)
  #   updated_circle_tuples =
  #     (circles || [])
  #     |> Enum.flat_map(fn
  #       {circle_id, roles} when is_list(roles) ->
  #         Enum.map(roles, fn role ->
  #           circle_data = Map.get(known_circles, id(circle_id)) || circle_id
  #           {circle_data, role}
  #         end)

  #       {circle_id, role} ->
  #         circle_data = Map.get(known_circles, id(circle_id)) || circle_id
  #         [{circle_data, role}]
  #     end)
  #     |> debug("updated_circle_tuples")

  #   # Create map of circle_id -> updated role
  #   updated_roles_by_id =
  #     updated_circle_tuples
  #     |> Enum.map(fn {circle, role} -> {id(circle), role} end)
  #     |> Map.new()
  #     |> debug("updated_roles_by_id")

  #   # Update existing circles with new roles where applicable
  #   updated_circles =
  #     previous_value
  #     |> Enum.map(fn {circle, old_role} ->
  #       circle_id = id(circle)

  #       case Map.get(updated_roles_by_id, circle_id) do
  #         # Keep existing role if not in update
  #         nil -> {circle, old_role}
  #         # Update with new role
  #         new_role -> {circle, new_role}
  #       end
  #     end)
  #     |> debug("updated_existing_circles")

  #   # Add any completely new circles not in previous list
  #   existing_ids = Enum.map(updated_circles, fn {circle, _} -> id(circle) end)

  #   new_circles =
  #     updated_circle_tuples
  #     |> Enum.reject(fn {circle, _} -> id(circle) in existing_ids end)
  #     |> debug("completely_new_circles")

  #   # Final merged list preserves all circles
  #   merged_circles =
  #     (updated_circles ++ new_circles)
  #     |> debug("merged_circles")

  #   # Only update if there's a change
  #   if merged_circles != previous_value do
  #     maybe_send_update(
  #       Bonfire.UI.Boundaries.CustomizeBoundaryLive,
  #       "customize_boundary_live",
  #       %{field => merged_circles}
  #     )

  #     socket
  #     |> assign(field, merged_circles)
  #   else
  #     socket
  #   end
  # end

  def set_circles_tuples(field, circles, socket) do
    debug(circles, "set roles for #{field}")

    previous_value =
      e(assigns(socket), field, [])
      |> debug("previous_value")

    # Create a lookup map of existing circles by ID
    known_circles =
      previous_value
      |> Enum.map(fn
        {%{id: id} = circle, _old_role} -> {id, circle}
        {%{"id" => id} = circle, _old_role} -> {id, circle}
        {circle, _} when is_binary(circle) -> {circle, circle}
        circle when is_binary(circle) -> {circle, circle}
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()
      |> debug("known_circles")

    # Process incoming circle roles
    updated_circle_tuples =
      if is_map(circles) do
        # Handle map format from form submission (circle_id => [role])
        Enum.flat_map(circles, fn
          {circle_id, roles_array} when is_list(roles_array) ->
            # Skip _unused_ entries
            if String.starts_with?(circle_id, "_unused_") do
              []
            else
              # Extract role from array - usually just the first element
              role = List.first(roles_array)
              circle_data = Map.get(known_circles, circle_id) || circle_id
              [{circle_data, role}]
            end

          {circle_id, role} ->
            if String.starts_with?(circle_id, "_unused_") do
              []
            else
              circle_data = Map.get(known_circles, circle_id) || circle_id
              [{circle_data, role}]
            end
        end)
      else
        # Handle the case where circles is a list of tuples (legacy format)
        (circles || [])
        |> Enum.flat_map(fn
          {circle_id, roles} when is_list(roles) ->
            Enum.map(roles, fn role ->
              circle_data = Map.get(known_circles, id(circle_id)) || circle_id
              {circle_data, role}
            end)

          {circle_id, role} ->
            circle_data = Map.get(known_circles, id(circle_id)) || circle_id
            [{circle_data, role}]
        end)
      end
      |> debug("updated_circle_tuples")

    # Create map of circle_id -> updated role
    updated_roles_by_id =
      updated_circle_tuples
      |> Enum.map(fn {circle, role} -> {id(circle), role} end)
      |> Map.new()
      |> debug("updated_roles_by_id")

    # Update existing circles with new roles where applicable
    updated_circles =
      previous_value
      |> Enum.map(fn {circle, old_role} ->
        circle_id = id(circle)

        case Map.get(updated_roles_by_id, circle_id) do
          # Keep existing role if not in update
          nil -> {circle, old_role}
          # Update with new role
          new_role -> {circle, new_role}
        end
      end)
      |> debug("updated_existing_circles")

    # Add any completely new circles not in previous list
    existing_ids = Enum.map(updated_circles, fn {circle, _} -> id(circle) end)

    new_circles =
      updated_circle_tuples
      |> Enum.reject(fn {circle, _} -> id(circle) in existing_ids end)
      |> debug("completely_new_circles")

    # Final merged list preserves all circles
    merged_circles =
      (updated_circles ++ new_circles)
      |> debug("merged_circles")

    # Only update if there's a change
    if merged_circles != previous_value do
      maybe_send_update(
        Bonfire.UI.Boundaries.CustomizeBoundaryLive,
        "customize_boundary_live",
        %{field => merged_circles}
      )

      socket
      |> assign(field, merged_circles)
    else
      socket
    end
  end

  # File: /extensions/bonfire_ui_boundaries/lib/web/live_handlers/circles_live_handler.ex

  def remove_from_circle_tuples(ids, previous_circles) do
    # Make sure we have a list and convert all IDs to strings for comparison
    deselected_ids =
      ids
      |> List.wrap()
      |> Enum.map(fn
        %{id: id} -> to_string(id)
        %{"id" => id} -> to_string(id)
        id when is_binary(id) -> to_string(id)
        other -> to_string(other)
      end)
      |> debug("deselected_ids")

    # Only remove circles with matching IDs
    previous_circles
    |> debug("before_removal: #{inspect(deselected_ids)}")
    |> Enum.reject(fn
      {circle, _role} ->
        to_string(id(circle)) in deselected_ids

      circle when is_map(circle) ->
        to_string(id(circle)) in deselected_ids

      circle when is_binary(circle) ->
        to_string(circle) in deselected_ids

      _ ->
        # Don't remove anything we can't identify
        false
    end)
    |> debug("after_removal")
  end

  def my_circles_paginated(scope, attrs \\ nil) do
    Bonfire.Boundaries.Circles.list_my_with_counts(scope,
      exclude_stereotypes: true,
      exclude_built_ins: true,
      paginate?: true,
      paginate: attrs
    )

    # |> repo().maybe_preload(encircles: [subject: [:profile]])
  end

  def maybe_redirect_to(socket, _, %{"no_redirect" => r}) when r != "" do
    socket
  end

  def maybe_redirect_to(socket, path, _attrs) do
    redirect_to(
      socket,
      path
    )
  end
end
