defmodule Bonfire.UI.Boundaries.RolesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Roles

  prop scope, :any, default: nil
  prop read_only, :boolean, default: false
  prop load_roles, :boolean, default: true

  # Semantic groupings for verbs - used by role cards for progressive disclosure
  @verb_groups [
    visibility: %{
      name: l("Visibility"),
      icon: "ph:eyes-duotone",
      description: l("Who can discover and view content"),
      verbs: [:see, :read, :request]
    },
    participation: %{
      name: l("Participation"),
      icon: "ph:chat-circle-duotone",
      description: l("Interacting with and creating content"),
      verbs: [
        :like,
        :boost,
        :bookmark,
        :follow,
        :reply,
        :quote,
        :mention,
        :message,
        :create,
        :edit,
        :delete,
        :tag,
        :pin,
        :schedule,
        :vote
      ]
    },
    moderation: %{
      name: l("Moderation"),
      icon: "ph:shield-check-duotone",
      description: l("Reporting and content moderation"),
      verbs: [:flag, :label, :annotate, :mediate, :block]
    },
    administration: %{
      name: l("Administration"),
      icon: "ph:gear-duotone",
      description: l("System configuration and access control"),
      verbs: [:toggle, :describe, :grant, :assign, :invite, :configure]
    }
  ]

  def verb_groups, do: @verb_groups

  def update(assigns, socket) do
    current_user =
      current_user(assigns) || current_user(socket)

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
                  {Bonfire.UI.Boundaries.NewRoleButtonLive,
                   [scope: scope, scope_type: scope_type, setting_boundaries: false]}
              )
            ]
          )

      # else
      #   send_self(
      #   scope: scope,
      #   scope_type: scope_type,
      # )
    end

    # Load roles with verbs using the same pattern as TabledRolesLive
    roles_with_verbs =
      Bonfire.Boundaries.Roles.role_verbs(:all,
        current_user: current_user,
        one_scope_only: true,
        scope: scope
      )
      |> Bonfire.UI.Boundaries.TabledRolesLive.get_roles_with_verbs(
        current_user: current_user,
        one_scope_only: true,
        scope: scope
      )
      |> debug("roles_with_verbs_for_cards")

    # Split into built-in (read_only) and custom roles
    {builtin_roles, custom_roles} =
      Enum.split_with(roles_with_verbs, fn {role_name, _verbs} ->
        role_config = Roles.get(role_name, scope: scope, current_user: current_user)
        e(role_config, :read_only, false)
      end)

    {
      :ok,
      socket
      |> assign(assigns)
      |> assign(
        scope_type: scope_type,
        scope: scope,
        read_only: e(assigns, :read_only, false),
        verb_groups: @verb_groups,
        roles_with_verbs: roles_with_verbs,
        builtin_roles: builtin_roles,
        custom_roles: custom_roles,
        builtin_roles_count: length(builtin_roles),
        all_verbs: Bonfire.UI.Boundaries.TabledRolesLive.verb_order()
      )
      #  |> debug()
    }
  end

  @doc "Count permissions with explicit :can or :cannot status"
  def defined_count(role_verbs) do
    Enum.count(role_verbs || [], fn {_verb, status} -> status in [:can, :cannot] end)
  end

  @doc "Generate summary string for a role"
  def permission_summary(role_verbs) do
    case defined_count(role_verbs) do
      0 -> l("No permissions defined")
      1 -> l("1 permission defined")
      n -> l("%{count} permissions defined", count: n)
    end
  end

  @doc "Prepare verb data with metadata from Verbs module"
  def verb_with_meta({verb, status}) do
    meta = Bonfire.Boundaries.Verbs.get(verb) || %{}

    %{
      verb: verb,
      status: status,
      icon: meta[:icon] || "ph:circle-duotone",
      display_name: meta[:verb] || Recase.to_title(to_string(verb))
    }
  end
end
