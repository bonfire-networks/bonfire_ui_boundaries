defmodule Bonfire.UI.Boundaries.SetBoundariesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  use Bonfire.Common.Utils
  alias Bonfire.UI.Boundaries.VerbPermissionsHelper

  # declare_module_optional(l("Custom boundaries in composer"),
  #   description:
  #     l(
  #       "Enable selecting custom roles for specific circles or users in the composer when drafting a post. "
  #     )
  # )

  # prop create_object_type, :any, default: nil
  prop to_boundaries, :any, default: nil
  prop to_circles, :list, default: []
  prop exclude_circles, :list, default: []
  prop verb_permissions, :map, default: %{}
  prop parent_id, :string, default: nil
  prop setting_boundaries, :atom, default: nil
  prop show_general_boundary, :boolean, default: false
  prop selected_users, :list, default: []
  prop my_circles, :list, default: nil

  # Verb filtering options (computed by parent)
  prop available_verbs, :list, default: []
  prop preset_boundary, :any, default: nil

  # prop showing_within, :atom, default: nil

  prop open_boundaries, :boolean, default: false
  # prop hide_breakdown, :boolean, default: false
  # prop click_override, :boolean, default: false
  prop is_caretaker, :boolean, default: true

  @presets ["public", "local", "mentions", "custom"]
  def presets, do: @presets

  @doc """
  Get the value for a specific verb-circle combination from verb_permissions.
  This is called on-demand from the template.
  """
  def get_verb_value_for_display(verb_permissions, verb_slug, circle_id) do
    get_in(verb_permissions, [to_string(verb_slug), circle_id])
  end

  def reject_presets(to_boundaries)
      when is_list(to_boundaries) and to_boundaries != [] and to_boundaries != [nil],
      do: Keyword.drop(to_boundaries, presets())

  def reject_presets(_), do: []

  def boundaries_to_preset(to_boundaries) do
    List.wrap(to_boundaries)
    |> Enum.filter(fn
      {x, _} when x in @presets -> true
      x when x in @presets -> true
      _ -> false
    end)
    |> List.first()
  end

  # def set_clean_boundaries(to_boundaries, "custom", _name) do
  #   Keyword.drop(to_boundaries, ["public", "local", "mentions"])
  # end

  def get_preset_circles_info({preset_key, _name}), do: get_preset_circles_info(preset_key)

  def get_preset_circles_info(boundary_preset) when is_binary(boundary_preset) do
    # Get ACL names for this preset
    acl_names = Bonfire.Boundaries.acls_from_preset_boundary_names(boundary_preset)

    # Get grants for each ACL from configuration and return as tuples for BoundaryItemsLive
    acl_names
    |> Enum.flat_map(fn acl_name ->
      case Bonfire.Boundaries.Grants.get(acl_name) do
        grants when is_map(grants) ->
          Enum.map(grants, fn {circle_slug, role_or_verbs} ->
            circle = Bonfire.Boundaries.Circles.get(circle_slug)
            role = if(is_atom(role_or_verbs), do: role_or_verbs, else: :custom)

            # Return tuple format expected by BoundaryItemsLive
            {circle, role}
          end)

        _ ->
          []
      end
    end)
    |> Enum.reject(fn {circle, _role} -> is_nil(circle) end)
  end

  def get_preset_circles_info(_), do: []

  def get_preset_verb_permissions(boundary_preset, verb)
      when is_binary(boundary_preset) and is_atom(verb) do
    # Get ACL names for this preset
    acl_names = Bonfire.Boundaries.acls_from_preset_boundary_names(boundary_preset)

    # Get grants for each ACL and extract verb permissions
    acl_names
    |> Enum.flat_map(fn acl_name ->
      case Bonfire.Boundaries.Grants.get(acl_name) do
        grants when is_map(grants) ->
          Enum.map(grants, fn {circle_slug, role_or_verbs} ->
            circle = Bonfire.Boundaries.Circles.get(circle_slug)

            # Convert role to verbs or use verbs directly
            verbs =
              if is_atom(role_or_verbs) do
                # Get verbs for role
                case Bonfire.Boundaries.Roles.verbs_for_role(role_or_verbs, %{}) do
                  {:ok, can_verbs, cannot_verbs} ->
                    {can_verbs, cannot_verbs}

                  _ ->
                    {[], []}
                end
              else
                # Direct verbs
                {List.wrap(role_or_verbs), []}
              end

            # Check if the specific verb is in can/cannot lists
            {can_verbs, cannot_verbs} = verbs
            verb_atom = maybe_to_atom(verb)

            value =
              cond do
                verb_atom in can_verbs -> :can
                verb_atom in cannot_verbs -> :cannot
                true -> nil
              end

            {id(circle), value}
          end)
          |> Enum.reject(fn {circle_id, _} -> is_nil(circle_id) end)

        _ ->
          []
      end
    end)
    # Convert to map for easy lookup
    |> Map.new()
  end

  def get_preset_verb_permissions(_, _), do: %{}

  # Helper function to parse verbs into a list of atoms consistently
  defp parse_verbs(verbs) do
    case verbs do
      verbs_string when is_binary(verbs_string) ->
        verbs_string |> String.split(",") |> Enum.map(&maybe_to_atom/1)

      verb_list when is_list(verb_list) ->
        Enum.map(verb_list, &maybe_to_atom/1)

      single_verb ->
        [maybe_to_atom(single_verb)]
    end
  end

  def set_clean_boundaries(to_boundaries, acl_id, name)
      when acl_id in @presets do
    reject_presets(to_boundaries) ++
      [{acl_id, name}]
  end

  def set_clean_boundaries(to_boundaries, acl_id, name) do
    to_boundaries ++ [{acl_id, name}]
  end

  def list_my_circles(scope) do
    # TODO: load using LivePlug to avoid re-loading on render?
    Bonfire.Boundaries.Circles.list_my(scope,
      exclude_block_stereotypes: true
    )
  end

  def circles_for_multiselect(context, circle_field \\ :to_circles)

  def circles_for_multiselect(context, circle_field) do
    case current_user(context) do
      nil ->
        []

      current_user ->
        (e(context, :my_circles, nil) || list_my_circles(current_user))
        |> results_for_multiselect(circle_field)
    end
  end

  def selected_users_for_tags(my_circles) do
    # Filter out only users (not circles) and format them for LiveSelect tags
    my_circles
    |> Enum.filter(fn item -> e(item, :user_type, nil) == "permission_entry" end)
    |> Enum.map(fn user ->
      name = e(user, :name, "Unnamed User")
      username = e(user, :character, :username, nil)
      display_name = if username, do: "#{name} (@#{username})", else: name

      # Return just a simple tuple with display name and user ID
      # LiveSelect doesn't need the full user object for tags display
      {display_name, e(user, :id)}
    end)
  end

  def results_for_multiselect(results, circle_field \\ :to_circles) do
    results
    |> Enum.map(fn
      %Bonfire.Data.AccessControl.Acl{} = acl ->
        name = e(acl, :named, :name, nil) || e(acl, :stereotyped, :named, :name, nil)

        {name,
         %{
           id: e(acl, :id, nil),
           field: :to_boundaries,
           name: name,
           type: "acl"
         }}

      %Bonfire.Data.AccessControl.Circle{} = circle ->
        name = e(circle, :named, :name, nil) || e(circle, :stereotyped, :named, :name, nil)

        {name,
         %{
           id: e(circle, :id, nil),
           field: circle_field,
           name: name,
           type: "circle"
         }}

      user ->
        name = e(user, :profile, :name, nil)
        username = e(user, :character, :username, nil)

        if is_nil(name) and is_nil(username) do
          nil
        else
          {"#{name || ""} - #{username || ""}",
           %{
             id: e(user, :id, nil),
             field: circle_field,
             icon: Media.avatar_url(user),
             name: name,
             username: username,
             type: "user"
           }}
        end
    end)
    |> Enum.reject(&is_nil/1)

    # Reduce the results to show in dropdown for clarity to 4 items
    # |> Enum.take(4)
  end
end
