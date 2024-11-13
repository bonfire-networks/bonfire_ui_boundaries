defmodule Bonfire.UI.Boundaries.Web.RolesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Roles

  prop scope, :any, default: nil
  prop read_only, :boolean, default: false
  prop load_roles, :boolean, default: true

  def update(assigns, socket) do
    current_user =
      current_user(assigns) || current_user(assigns(socket))

    # params = e(assigns, :__context__, :current_params, %{})

    scope =
      (e(assigns, :scope, nil) || e(assigns(socket), :scope, nil))
      |> debug("role_scope")

    scope_type = Types.object_type(scope) || scope

    if scope_type not in [:smart_input, :group, Bonfire.Classify.Category] do
      # not for groups
      if socket_connected?(socket),
        do:
          send_self(
            scope: scope,
            scope_type: scope_type,
            page_title: e(assigns(socket), :name, nil) || l("Roles"),
            back: true,
            page_header_aside: [
              if(!assigns[:read_only],
                do:
                  {Bonfire.UI.Boundaries.Web.NewRoleButtonLive,
                   [scope: scope, scope_type: scope_type]}
              )
            ]
          )

      # else
      #   send_self(
      #   scope: scope,
      #   scope_type: scope_type,
      # )
    end

    available_verbs = Bonfire.Boundaries.Verbs.list(:code, :id)
    # |> debug("available_verbs")

    # available_verbs =
    #   if scope != :instance do
    #     instance_verbs =
    #       Bonfire.Boundaries.Verbs.list(:instance, :id)
    #       |> debug()

    #     available_verbs
    #     |> Enum.reject(&(elem(&1, 0) in instance_verbs))
    #   else
    #     available_verbs
    #   end
    #   |> debug()

    {
      :ok,
      socket
      |> assign(assigns)
      |> assign(
        scope_type: scope_type,
        scope: scope,
        role_verbs:
          Bonfire.Boundaries.Roles.role_verbs(:all,
            one_scope_only: scope_type not in [:smart_input],
            scope: scope,
            current_user: current_user
          )
          |> debug("role_verbsssss"),
        #  cannot_role_verbs: Bonfire.Boundaries.Roles.cannot_role_verbs(),
        all_verbs: Bonfire.Boundaries.Verbs.verbs(),
        available_verbs: available_verbs
      )
      #  |> debug()
    }
  end

  def handle_event("edit_verb_value", %{"role" => roles} = attrs, socket) do
    debug(attrs)

    current_user = current_user_required!(socket)
    scope = e(assigns(socket), :scope, nil)
    # verb_value = List.first(Map.values(roles))

    with [ok: edited] <-
           Enum.flat_map(roles, fn {role_name, verb_value} ->
             Enum.flat_map(verb_value, fn {verb, value} ->
               case Types.maybe_to_atom!(verb) do
                 nil ->
                   [{:error, "Invalid verb"}]

                 verb ->
                   debug(scope, "edit #{role_name} -- #{verb} = #{value} - scope:")

                   [
                     Roles.edit_verb_permission(role_name, verb, value,
                       scope: scope,
                       current_user: current_user
                     )
                   ]
               end
             end)
           end) do
      debug(edited, "settings with edited role")

      {
        :noreply,
        socket
        |> assign_flash(:info, l("Permission edited!"))
        |> maybe_assign_settings(edited)
        |> assign(
          :role_verbs,
          Bonfire.Boundaries.Roles.role_verbs(:all,
            one_scope_only: assigns(socket)[:scope_type] not in [:smart_input],
            scope: scope,
            current_user: current_user(edited)
          )
          |> debug("updated role_verbsssss")
        )
      }
    else
      other ->
        error(other)

        {:noreply, assign_error(socket, l("Could not edit permission"))}
    end
  end

  defp maybe_assign_settings(socket, %{__context__: assigns}) do
    debug(assigns, "assign updated data with settings")

    socket
    |> assign_global(assigns)
  end

  # defp maybe_assign_settings(socket, %{id: "3SERSFR0MY0VR10CA11NSTANCE", data: settings}) do
  #   debug(settings, "assign updated instance settings")

  #   socket
  #   |> assign_global(instance_settings: settings)
  # end

  defp maybe_assign_settings(socket, %{id: _, data: data} = _scope) do
    debug(data, "assign updated role_verbs")

    socket
    |> assign(role_verbs: data[:bonfire][:role_verbs])
  end

  defp maybe_assign_settings(socket, ret) do
    debug(ret, "cannot assign updated data with settings")
    socket
  end
end
