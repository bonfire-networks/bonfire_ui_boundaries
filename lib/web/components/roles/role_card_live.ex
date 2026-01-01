defmodule Bonfire.UI.Boundaries.RoleCardLive do
  @moduledoc """
  An expandable card displaying a role with its permissions grouped by semantic category.
  Handles permission editing via the edit_verb_value event.
  """
  use Bonfire.UI.Common.Web, :stateful_component

  alias Bonfire.Boundaries.Roles
  alias Bonfire.UI.Boundaries.RolesLive

  prop role_name, :any, required: true
  prop role_verbs, :list, default: []
  prop read_only, :boolean, default: false
  prop scope, :any, default: nil
  prop verb_groups, :list, required: true
  prop event_target, :any, default: nil

  data grouped_verbs, :list, default: []
  data defined_verbs, :list, default: []

  def update(assigns, socket) do
    role_verbs = assigns[:role_verbs] || []
    verb_groups = assigns[:verb_groups] || []

    grouped = group_verbs_by_category(role_verbs, verb_groups)

    # For read-only roles, prepare flat list of only defined verbs
    defined_verbs =
      if assigns[:read_only] do
        role_verbs
        |> Enum.filter(fn {_verb, status} -> status in [:can, :cannot] end)
        |> Enum.map(&RolesLive.verb_with_meta/1)
        |> Enum.sort_by(&(&1.status != :can))
      else
        []
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(grouped_verbs: grouped, defined_verbs: defined_verbs)}
  end

  defp group_verbs_by_category(role_verbs, verb_groups) do
    role_verbs_map = Map.new(role_verbs)

    Enum.map(verb_groups, fn {category_key, category} ->
      category_verbs =
        (category[:verbs] || [])
        |> Enum.map(fn verb -> {verb, Map.get(role_verbs_map, verb)} end)

      {category_key, Map.put(category, :role_verbs, category_verbs)}
    end)
  end

  # Delegate to parent for DRY
  defdelegate permission_summary(role_verbs), to: RolesLive

  # Handle permission toggle
  def handle_event(
        "edit_verb_value",
        %{"role" => role, "verb" => verb, "status" => value} = attrs,
        socket
      ) do
    debug(attrs, "edit_verb_value in RoleCardLive")

    current_user = current_user_required!(socket)
    scope = e(assigns(socket), :scope, nil)

    role = Bonfire.Common.Types.maybe_to_atom(role)
    verb = Bonfire.Common.Types.maybe_to_atom(verb)

    case Roles.edit_verb_permission(role, verb, value,
           scope: scope,
           current_user: current_user
         ) do
      {:ok, edited} ->
        debug(edited, "permission edited successfully")
        current_user = current_user(edited)

        # Reload the role verbs for this role
        updated_role_verbs =
          case Roles.verbs_for_role(role,
                 scope: scope,
                 current_user: current_user
               ) do
            {:ok, can_verbs, cannot_verbs} ->
              verb_order = Bonfire.UI.Boundaries.TabledRolesLive.verb_order()

              Enum.map(verb_order, fn v ->
                cond do
                  v in can_verbs -> {v, :can}
                  v in cannot_verbs -> {v, :cannot}
                  true -> {v, nil}
                end
              end)

            _ ->
              socket.assigns[:role_verbs] || []
          end

        grouped =
          group_verbs_by_category(
            updated_role_verbs,
            socket.assigns[:verb_groups] || []
          )

        {
          :noreply,
          socket
          |> assign_flash(:info, l("Permission updated!"))
          |> assign(
            role_verbs: updated_role_verbs,
            grouped_verbs: grouped
          )
        }

      error ->
        error(error, "Could not edit permission")
        {:noreply, assign_error(socket, l("Could not edit permission"))}
    end
  end
end
