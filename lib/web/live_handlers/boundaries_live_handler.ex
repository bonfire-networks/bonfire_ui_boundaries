defmodule Bonfire.Boundaries.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler
  use Untangle
  # import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Roles
  # alias Bonfire.Boundaries.Grants

  def handle_event(
        "multi_select",
        %{data: %{"id" => id, "username" => username}} = _params,
        socket
      )
      when not is_nil(id) and not is_nil(username) do
    {:noreply, preview(socket, id, username)}
  end

  def preview(socket, id, username) do
    current_user = current_user(socket)

    boundaries =
      Enum.map(
        List.wrap(socket.assigns[:boundary_preset] || socket.assigns[:to_boundaries] || []),
        fn
          {slug, _} -> slug
          slug -> slug
        end
      )

    opts = [
      preview_for_id: id,
      boundary: e(boundaries, "mentions"),
      to_circles: e(assigns(socket), :to_circles, []),
      context_id: e(assigns(socket), :context_id, nil)
      # TODO: also calculate mentions from current draft text to take those into account in boundary calculation
      # mentions: [],
      # reply_to_id: e(assigns(socket), :reply_to_id, nil),
    ]

    with {:ok, verbs} <-
           Bonfire.Boundaries.Acls.preview(current_user, opts)
           |> debug("preview") do
      role = Bonfire.Boundaries.Roles.preset_boundary_role_from_acl(verbs)

      role_name =
        case role do
          {role_name, _permissions} -> role_name
          _ -> nil
        end

      socket
      |> assign(
        role_name: role_name,
        preview_boundary_for_username: username,
        preview_boundary_for_id: id || :guests,
        preview_boundary_verbs: verbs
      )

      # |> push_event("change", "#smart_input")
    end
  end

  def handle_event("set_default_boundary", %{"id" => id, "scope" => scope} = _params, socket) do
    Bonfire.Common.Settings.LiveHandler.handle_event(
      "set",
      %{"ui" => %{"boundary_preset" => id}, "scope" => scope},
      socket
    )
  end

  def handle_event("blocks", %{"id" => id} = attrs, socket)
      when is_binary(id) do
    info(attrs)
    current_user = current_user_required!(socket)
    opts = [current_user: current_user]

    can_instance_wide = Bonfire.Boundaries.can?(assigns(socket)[:__context__], :block, :instance)

    with {:ok, a} <-
           if(attrs["silence"],
             do: Bonfire.Boundaries.Blocks.block(id, :silence, opts),
             else: {:ok, nil}
           ),
         {:ok, b} <-
           if(attrs["ghost"],
             do: Bonfire.Boundaries.Blocks.block(id, :ghost, opts),
             else: {:ok, nil}
           ),
         {:ok, c} <-
           if(can_instance_wide && attrs["instance_wide"]["silence"],
             do: Bonfire.Boundaries.Blocks.block(id, :silence, :instance_wide),
             else: {:ok, nil}
           ),
         {:ok, d} <-
           if(can_instance_wide && attrs["instance_wide"]["ghost"],
             do: Bonfire.Boundaries.Blocks.block(id, :ghost, :instance_wide),
             else: {:ok, nil}
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      {:noreply, assign_flash(socket, :info, Enum.join(filter_empty([a, b, c, d], []), "\n"))}
    end
  end

  def handle_event("block", %{"id" => id, "scope" => scope} = attrs, socket)
      when is_binary(id) do
    # current_user = current_user_required!(socket)

    can_instance_wide = Bonfire.Boundaries.can?(assigns(socket)[:__context__], :block, :instance)

    with {:ok, status} <-
           (if can_instance_wide do
              Bonfire.Boundaries.Blocks.block(
                id,
                maybe_to_atom(attrs["block_type"]),
                maybe_to_atom(scope) || socket
              )
            else
              debug("not admin, fallback to user-level block")

              Bonfire.Boundaries.Blocks.block(
                id,
                maybe_to_atom(attrs["block_type"]),
                socket
              )
            end) do
      Bonfire.UI.Common.OpenModalLive.close()

      {:noreply, assign_flash(socket, :info, status)}
    end
  end

  def handle_event("block", %{"id" => id} = attrs, socket) when is_binary(id) do
    with {:ok, status} <-
           Bonfire.Boundaries.Blocks.block(
             id,
             maybe_to_atom(attrs["block_type"]),
             socket
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      {:noreply, assign_flash(socket, :info, status)}
    end
  end

  def handle_event("unblock", %{"id" => id, "scope" => scope} = attrs, socket)
      when is_binary(id) do
    unblock(id, maybe_to_atom(attrs["block_type"]), scope, socket)
  end

  def handle_event("unblock", %{"id" => id} = attrs, socket)
      when is_binary(id) do
    unblock(id, maybe_to_atom(attrs["block_type"]), assigns(socket)[:scope], socket)
  end

  def handle_event("acl_create", %{"name" => name} = attrs, socket) do
    acl_create(Map.merge(attrs, %{named: %{name: name}}), socket)
  end

  def handle_event("acl_create", attrs, socket) do
    acl_create(attrs, socket)
  end

  def handle_event("acl_validate", attrs, socket) do
    {:noreply, socket}
  end

  def handle_event("open_boundaries", _params, socket) do
    debug("open_boundaries")
    {:noreply, assign(socket, :open_boundaries, true)}
  end

  def handle_event("close_boundaries", _params, socket) do
    debug("close_boundaries")
    {:noreply, assign(socket, :open_boundaries, false)}
  end

  def handle_event("replace_boundary", %{"id" => acl_id} = params, socket) do
    debug(acl_id, "replace_boundary")

    maybe_send_update(
      Bonfire.UI.Boundaries.CustomizeBoundaryLive,
      "customize_boundary_live",
      to_boundaries: [{acl_id, e(params, "name", acl_id)}]
    )

    {:noreply,
     assign(
       socket,
       :to_boundaries,
       [{acl_id, e(params, "name", acl_id)}]
     )}
  end

  def handle_event("select_boundary", %{"id" => acl_id} = params, socket) do
    debug(acl_id, "select_boundary")

    {:noreply,
     assign(
       socket,
       :to_boundaries,
       Bonfire.UI.Boundaries.SetBoundariesLive.set_clean_boundaries(
         e(assigns(socket), :to_boundaries, []),
         acl_id,
         e(params, "name", acl_id)
       )
     )}
  end

  def handle_event("remove_boundary", %{"id" => id} = _params, socket) do
    debug(id, "remove_boundary")

    {:noreply,
     assign(
       socket,
       :to_boundaries,
       e(assigns(socket), :to_boundaries, [])
       |> Keyword.drop([id])
     )}
  end

  # def handle_event("input", %{"circles" => selected_circles} = _attrs, socket) when is_list(selected_circles) and length(selected_circles)>0 do
  #   previous_circles = e(assigns(socket), :to_circles, []) #|> Enum.uniq()
  #   new_circles = set_circles(selected_circles, previous_circles)

  #   {:noreply,
  #       socket
  #       |> assign_global(
  #         to_circles: new_circles
  #       )
  #   }
  # end

  # def handle_event("input", _attrs, socket) do # no circle
  #   {:noreply,
  #     socket
  #       |> assign_global(
  #         to_circles: []
  #       )
  #   }
  # end

  def handle_event(action, %{"id" => selected} = _attrs, socket)
      when action in ["select", "select_circle"] and is_binary(selected) do
    {:noreply,
     Bonfire.Boundaries.Circles.LiveHandler.set_circles_tuples(:to_circles, [selected], socket)}

    #
    #  assign(socket,
    #    to_circles: set_circles([selected], e(assigns(socket), :to_circles, []), true)
    #  )
  end

  def handle_event(
        "multi_select",
        %{data: data, text: _text},
        socket
      ) do
    # debug(data, text)

    field =
      maybe_to_atom(e(data, "field", :to_boundaries))
      |> debug("field")

    appended_data =
      case field do
        :to_boundaries ->
          # [{"public", l("Public")}]
          []
          |> (e(assigns(socket), field, ...) ++
                [{id(data), data}])

        :to_circles ->
          e(assigns(socket), field, []) ++
            [{data, nil}]

        :exclude_circles ->
          e(assigns(socket), field, []) ++
            [{data, nil}]

        _ ->
          e(assigns(socket), field, []) ++
            [{data, id(data)}]
      end
      |> debug("list")
      |> Enum.uniq()
      |> debug("uniq")

    maybe_send_update(
      Bonfire.UI.Boundaries.CustomizeBoundaryLive,
      "customize_boundary_live",
      %{field => appended_data}
    )

    {:noreply,
     socket
     |> assign(
       field,
       appended_data
     )
     |> assign_global(
       _already_live_selected_:
         Enum.uniq(e(assigns(socket), :__context, :_already_live_selected_, []) ++ [field])
     )}
  end

  def handle_event(
        "select",
        %{"to_circles" => to_circles, "exclude_circles" => exclude_circles} = _params,
        socket
      ) do
    {:noreply,
     socket
     |> Bonfire.Boundaries.Circles.LiveHandler.set_circles_tuples(:to_circles, to_circles, ...)
     |> Bonfire.Boundaries.Circles.LiveHandler.set_circles_tuples(
       :exclude_circles,
       exclude_circles,
       ...
     )}
  end

  def handle_event("multi_select", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("select", %{"to_circles" => circles} = _params, socket) do
    {:noreply,
     socket
     |> Bonfire.Boundaries.Circles.LiveHandler.set_circles_tuples(:to_circles, circles, ...)}
  end

  def handle_event("select", %{"exclude_circles" => circles} = _params, socket) do
    {:noreply,
     socket
     |> Bonfire.Boundaries.Circles.LiveHandler.set_circles_tuples(:exclude_circles, circles, ...)}
  end

  def handle_event("select", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(action, %{"id" => deselected} = attrs, socket)
      when action in ["deselect", "remove_circle"] and is_binary(deselected) do
    field = e(attrs, "field", nil) |> Types.maybe_to_atom() || :to_circles

    maybe_send_update(
      Bonfire.UI.Boundaries.CustomizeBoundaryLive,
      "customize_boundary_live",
      %{
        field =>
          Bonfire.Boundaries.Circles.LiveHandler.remove_from_circle_tuples(
            [deselected],
            e(assigns(socket), field, [])
          )
      }
    )

    {:noreply,
     assign(
       socket,
       field,
       Bonfire.Boundaries.Circles.LiveHandler.remove_from_circle_tuples(
         [deselected],
         e(assigns(socket), field, [])
       )
     )}
  end

  def handle_event("load_more", attrs, socket) do
    scope = scope_origin(socket)

    %{page_info: page_info, edges: edges} =
      Bonfire.Boundaries.Circles.LiveHandler.my_circles_paginated(scope, input_to_atoms(attrs))

    {:noreply,
     socket
     |> assign(
       loaded: true,
       circles: e(assigns(socket), :circles, []) ++ edges,
       page_info: page_info
     )}
  end

  # TODO
  # def handle_event("circle_soft_delete", _, socket) do
  #   id = uid!(e(assigns(socket), :circle, nil))

  #   with {:ok, _circle} <-
  #          Circles.soft_delete(id, current_user_required!(socket)) |> debug() do
  #     {:noreply,
  #      socket
  #      |> assign_flash(:info, l("Archived"))
  #      |> redirect_to("/boundaries/circles")}
  #   end
  # end

  def handle_event("edit_acl", attrs, socket) do
    debug(attrs)

    with {:ok, acl} <-
           Acls.edit(e(assigns(socket), :acl, nil), current_user_required!(socket), attrs) do
      send_self(page_title: e(acl, :named, :name, nil))

      {:noreply,
       socket
       |> assign_flash(:info, l("Edited!"))
       |> assign(show: false)
       |> assign(acl: acl)}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not edit boundary"))}
    end
  end

  def handle_event("acl_soft_delete", _, socket) do
    id = uid!(e(assigns(socket), :acl, nil))

    with {:ok, _} <-
           Acls.soft_delete(id, current_user_required!(socket)) |> debug() do
      {:noreply,
       socket
       |> assign_flash(:info, l("Archived"))
       |> redirect_to("/boundaries/acls")}
    end
  end

  def handle_event("acl_delete", _, socket) do
    id = uid!(e(assigns(socket), :acl, nil))

    with {:ok, _} <-
           Acls.delete(id, current_user_required!(socket)) |> debug() do
      {:noreply,
       socket
       |> assign_flash(:info, l("Deleted"))
       |> redirect_to("/boundaries/acls")}
    end
  end

  def handle_event("role_create", %{"name" => name} = attrs, socket) do
    debug(attrs, "TETETETETe")
    current_user = current_user_required!(socket)

    scope =
      case e(assigns(socket), :scope, nil) do
        nil -> nil
        scope -> scope
      end

    debug(scope, "scope")

    with {:ok, _} <-
           Roles.create(
             input_to_atoms(attrs),
             scope: scope,
             current_user: current_user
           ) do
      # Bonfire.UI.Common.OpenModalLive.close()

      {:noreply,
       socket
       |> assign_flash(:info, "Role created!")
       |> redirect_to(current_url(socket))}
    end
  end

  def handle_event("role_edit_details", attrs, socket) do
    current_user = current_user_required!(socket)

    scope =
      case e(assigns(socket), :scope, nil) do
        nil -> nil
        scope -> scope
      end

    with {:ok, _} <-
           Roles.edit_details(
             e(attrs, "old_name", nil),
             e(attrs, "new_name", nil),
             e(attrs, "usage", nil),
             scope: scope,
             current_user: current_user
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      {:noreply,
       socket
       |> assign_flash(:info, "Role edited!")
       |> redirect_to(current_url(socket))}
    end
  end

  def handle_event("role_delete", attrs, socket) do
    current_user = current_user_required!(socket)

    scope =
      case e(assigns(socket), :scope, nil) do
        nil -> nil
        scope -> scope
      end

    with {:ok, _} <-
           Roles.delete(
             e(attrs, "name", nil),
             scope: scope,
             current_user: current_user
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      {:noreply,
       socket
       |> assign_flash(:info, "Role deleted.")
       |> redirect_to(current_url(socket))}
    end
  end

  def handle_event(
        "custom_from_preset_template",
        %{"boundary" => boundary, "name" => name} = _params,
        socket
      ) do
    {to_circles, exclude_circles} =
      Acls.grant_tuples_from_preset(current_user_required!(socket), boundary)
      |> Roles.split_tuples_can_cannot()
      |> debug("custom_from_preset_template")

    {:noreply,
     socket
     |> assign(
       to_circles: to_circles,
       exclude_circles: exclude_circles,
       to_boundaries: [{"custom", "#{name}*"}]
     )}
  end

  def handle_event(
        "remove_object_acl",
        %{"object_id" => object, "acl_id" => acl} = _params,
        socket
      ) do
    with {1, nil} <-
           Bonfire.Boundaries.Controlleds.remove_acls(
             object,
             acl
           )
           |> debug("removed?") do
      Bonfire.UI.Common.OpenModalLive.close()

      {
        :noreply,
        socket
        |> assign_flash(:info, l("Boundary removed!"))
        #  |> assign(
        #  )
      }
    else
      e ->
        error(e)
    end
  end

  def handle_event("add_object_acl", %{"id" => acl, "object_id" => object}, socket) do
    with {:ok, _} <-
           Bonfire.Boundaries.Controlleds.add_acls(
             object,
             acl
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      {
        :noreply,
        socket
        |> assign_flash(:info, l("Boundary added!"))
        #  |> assign(
        #  )
      }
    else
      e ->
        error(e)
    end
  end

  def unblock(id, block_type, scope, socket)
      when is_binary(id) do
    # current_user = current_user_required!(socket)

    can_instance_wide = Bonfire.Boundaries.can?(assigns(socket)[:__context__], :block, :instance)

    with {:ok, status} <-
           (if can_instance_wide do
              Bonfire.Boundaries.Blocks.unblock(
                id,
                block_type,
                maybe_to_atom(scope) || socket
              )
            else
              debug("not admin, fallback to user-level block")

              Bonfire.Boundaries.Blocks.unblock(
                id,
                block_type,
                socket
              )
            end) do
      {:noreply, assign_flash(socket, :info, status)}
    end
  end

  def acl_create(attrs, socket) do
    current_user = current_user_required!(socket)
    scope = maybe_to_atom(e(attrs, :scope, nil))

    with {:ok, %{id: id} = acl} <-
           Acls.create(attrs,
             current_user: scope || current_user
           ) do
      # Bonfire.UI.Common.OpenModalLive.close()

      {:noreply,
       socket
       |> assign(
         acls: [acl] ++ e(assigns(socket), :acls, []),
         edit_acl_id: id,
         section: nil
       )
       |> assign_flash(:info, l("Boundary created!"))
       |> maybe_redirect_to(
         if(is_atom(scope) && not is_nil(scope),
           do: ~p"/boundaries/scope/instance/acl/" <> id,
           else: ~p"/boundaries/acl/" <> id
         ),
         attrs
       )}
    end
  end

  # @decorate time()
  def maybe_check_boundaries(assigns_sockets, opts \\ []) do
    current_user =
      current_user(elem(List.first(assigns_sockets), 0)) ||
        current_user(elem(List.first(assigns_sockets), 1))

    # |> debug("current_user")

    list_of_objects =
      assigns_sockets
      # |> debug("assigns_sockets")
      # only check when explicitly asked
      |> Enum.reject(&(e(&1, :check_object_boundary, nil) != true))
      |> Enum.map(&the_object/1)

    # |> debug("list_of_objects")

    list_of_ids =
      list_of_objects
      |> Enum.map(&Acls.acl_id/1)
      |> Enum.uniq()
      |> filter_empty(nil)

    if list_of_ids do
      debug(list_of_ids, "list_of_ids (check via #{opts[:caller_module]})")

      my_visible_ids =
        if current_user,
          do:
            Bonfire.Boundaries.load_pointers(list_of_ids,
              current_user: current_user,
              verbs: e(opts, :verbs, [:read]),
              ids_only: true
            )
            |> Enums.ids(),
          else: []

      debug(my_visible_ids, "my_visible_ids")

      Enum.map(assigns_sockets, fn {assigns, socket} ->
        object_id = uid(the_object(assigns))

        {if object_id in list_of_ids and object_id not in my_visible_ids do
           # not allowed
           assigns
           |> Map.put(
             :activity,
             nil
           )
           |> Map.put(
             :object,
             nil
           )
           |> Map.put(
             :object_boundary,
             :not_visible
           )
         else
           # allowed
           assigns
           |> Map.put(
             :boundary_can,
             true
           )
           # to avoid checking again
           |> Map.put(
             :check_object_boundary,
             false
           )
         end, socket}
      end)
    else
      debug("skip")
      assigns_sockets
    end
  end

  # @decorate time()
  def update_many(assigns_sockets, opts \\ []) do
    {first_assigns, _socket} = List.first(assigns_sockets)

    update_many_async(
      assigns_sockets,
      update_many_opts(
        opts ++
          [
            id:
              e(first_assigns, :feed_name, nil) || e(first_assigns, :feed_id, nil) ||
                e(first_assigns, :thread_id, nil) || id(first_assigns)
          ]
      )
    )
  end

  def update_many_opts(opts \\ []) do
    opts ++
      [
        skip_if_set: :object_boundary,
        preload_status_key: :preloaded_async_boundaries,
        assigns_to_params_fn: &assigns_to_params/1,
        preload_fn: &do_preload_many/3
      ]
  end

  defp assigns_to_params(assigns) do
    object = the_object(assigns)

    %{
      component_id: assigns.id,
      object: object || e(assigns, :object_id, nil),
      object_id: e(assigns, :object_id, nil) || uid(object),
      previous_value: e(assigns, :object_boundary, nil)
    }
  end

  @decorate time()
  defp do_preload_many(list_of_components, list_of_ids, current_user) do
    my_states =
      if is_list(list_of_ids) and list_of_ids != [],
        do: Boundaries.boundaries_on_objects(list_of_ids, current_user),
        else: %{}

    debug(my_states, "boundaries_on_objects!")

    list_of_components
    |> Map.new(fn component ->
      {component.component_id,
       %{
         object_boundary:
           Map.get(my_states, component.object_id) || component.previous_value || false
       }}
    end)
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

  def subject_name(subject) do
    e(subject, :named, :name, nil) ||
      e(subject, :stereotyped, :named, :name, nil) ||
      e(subject, :profile, :name, nil) || e(subject, :character, :username, nil) ||
      e(subject, :name, nil) || uid(subject)
  end

  def scope_origin(assigns \\ nil, socket) do
    context = e(assigns, :__context__, nil) || assigns(socket)[:__context__]
    current_user = current_user(context)
    scope = e(assigns, :scope, nil) || e(assigns(socket), :scope, nil)

    if scope == :instance and
         Bonfire.Boundaries.can?(context, :assign, :instance),
       do: Bonfire.Boundaries.Scaffold.Instance.admin_circle(),
       else: current_user
  end

  def prepare_assigns({reply, socket}) do
    {reply, socket |> prepare_assigns()}
  end

  def prepare_assigns(socket) do
    current_user = current_user(socket)
    my_acls = e(assigns(socket)[:__context__], :my_acls, nil) || my_acls(id(current_user))

    to_boundaries =
      e(assigns(socket), :to_boundaries, nil)
      |> debug("existing")
      |> Bonfire.Boundaries.boundaries_or_default(current_user: current_user, my_acls: my_acls)
      |> debug()

    socket
    |> assign_global(
      :my_acls,
      my_acls
    )
    |> assign(
      to_boundaries: to_boundaries,
      boundary_preset: Bonfire.UI.Boundaries.SetBoundariesLive.boundaries_to_preset(to_boundaries)
    )
  end

  def my_acls(current_user_id, opts \\ nil) do
    Bonfire.Boundaries.Acls.list_my(
      current_user_id,
      opts || Bonfire.Boundaries.Acls.opts_for_list()
    )
    |> Enum.map(fn
      %Bonfire.Data.AccessControl.Acl{id: acl_id} = acl ->
        {acl_id, acl_meta(acl)}
    end)
    |> Enum.reject(fn
      {_, %{name: nil}} -> true
      _ -> false
    end)

    # |> debug("myacccl")
  end

  defp acl_meta(%{id: acl_id, stereotyped: %{stereotype_id: "1HANDP1CKEDZEPE0P1E1F0110W"}} = acl) do
    %{
      id: acl_id,
      field: :to_boundaries,
      description: e(acl, :stereotyped, :named, :name, nil),
      name: l("Follows"),
      icon: "ph:circle-duotone"
    }
  end

  defp acl_meta(%{id: acl_id} = acl) do
    %{
      id: acl_id,
      field: :to_boundaries,
      description: e(acl, :extra_info, :summary, nil),
      name: e(acl, :named, :name, nil) || e(acl, :stereotyped, :named, :name, nil)
    }
  end
end
