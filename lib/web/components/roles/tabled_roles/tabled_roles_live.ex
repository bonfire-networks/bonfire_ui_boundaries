defmodule Bonfire.UI.Boundaries.TabledRolesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Roles

  prop scope, :any, default: nil
  prop read_only, :boolean, default: false
  prop selectable, :boolean, default: false
  prop role, :any, default: nil
  prop field, :atom, default: :to_circles
  prop circle_id, :string, default: nil
  prop roles, :map, default: nil
  prop event_target, :any, default: nil

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

    roles_with_verbs =
      e(
        assigns,
        :roles,
        Bonfire.Boundaries.Roles.role_verbs(:all,
          one_scope_only: true,
          scope: scope,
          current_user: current_user(socket)
        )
      )
      |> get_roles_with_verbs(scope)
      |> debug("roles_with_verbs")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       scope: scope,
       verb_order: verb_order(),
       roles_with_verbs: roles_with_verbs
     )}
  end

  def verb_order, do: @verb_order

  @doc """
  Sorts a list of verbs according to the predefined @verb_order.
  """
  def sort_verbs(can_verbs, cannot_verbs) do
    verb_order()
    |> Enum.map(fn verb ->
      cond do
        verb in can_verbs -> {verb, :can}
        verb in cannot_verbs -> {verb, :cannot}
        true -> {verb, nil}
      end
    end)
  end

  def default_sorted_verbs() do
    verb_order()
    |> Enum.map(fn verb ->
      {verb, nil}
    end)
  end

  @doc """
  Retrieves all roles and their associated verbs (both can_verbs and cannot_verbs),
  sorted according to @verb_order.
  Returns a list of tuples: [{role, verbs_with_statuses}].
  """
  def get_roles_with_verbs(roles, scope) do
    roles
    |> Enum.map(fn
      {role_name, role_data} when is_map(role_data) ->
        can_verbs = Map.get(role_data, :can_verbs, [])
        cannot_verbs = Map.get(role_data, :cannot_verbs, [])
        {role_name, sort_verbs(can_verbs, cannot_verbs)}

      {role_name, _} ->
        {role_name, nil}

      other ->
        warn(other, "unexpected data")
        nil
    end)
  end

  def handle_event(
        "edit_verb_value",
        %{"role" => role, "verb" => verb, "status" => value} = attrs,
        socket
      ) do
    debug(attrs)

    current_user = current_user_required!(socket)
    scope = e(assigns(socket), :scope, nil)

    role = Bonfire.Common.Types.maybe_to_atom(role)
    verb = Bonfire.Common.Types.maybe_to_atom(verb)
    debug(scope, "edit #{role} -- #{verb} = #{value} - scope:")

    case Roles.edit_verb_permission(role, verb, value,
           scope: scope,
           current_user: current_user
         ) do
      {:ok, edited} ->
        debug(edited, "edited")

        {
          :noreply,
          socket
          |> assign_flash(:info, l("Permission edited!"))
          |> maybe_assign_settings(edited)
          |> assign(
            :roles_with_verbs,
            Bonfire.Boundaries.Roles.role_verbs(:all,
              one_scope_only: assigns(socket)[:scope_type] not in [:smart_input],
              scope: scope,
              current_user: current_user(edited)
            )
            |> get_roles_with_verbs(scope)
          )
        }

      error ->
        error(error)
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
  #  end

  defp maybe_assign_settings(socket, %{id: _, data: data} = _scope) do
    socket
    |> assign(roles: data[:bonfire][:role_verbs])
  end

  defp maybe_assign_settings(socket, ret) do
    debug(ret, "cannot assign updated data with settings")
    socket
  end
end
