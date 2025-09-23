defmodule Bonfire.UI.Boundaries.CustomizeBoundaryLive do
  use Bonfire.UI.Common.Web, :stateful_component
  use Bonfire.Common.Utils
  # alias Bonfire.Boundaries.Roles
  alias Bonfire.UI.Boundaries.VerbPermissionsHelper
  alias Bonfire.Common.Media

  prop to_boundaries, :any, default: nil
  prop hide_presets, :boolean, default: false
  prop boundary_preset, :any, default: nil
  prop set_action, :any, default: nil
  prop set_opts, :any, default: %{}
  prop my_acls, :any, default: nil
  prop verb_permissions, :any, default: %{}
  prop is_customizable, :boolean, default: false
  prop hide_custom, :boolean, default: false
  prop to_circles, :list, default: []
  prop exclude_circles, :list, default: []
  prop selected_users, :list, default: []
  prop parent_id, :string, default: nil

  # ACL mode props
  prop setting_boundaries, :atom, default: nil
  prop acl, :any, default: nil
  prop acl_subject_verb_grants, :any, default: nil

  # Display control
  prop show_general_boundary, :boolean, default: false

  # Verb filtering options
  prop include_verbs, :list, default: nil
  prop exclude_verbs, :list, default: nil

  # Default verbs to show for common interactions (if no include_verbs specified)
  def default_verbs_for(key), do: Config.get([:default_verbs_for, key], [])

  # All verbs in preferred order
  def verb_order, do: Config.get!(:preferred_verb_order)

  def update(assigns, socket) do
    socket = socket |> assign(assigns)

    {verb_permissions, extracted_users} =
      determine_verb_permissions_and_users(assigns(socket), socket)

    # Get base circles from DB
    base_circles =
      assigns(socket)[:my_circles] || fetch_my_circles_with_global(current_user(socket))

    # Initialize selected_users with extracted users from ACL + any manually selected
    base_selected_users =
      assigns(socket)[:selected_users] || assigns(socket)[:selected_users] || []

    # Merge extracted users with any existing selected users, avoiding duplicates
    selected_users = merge_users_without_duplicates(extracted_users, base_selected_users)

    # Use existing circles or base circles
    existing_circles = assigns(socket)[:my_circles]

    my_circles =
      if existing_circles do
        existing_circles
      else
        base_circles
      end

    debug(extracted_users, "Users extracted from ACL boundaries")
    debug(selected_users, "Final selected users (ACL + manual)")

    {
      :ok,
      socket
      |> assign(:verb_permissions, verb_permissions)
      |> assign(
        :available_verbs,
        get_available_verbs(
          assigns(socket)[:setting_boundaries],
          assigns(socket)[:include_verbs],
          assigns(socket)[:exclude_verbs]
        )
      )
      |> assign(
        :preset_boundary,
        Bonfire.UI.Boundaries.SetBoundariesLive.boundaries_to_preset(
          assigns(socket)[:to_boundaries]
        )
      )
      |> assign(:my_circles, my_circles)
      |> assign(:selected_users, selected_users)
    }
  end

  defp editing_acl?(setting_boundaries) do
    !setting_boundaries or setting_boundaries == :edit_object
  end

  @doc """
  Gets the available verbs for the boundaries UI, with optional filtering.

  ## Options
  - `include_verbs`: List of verbs to include (allow-list). If nil, uses default set.
  - `exclude_verbs`: List of verbs to exclude (deny-list).
  """
  def get_available_verbs(setting_boundaries \\ nil, include_verbs \\ nil, exclude_verbs \\ []) do
    # TODO: list verbs appropriate for the each scope/context
    default_verbs =
      if setting_boundaries == :create_object, do: default_verbs_for(:objects), else: []

    # Start with either the specified include list, default verbs, or all verbs
    base_verbs =
      cond do
        include_verbs && include_verbs != [] -> include_verbs
        default_verbs != [] -> default_verbs
        # Use all available verbs if default is empty
        true -> verb_order()
      end

    all_verbs = Bonfire.Boundaries.Verbs.verbs()

    # Filter to only include verbs that exist in the configuration
    available =
      Enum.filter(base_verbs, fn verb_slug ->
        Keyword.has_key?(all_verbs, verb_slug)
      end)

    # Remove any excluded verbs
    excluded_set = MapSet.new(exclude_verbs || [])

    available
    |> Enum.reject(fn verb_slug -> MapSet.member?(excluded_set, verb_slug) end)
    |> Enum.map(fn verb_slug ->
      verb_config = Keyword.get(all_verbs, verb_slug, %{})
      # Return a simple map that Surface templates can handle
      %{
        slug: verb_slug,
        icon: e(verb_config, :icon, "ph:circle-duotone"),
        name: e(verb_config, :verb, verb_slug |> to_string() |> String.capitalize()),
        summary: e(verb_config, :summary, "Who can #{verb_slug} the post")
      }
    end)
  end

  def fetch_my_circles_with_global(scope) do
    # TODO: load using LivePlug to avoid re-loading on render?
    Bonfire.Boundaries.Circles.list_my_with_global(scope,
      exclude_block_stereotypes: true,
      exclude_circles: [Bonfire.Boundaries.Scaffold.Instance.admin_circle()]
    )
  end

  # Helper to detect and load custom ACL from to_boundaries
  defp detect_custom_acl_from_to_boundaries(assigns, socket) do
    to_boundaries = e(assigns, :to_boundaries, [])
    current_user = current_user(socket)

    with {:ok, acl_id} <- extract_acl_id_from_boundaries(to_boundaries),
         {:ok, current_user} <- validate_current_user(current_user),
         {:ok, verb_permissions, extracted_users} <- load_and_transform_acl(acl_id, current_user) do
      {:ok, verb_permissions, extracted_users}
    else
      error ->
        debug(error, "Custom ACL detection failed")
        :error
    end
  end

  # Extract ACL ID from to_boundaries if it contains a valid ULID
  defp extract_acl_id_from_boundaries(to_boundaries) do
    acl_id =
      case to_boundaries do
        [{acl_id, _name}] when is_binary(acl_id) ->
          if Needle.ULID.valid?(acl_id), do: acl_id, else: nil

        [acl_id] when is_binary(acl_id) ->
          if Needle.ULID.valid?(acl_id), do: acl_id, else: nil

        _ ->
          nil
      end

    case acl_id do
      nil -> {:error, :no_acl_id}
      valid_id -> {:ok, valid_id}
    end
  end

  # Validate that current user exists
  defp validate_current_user(current_user) do
    if is_nil(current_user) do
      {:error, :no_current_user}
    else
      {:ok, current_user}
    end
  end

  # Load ACL and transform to verb permissions format, also extracting users
  defp load_and_transform_acl(acl_id, current_user) do
    case Bonfire.Boundaries.Acls.get_for_caretaker(acl_id, current_user) do
      {:ok, acl} ->
        transform_acl_to_verb_permissions(acl)

      error ->
        debug(error, "Failed to load ACL for caretaker")
        {:error, :acl_load_failed}
    end
  end

  # Transform ACL to verb permissions format with preloading and extract users
  defp transform_acl_to_verb_permissions(acl) do
    # Preload grants
    acl_with_grants =
      acl
      |> repo().maybe_preload(
        [
          grants: [:verb, subject: [:named, :profile, :character, stereotyped: [:named]]]
        ],
        force: true
      )

    # Get grants for processing
    grants = e(acl_with_grants, :grants, [])

    # Extract users who are subjects in the grants (not circles/stereotypes)
    extracted_users = extract_users_from_grants(grants)

    # Transform to verb_permissions format
    acl_subject_verb_grants = Bonfire.Boundaries.Grants.subject_verb_grants(grants)

    {verb_permissions, _} =
      VerbPermissionsHelper.transform_acl_to_verb_format(acl_subject_verb_grants)

    {:ok, verb_permissions, extracted_users}
  end

  # Extract individual users from ACL grants (filtering out circles and stereotypes)
  defp extract_users_from_grants(grants) do
    debug(grants, "Raw grants for user extraction")

    subjects =
      grants
      |> Enum.map(fn grant -> e(grant, :subject, nil) end)
      |> Enum.reject(&is_nil/1)

    debug(subjects, "All subjects from grants")

    user_subjects =
      subjects
      |> Enum.filter(&is_user_subject?/1)

    debug(user_subjects, "Filtered user subjects")

    unique_users =
      user_subjects
      |> Enum.uniq_by(&id/1)

    debug(unique_users, "Unique user subjects")

    formatted_users =
      unique_users
      |> Enum.map(&format_user_for_selected_list/1)

    debug(formatted_users, "Final formatted users")

    formatted_users
  end

  # Check if a subject is an individual user (not a circle or stereotype)
  defp is_user_subject?(subject) do
    # Users have profile and character, but are not stereotyped circles
    has_profile = not is_nil(e(subject, :profile, nil))
    has_character = not is_nil(e(subject, :character, nil))
    is_not_stereotyped = is_nil(e(subject, :stereotyped, nil))

    debug(
      "Subject check - ID: #{id(subject)}, has_profile: #{has_profile}, has_character: #{has_character}, is_not_stereotyped: #{is_not_stereotyped}"
    )

    result = has_profile and has_character and is_not_stereotyped

    if not result do
      debug(subject, "Subject rejected as not a user")
    end

    result
  end

  # Format user from ACL subject to match selected_users format
  defp format_user_for_selected_list(user) do
    %{
      id: id(user),
      name: e(user, :profile, :name, nil) || e(user, :named, :name, nil) || "Unnamed User",
      character: %{username: e(user, :character, :username, nil)},
      user_type: "permission_entry",
      username: e(user, :character, :username, nil)
    }
  end

  # Merge users without duplicates based on ID
  defp merge_users_without_duplicates(extracted_users, base_users) do
    all_users = (extracted_users || []) ++ (base_users || [])

    all_users
    |> Enum.uniq_by(&id/1)
    |> Enum.reject(&is_nil/1)
  end

  # Clean separation of concerns - returns {verb_permissions, extracted_users}
  defp determine_verb_permissions_and_users(assigns, socket) do
    case e(assigns, :verb_permissions, nil) do
      provided when not is_nil(provided) and provided != %{} ->
        # If verb_permissions are provided, no extracted users from ACL
        {provided, []}

      _ ->
        if editing_acl?(e(assigns, :setting_boundaries, nil)) do
          load_acl_verb_permissions_and_users(assigns, socket)
        else
          load_boundary_verb_permissions_and_users(assigns, socket)
        end
    end
  end

  # Backwards compatibility - old function for verb permissions only
  defp determine_verb_permissions(assigns, socket) do
    {verb_permissions, _} = determine_verb_permissions_and_users(assigns, socket)
    verb_permissions
  end

  # Load ACL verb permissions and extract users
  defp load_acl_verb_permissions_and_users(assigns, socket) do
    acl_subject_verb_grants = e(assigns, :acl_subject_verb_grants, nil)

    if acl_subject_verb_grants && acl_subject_verb_grants != %{} do
      {perms, _} = VerbPermissionsHelper.transform_acl_to_verb_format(acl_subject_verb_grants)
      # TODO: Extract users from acl_subject_verb_grants if needed
      {perms, []}
    else
      case detect_custom_acl_from_to_boundaries(assigns, socket) do
        {:ok, verb_permissions, extracted_users} -> {verb_permissions, extracted_users}
        _ -> {%{}, []}
      end
    end
  end

  # Backwards compatibility - old function for verb permissions only
  defp load_acl_verb_permissions(assigns, socket) do
    {verb_permissions, _} = load_acl_verb_permissions_and_users(assigns, socket)
    verb_permissions
  end

  # Load boundary verb permissions and extract users
  defp load_boundary_verb_permissions_and_users(assigns, socket) do
    preset_boundary =
      Bonfire.UI.Boundaries.SetBoundariesLive.boundaries_to_preset(assigns[:to_boundaries])

    cond do
      preset_boundary ->
        # Preset boundaries don't have individual users, only circles
        verb_permissions = load_preset_verb_permissions(preset_boundary, assigns, socket)
        {verb_permissions, []}

      true ->
        case detect_custom_acl_from_to_boundaries(assigns, socket) do
          {:ok, verb_permissions, extracted_users} -> {verb_permissions, extracted_users}
          _ -> {reconstruct_from_circles(assigns), []}
        end
    end
  end

  # Backwards compatibility - old function for verb permissions only
  defp load_boundary_verb_permissions(assigns, socket) do
    {verb_permissions, _} = load_boundary_verb_permissions_and_users(assigns, socket)
    verb_permissions
  end

  defp load_preset_verb_permissions(preset_boundary, assigns, socket) do
    # Load preset's default circles and permissions
    preset_circles =
      Bonfire.UI.Boundaries.SetBoundariesLive.get_preset_circles_info(preset_boundary)

    # Expand roles to individual verbs
    preset_circles_with_verbs = expand_preset_roles_to_verbs(preset_circles)

    # Convert to verb permissions format
    preset_verb_permissions =
      VerbPermissionsHelper.reconstruct_verb_permissions(preset_circles_with_verbs, [])

    # Check if preset has changed - if so, start fresh
    current_preset = e(assigns(socket), :preset_boundary, nil)
    current_verb_permissions = e(assigns(socket), :verb_permissions, %{})

    if preset_changed?(current_preset, preset_boundary) do
      preset_verb_permissions
    else
      # Merge preset defaults with custom overrides
      merge_verb_permissions(preset_verb_permissions, current_verb_permissions)
    end
  end

  # Detect if the preset boundary has changed
  defp preset_changed?(current_preset, new_preset) do
    current_preset != new_preset
  end

  # Expand preset roles to individual verbs using existing Bonfire pattern
  defp expand_preset_roles_to_verbs(circles_with_roles) do
    Enum.flat_map(circles_with_roles, fn {circle, role} ->
      # Use existing Bonfire pattern from scaffold/instance.ex
      expanded_verbs = list_verbs_for_role(role)
      Enum.map(expanded_verbs, fn {verb, _value} -> {circle, verb} end)
    end)
  end

  # Following the existing pattern from Bonfire.Boundaries.Scaffold.Instance
  defp list_verbs_for_role(verbs) when is_list(verbs) or is_map(verbs), do: verbs

  defp list_verbs_for_role(role) when is_atom(role) do
    role_definition = Bonfire.Boundaries.Roles.get(role)

    (role_definition
     |> e(:can_verbs, [])
     |> Enum.map(&{&1, true})) ++
      (role_definition
       |> e(:cannot_verbs, [])
       |> Enum.map(&{&1, false}))
  end

  # Merge preset defaults with custom overrides
  defp merge_verb_permissions(preset_permissions, custom_permissions) do
    Map.merge(preset_permissions, custom_permissions, fn _verb, preset_map, custom_map ->
      Map.merge(preset_map, custom_map)
    end)
  end

  defp reconstruct_from_circles(assigns) do
    to_circles = e(assigns, :to_circles, [])
    exclude_circles = e(assigns, :exclude_circles, [])
    VerbPermissionsHelper.reconstruct_verb_permissions(to_circles, exclude_circles)
  end

  def handle_event(
        "edit_verb_value",
        %{"role" => circle_id, "verb" => verb, "status" => status},
        socket
      ) do
    # Basic validation
    if is_nil(circle_id) or circle_id == "" or is_nil(verb) or verb == "" do
      {:noreply, socket}
    else
      # Convert status to proper value
      verb_value =
        case status do
          "1" -> :can
          "0" -> :cannot
          _ -> nil
        end

      handle_verb_update(socket, circle_id, verb, verb_value)
    end
  end

  def handle_event(
        "remove_from_acl",
        %{"subject_id" => subject_id},
        socket
      ) do
    # When editing an ACL, handle removal directly
    if editing_acl?(e(assigns(socket), :setting_boundaries, nil)) do
      acl_id = e(assigns(socket), :acl, :id, nil)

      if acl_id do
        case Bonfire.Boundaries.Grants.remove_subject_from_acl(subject_id, acl_id) do
          {del, _} when is_integer(del) and del > 0 ->
            # Notify parent to refresh data
            if parent_component = e(assigns(socket), :parent_component, nil) do
              send_update(parent_component, %{force_refresh: true})
            end

            {:noreply, assign_flash(socket, :info, l("Removed from boundary"))}

          {0, _} ->
            {:noreply, assign_flash(socket, :info, l("No permissions to remove"))}

          {:error, reason} ->
            error(reason, "Failed to remove subject from ACL")
            {:noreply, assign_error(socket, l("Could not remove from boundary"))}

          other ->
            error(other, "Unexpected result from remove_subject_from_acl")
            {:noreply, assign_error(socket, l("Could not remove from boundary"))}
        end
      else
        {:noreply, assign_error(socket, l("Boundary not found"))}
      end
    else
      {:noreply, socket}
    end
  end

  defp handle_verb_update(socket, circle_id, verb, verb_value) do
    # Get current verb permissions (stored as map of maps: %{verb => %{circle_id => value}})
    current_verbs = e(assigns(socket), :verb_permissions, %{})
    # Update the specific verb for the specific circle
    updated_verbs =
      VerbPermissionsHelper.update_verb_permission(current_verbs, circle_id, verb, verb_value)

    # Handle ACL mode differently
    final_verbs =
      if editing_acl?(e(assigns(socket), :setting_boundaries, nil)) do
        case update_acl_mode_permissions(socket, circle_id, verb, verb_value, updated_verbs) do
          {:ok, permissions} -> permissions
          # Revert on error
          {:error, _reason} -> current_verbs
        end
      else
        update_boundary_mode_permissions(socket, updated_verbs)
      end

    {:noreply, assign(socket, :verb_permissions, final_verbs)}
  end

  # Handle ACL mode permission updates
  defp update_acl_mode_permissions(socket, circle_id, verb, verb_value, updated_verbs) do
    acl = e(assigns(socket), :acl, nil)
    current_user = current_user(socket)

    case maybe_to_atom(String.downcase(verb)) do
      nil ->
        debug({verb, "invalid verb"}, "Verb atom doesn't exist")
        {:error, :invalid_verb}

      verb_atom ->
        case Bonfire.Boundaries.Grants.grant(
               circle_id,
               acl,
               verb_atom,
               verb_value_to_grant_value(verb_value),
               current_user: current_user
             ) do
          {:ok, _grant} ->
            {:ok, updated_verbs}

          {:error, error} ->
            debug(error, "Failed to update permission")
            {:error, :permission_update_failed}
        end
    end
  end

  # Handle boundary mode permission updates
  defp update_boundary_mode_permissions(socket, updated_verbs) do
    # In non-ACL mode, send only the verb permissions to parent
    # The backend will handle transformation via verb_permissions_json
    maybe_send_update(
      Bonfire.UI.Common.SmartInputContainerLive,
      :smart_input,
      %{
        verb_permissions: updated_verbs
      }
    )

    updated_verbs
  end

  # Helper function to convert verb_value to the format expected by Grants.grant/5
  defp verb_value_to_grant_value(verb_value) do
    case verb_value do
      :can -> true
      :cannot -> false
      nil -> nil
    end
  end

  # Handle LiveSelect user selection - dynamic field names
  def handle_event(
        "change",
        %{"_target" => ["multi_select", field_name], "multi_select" => multi_select_data} =
          params,
        socket
      )
      when is_map_key(multi_select_data, field_name) and
             is_list(:erlang.map_get(field_name, multi_select_data)) do
    debug(params, "LiveSelect user selection")
    user_data = multi_select_data[field_name]
    selected_users = decode_selected_users(user_data)
    {:noreply, assign(socket, :selected_users, selected_users)}
  end

  def handle_event(
        "change",
        %{
          "_target" => ["multi_select", "customize_boundary_live_empty_selection"],
          "multi_select" => %{
            "_unused_customize_boundary_live_text_input" => "",
            "customize_boundary_live_empty_selection" => "",
            "customize_boundary_live_text_input" => ""
          }
        } = _params,
        socket
      ) do
    {:noreply, socket}
  end

  # Handle LiveSelect clear selection - dynamic field names
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
        {:noreply, handle_clear_users(socket)}

      _ ->
        debug(params, "Unhandled clear event")
        {:noreply, socket}
    end
  end

  def handle_event("change", params, socket) do
    debug(params, "Unhandled change event")
    {:noreply, socket}
  end

  # Handle search autocomplete from LiveSelect (via LiveHandlers or directly)
  def handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket)
      when is_binary(search) do
    debug(search, "LiveSelect autocomplete search")
    handle_user_search(search, live_select_id, socket)
  end

  # Fallback handler for live_select_change without id field
  def handle_event("live_select_change", %{"text" => search} = params, socket)
      when is_binary(search) do
    debug(params, "LiveSelect autocomplete search (fallback - constructing ID)")
    # Try to construct the component ID as fallback
    parent_id = e(assigns(socket), :parent_id, nil) || "customize_boundary_live"
    live_select_id = "multi_select_#{parent_id}_live_select_component"
    handle_user_search(search, live_select_id, socket)
  end

  # Handle search from LiveHandlers delegation with field info
  # def handle_event("live_select_change", %{"field" => _field, "text" => search} = params, socket) when is_binary(search) do
  #   debug(params, "LiveSelect autocomplete search with field")
  #   handle_user_search(search, socket)
  # end

  # Decode selected users from LiveSelect JSON format
  defp decode_selected_users(user_data) when is_list(user_data) do
    user_data
    |> Enum.map(&decode_single_user/1)
    |> Enum.reject(&is_nil/1)
  end

  defp decode_selected_users(_), do: []

  # Decode a single user from various formats
  defp decode_single_user(user) when is_binary(user) do
    case Jason.decode(user) do
      {:ok, decoded} -> format_decoded_user(decoded)
      {:error, _} -> nil
    end
  end

  defp decode_single_user(user) when is_map(user) do
    format_decoded_user(user)
  end

  defp decode_single_user(_), do: nil

  # Format decoded user data to consistent structure
  defp format_decoded_user(user_data) do
    %{
      id: user_data["id"] || user_data[:id],
      name: user_data["name"] || user_data[:name] || "Unnamed User",
      character: %{username: user_data["username"] || user_data[:username]},
      user_type: "permission_entry",
      username: user_data["username"] || user_data[:username]
    }
  end

  # Handle clearing users and their permissions using the same mechanism as edit_verb_value
  defp handle_clear_users(socket) do
    current_selected_users = e(assigns(socket), :selected_users, [])

    if current_selected_users == [] do
      debug("No users to clear")
      socket
    else
      debug("Clearing #{length(current_selected_users)} users and their permissions")
      clear_user_permissions_consistently(socket, current_selected_users)
    end
  end

  # Clear permissions for specific users using the same mechanism as edit_verb_value
  defp clear_user_permissions_consistently(socket, users_to_clear) do
    current_verb_permissions = e(assigns(socket), :verb_permissions, %{})

    # For each user that needs to be cleared, clear only their existing verb permissions
    updated_socket =
      Enum.reduce(users_to_clear, socket, fn user, acc_socket ->
        user_id = id(user)

        # Only clear verbs where this user has existing permissions
        Enum.reduce(current_verb_permissions, acc_socket, fn {verb_string, permissions},
                                                             verb_socket ->
          if Map.has_key?(permissions, user_id) do
            # User has a permission for this verb, clear it
            {:noreply, updated_socket} =
              handle_verb_update(verb_socket, user_id, verb_string, nil)

            updated_socket
          else
            # User has no permission for this verb, skip
            verb_socket
          end
        end)
      end)

    # Clear the selected users list
    assign(updated_socket, :selected_users, [])
  end

  # Handle user search for autocomplete - use provided live_select_id
  defp handle_user_search(search, live_select_id, socket) when byte_size(search) >= 2 do
    search_results = do_user_search(search)
    maybe_send_update(LiveSelect.Component, live_select_id, options: search_results)
    {:noreply, socket}
  end

  defp handle_user_search(_search, _live_select_id, socket) do
    {:noreply, socket}
  end

  # Search for users only (not circles)
  defp do_user_search(search) do
    Utils.maybe_apply(
      Bonfire.Me.Users,
      :search,
      [search]
    )
    |> Enum.map(fn
      %Needle.Pointer{activity: %{object: user}} -> user
      other -> other
    end)
    |> Enum.filter(&is_user?/1)
    |> format_users_for_multiselect()
  end

  # Check if the result is a user (not a circle or other entity)
  defp is_user?(%{__struct__: struct}) when struct in [Bonfire.Data.Identity.User], do: true
  defp is_user?(%{profile: _}), do: true
  defp is_user?(%{character: _}), do: true
  defp is_user?(_), do: false

  # Format users for LiveSelect options
  defp format_users_for_multiselect(users) do
    Enum.map(users, fn user ->
      name = e(user, :profile, :name, nil) || e(user, :character, :username, nil) || "Unnamed"
      username = e(user, :character, :username, nil)
      avatar = Media.avatar_url(user)

      display_name = if username, do: "#{name} (@#{username})", else: name

      {display_name,
       %{
         id: id(user),
         name: name,
         username: username,
         icon: avatar,
         type: "user"
       }}
    end)
  end
end
