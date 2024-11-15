defmodule Bonfire.UI.Boundaries.Web.TabledRolesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Roles

  prop scope, :any, default: nil
  prop read_only, :boolean, default: false

  #  FIXME: this should be in config where the verbs are defined
  @verb_order [
    :see,
    :read,
    :request,
    :like,
    :boost,
    :flag,
    :reply,
    :mention,
    :message,
    :tag,
    :label,
    :follow,
    :schedule,
    :pin,
    :create,
    :edit,
    :delete,
    :vote,
    :toggle,
    :describe,
    :grant,
    :assign,
    :invite,
    :mediate,
    :block,
    :configure
  ]

  def update(assigns, socket) do
    scope =
      (e(assigns, :scope, nil) || e(assigns(socket), :scope, nil))
      |> debug("role_scope")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       scope: scope,
       verb_order: verb_order(),
       roles_with_verbs:
         get_roles_with_verbs(scope, current_user(socket)) |> debug("roles_with_verbs")
     )}
  end

  def verb_order, do: @verb_order

  @doc """
  Sorts a list of verbs according to the predefined @verb_order.
  """
  def sort_verbs(can_verbs, cannot_verbs) do
    @verb_order
    |> Enum.map(fn verb ->
      cond do
        verb in can_verbs -> {verb, :can}
        verb in cannot_verbs -> {verb, :cannot}
        true -> {verb, nil}
      end
    end)
  end

  @doc """
  Retrieves all roles and their associated verbs (both can_verbs and cannot_verbs),
  sorted according to @verb_order.
  Returns a list of tuples: [{role, verbs_with_statuses}].
  """
  def get_roles_with_verbs(scope, current_user) do
    Bonfire.Boundaries.Roles.role_verbs(:all,
      one_scope_only: true,
      scope: scope,
      current_user: current_user
    )
    |> Enum.map(fn
      {role_name, role_data} when is_map(role_data) ->
        can_verbs = Map.get(role_data, :can_verbs, [])
        cannot_verbs = Map.get(role_data, :cannot_verbs, [])
        sorted_verbs = sort_verbs(can_verbs, cannot_verbs)
        {role_name, sorted_verbs}

      {nil, _} ->
        nil

      {role_name, _} ->
        {role_name, []}
    end)
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
        )
      }
    else
      other ->
        error(other)

        {:noreply, assign_error(socket, l("Could not edit permission"))}
    end
  end

  defp maybe_assign_settings(socket, %{__context__: assigns}) do
    socket
    |> assign_global(assigns)
  end

  # defp maybe_assign_settings(socket, %{id: "3SERSFR0MY0VR10CA11NSTANCE", data: settings}) do
  #   debug(settings, "assign updated instance settings")

  #   socket
  #   |> assign_global(instance_settings: settings)
  # end

  defp maybe_assign_settings(socket, %{id: _, data: data} = _scope) do
    socket
    |> assign(role_verbs: data[:bonfire][:role_verbs])
  end

  defp maybe_assign_settings(socket, ret) do
    debug(ret, "cannot assign updated data with settings")
    socket
  end
end
