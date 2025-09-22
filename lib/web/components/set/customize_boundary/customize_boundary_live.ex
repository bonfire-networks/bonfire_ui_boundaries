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

  # ACL mode props
  prop acl_mode, :boolean, default: false
  prop acl, :any, default: nil
  prop acl_subject_verb_grants, :any, default: nil

  # Display control
  prop show_general_boundary, :boolean, default: false

  # Verb filtering options
  prop include_verbs, :list, default: nil
  prop exclude_verbs, :list, default: nil

  # Default verbs to show for common interactions (if no include_verbs specified)
  @default_verbs [
    :request,
    :see,
    :read,
    :like,
    :boost,
    :reply,
    :annotate,
    :message,
    :mention,
    :edit,
    :delete
  ]

  @doc """
  Gets the available verbs for the boundaries UI, with optional filtering.

  ## Options
  - `include_verbs`: List of verbs to include (whitelist). If nil, uses default set.
  - `exclude_verbs`: List of verbs to exclude (blacklist).
  """
  def get_available_verbs(include_verbs \\ nil, exclude_verbs \\ []) do
    all_verbs = Bonfire.Boundaries.Verbs.verbs()

    # Start with either the specified include list, default verbs, or all verbs
    base_verbs =
      cond do
        include_verbs && include_verbs != [] -> include_verbs
        @default_verbs != [] -> @default_verbs
        # Use all available verbs if default is empty
        true -> Keyword.keys(all_verbs)
      end

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

  def update(assigns, socket) do
    {verb_permissions, extracted_users} = determine_verb_permissions_and_users(assigns, socket)

    # Get base circles from DB
    base_circles = assigns[:my_circles] || fetch_my_circles_with_global(current_user(socket))

    # Initialize selected_users with extracted users from ACL + any manually selected
    base_selected_users = socket.assigns[:selected_users] || assigns[:selected_users] || []

    # Merge extracted users with any existing selected users, avoiding duplicates
    selected_users = merge_users_without_duplicates(extracted_users, base_selected_users)

    # Use existing circles or base circles
    existing_circles = socket.assigns[:my_circles]

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
      |> assign(assigns)
      |> assign(:verb_permissions, verb_permissions)
      |> assign(
        :available_verbs,
        get_available_verbs(assigns[:include_verbs], assigns[:exclude_verbs])
      )
      |> assign(
        :preset_boundary,
        Bonfire.UI.Boundaries.SetBoundariesLive.boundaries_to_preset(assigns[:to_boundaries])
      )
      |> assign(:my_circles, my_circles)
      |> assign(:selected_users, selected_users)
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
        if e(assigns, :acl_mode, false) do
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
    # In ACL mode, handle removal directly
    if e(assigns(socket), :acl_mode, false) do
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
      if e(assigns(socket), :acl_mode, false) do
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

  def handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket) do
    # Search for users only when text has at least 2 characters
    if String.length(search) >= 2 do
      search_results = do_user_search(search)
      maybe_send_update(LiveSelect.Component, live_select_id, options: search_results)
    end

    {:noreply, socket}
  end

  def handle_event("multi_select", %{data: user_data_list}, socket)
      when is_list(user_data_list) do
    # Handle both non-empty and empty lists from LiveSelect
    selected_users =
      if user_data_list == [] do
        # Empty list means user cleared all selections
        []
      else
        # Convert LiveSelect data to user objects
        Enum.map(user_data_list, fn user_data ->
          user_name = user_data["name"] || user_data[:name] || "Unnamed User"

          username =
            user_data["username"] || user_data[:username] ||
              get_in(user_data, ["character", "username"])

          %{
            id: user_data["id"] || user_data[:id],
            name: to_string(user_name),
            character: %{username: if(username, do: to_string(username), else: nil)},
            user_type: "permission_entry"
          }
        end)
      end

    # Update selected users
    {:noreply, assign(socket, :selected_users, selected_users)}
  end

  # BYPASS LIVEHANDLERS: Handle direct form change events (MUST be first to intercept before LiveHandlers)
  def handle_event("change", %{"add_to_circles" => data} = params, socket) when is_list(data) do
    debug("DIRECT FORM CHANGE - USER SELECTION triggered")
    debug(params, "Direct form change params")
    debug(data, "add_to_circles data")

    cond do
      data == [] ->
        debug("Empty list received - clearing users and permissions")
        handle_empty_selection(socket)

      is_list(data) ->
        debug("User list received - processing selections")

        # Process the data (could be JSON strings or maps)
        selected_users =
          Enum.map(data, fn item ->
            case item do
              item when is_binary(item) ->
                # JSON string - decode it
                case Jason.decode(item) do
                  {:ok, user_data} ->
                    debug(user_data, "Decoded user from JSON")

                    %{
                      id: user_data["id"],
                      name: user_data["name"],
                      character: %{username: user_data["username"]},
                      user_type: "permission_entry",
                      username: user_data["username"]
                    }

                  {:error, _} ->
                    debug("Failed to decode JSON: #{inspect(item)}")
                    nil
                end

              item when is_map(item) ->
                # Already a map
                debug(item, "Direct map user data")

                %{
                  id: item["id"] || item[:id],
                  name: item["name"] || item[:name],
                  character: %{username: item["username"] || item[:username]},
                  user_type: "permission_entry",
                  username: item["username"] || item[:username]
                }

              _ ->
                debug("Unknown data format: #{inspect(item)}")
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        debug(selected_users, "Final processed selected users")
        {:noreply, assign(socket, :selected_users, selected_users)}
    end
  end

  # Handle LiveHandlers delegation format for multi_select (fallback if direct doesn't work)
  def handle_event("multi_select", %{data: data} = params, socket)
      when is_list(data) and data != [] do
    debug("LIVE_HANDLERS USER SELECTION triggered (fallback)")
    debug(params, "LiveHandlers user selection params")
    debug(data, "User data from LiveHandlers")

    # Process users from LiveHandlers format
    selected_users =
      Enum.map(data, fn user_data ->
        %{
          id: user_data["id"],
          name: user_data["name"],
          character: %{username: user_data["username"]},
          user_type: "permission_entry",
          username: user_data["username"]
        }
      end)

    debug(selected_users, "Processed selected users from LiveHandlers")
    {:noreply, assign(socket, :selected_users, selected_users)}
  end

  # Handle LiveHandlers delegation format for empty selection
  def handle_event("multi_select", %{data: nil} = params, socket) do
    debug("LIVE_HANDLERS EMPTY SELECTION triggered")
    debug(params, "LiveHandlers empty selection params")
    handle_empty_selection(socket)
  end

  def handle_event("multi_select", %{data: []} = params, socket) do
    debug("LIVE_HANDLERS EMPTY LIST triggered")
    debug(params, "LiveHandlers empty list params")
    handle_empty_selection(socket)
  end

  # Handle LiveSelect user selection - this is the actual format LiveSelect sends (fallback)
  def handle_event(
        "multi_select",
        %{
          "_target" => ["multi_select", "Elixir.Bonfire.UI.Boundaries.CustomizeBoundaryLive"],
          "multi_select" => %{
            "Elixir.Bonfire.UI.Boundaries.CustomizeBoundaryLive" => user_data_json_list,
            "Elixir.Bonfire.UI.Boundaries.CustomizeBoundaryLive_text_input" => _text
          }
        } = params,
        socket
      )
      when is_list(user_data_json_list) do
    # Convert JSON strings to user objects
    selected_users =
      if user_data_json_list == [] do
        []
      else
        Enum.map(user_data_json_list, fn json_string ->
          user_data = Jason.decode!(json_string)

          %{
            id: user_data["id"],
            name: user_data["name"],
            username: get_in(user_data, ["username"]),
            character: %{username: get_in(user_data, ["username"])},
            user_type: "permission_entry"
          }
        end)
      end

    debug(selected_users, "Parsed selected users")

    # Update selected users
    {:noreply, assign(socket, :selected_users, selected_users)}
  end

  # Handle LiveSelect empty selection - this specific pattern comes from LiveSelect
  def handle_event(
        "multi_select",
        %{
          "Elixir.Bonfire.UI.Boundaries.CustomizeBoundaryLive_empty_selection" => "",
          "Elixir.Bonfire.UI.Boundaries.CustomizeBoundaryLive_text_input" => text_value
        } = params,
        socket
      ) do
    # This catches when user clears all selections via LiveSelect
    debug("EMPTY SELECTION handler 1 triggered")
    debug(params, "Empty selection params - handler 1")
    debug("Empty selection event received, text_value: #{inspect(text_value)}")

    # Get current selected users before clearing
    current_selected_users = e(assigns(socket), :selected_users, [])

    # Get current verb_permissions
    current_verb_permissions = e(assigns(socket), :verb_permissions, %{})

    # Remove permissions for all selected users
    cleaned_verb_permissions =
      if current_selected_users != [] do
        user_ids = Enum.map(current_selected_users, &id/1)

        # Remove user IDs from each verb's permissions map
        Enum.reduce(current_verb_permissions, %{}, fn {verb, permissions}, acc ->
          cleaned_permissions =
            Enum.reject(permissions, fn {role_id, _value} ->
              role_id in user_ids
            end)
            |> Map.new()

          Map.put(acc, verb, cleaned_permissions)
        end)
      else
        current_verb_permissions
      end

    # Clear selected users and update permissions
    {:noreply,
     socket
     |> assign(:selected_users, [])
     |> assign(:verb_permissions, cleaned_verb_permissions)}
  end

  def handle_event(
        "multi_select",
        %{
          "multi_select" => %{
            "Elixir.Bonfire.UI.Boundaries.CustomizeBoundaryLive_empty_selection" => "",
            "Elixir.Bonfire.UI.Boundaries.CustomizeBoundaryLive_text_input" => _
          }
        } = params,
        socket
      ) do
    # Use the helper function with all the debug logging
    handle_empty_selection(socket)
  end

  # Handle standard LiveSelect change event (what LiveSelect actually sends)
  def handle_event(
        "change",
        %{"Elixir.Bonfire.UI.Boundaries.CustomizeBoundaryLive" => data} = params,
        socket
      ) do
    # Handle the data based on its type
    cond do
      is_list(data) and data == [] ->
        debug("Empty list received - clearing users and permissions")
        handle_empty_selection(socket)

      is_list(data) ->
        debug("User list received - processing selections")
        handle_user_selection(data, socket)

      true ->
        debug("Unknown data format: #{inspect(data)}")
        {:noreply, socket}
    end
  end

  # Handle PhoenixLive event format (field name from multiselect)
  def handle_event("change", %{"add_to_circles" => data} = params, socket) do
    cond do
      is_list(data) and data == [] ->
        debug("Empty circles - clearing users and permissions")
        handle_empty_selection(socket)

      is_list(data) ->
        debug("Circles data received")
        handle_user_selection(data, socket)

      true ->
        debug("Unknown circles data format: #{inspect(data)}")
        {:noreply, socket}
    end
  end

  # Handle any general change event
  def handle_event("change", params, socket) do
    # Look for any list fields that might be the user selections
    user_data =
      Enum.find_value(params, fn
        {key, value} when is_list(value) ->
          debug("Found list field: #{key} = #{inspect(value)}")
          {key, value}

        _ ->
          nil
      end)

    case user_data do
      {_key, []} ->
        debug("Found empty list - triggering empty selection")
        handle_empty_selection(socket)

      {_key, data} when is_list(data) ->
        debug("Found populated list - triggering user selection")
        handle_user_selection(data, socket)

      nil ->
        debug("No list fields found in change event")
        {:noreply, socket}
    end
  end

  # Handle live_select_change events (from LiveHandlers delegation)
  def handle_event("live_select_change", params, socket) do
    # This is usually just for autocomplete/search, acknowledge without state change
    {:noreply, socket}
  end

  # Handle validate events which LiveSelect might also send
  def handle_event("validate", params, socket) do
    # Usually just need to acknowledge validate without changing state
    {:noreply, socket}
  end

  def handle_event("multi_select", params, socket) do
    # Catch-all: for any other unrecognized multi_select patterns
    # Log what we're receiving to help debug LiveSelect's actual event structure
    # Log nested structure
    if is_map(params) do
      Enum.each(params, fn {key, value} ->
        debug(
          "Key: #{inspect(key)}, Value type: #{inspect(type_of(value))}, Value: #{inspect(value)}"
        )
      end)
    end

    # For safety, clear selected users
    {:noreply, assign(socket, :selected_users, [])}
  end

  # Helper to handle empty selection (clearing all users and their permissions)
  defp handle_empty_selection(socket) do
    debug("Processing empty selection - clearing users and permissions")

    # Get current selected users and permissions before clearing
    current_selected_users = e(assigns(socket), :selected_users, [])
    current_verb_permissions = e(assigns(socket), :verb_permissions, %{})

    debug(current_selected_users, "Users being removed")
    debug(current_verb_permissions, "Current verb_permissions before cleanup")

    # If no users are selected, this is likely a duplicate event - handle gracefully
    if current_selected_users == [] do
      debug("No users currently selected - this may be a duplicate empty selection event")
      debug("Already in clean state, returning without changes")
      {:noreply, socket}
    else
      debug("Processing permission cleanup for #{length(current_selected_users)} users")

      # Remove permissions for all selected users
      # Get user IDs in various formats that might be used
      user_ids =
        Enum.flat_map(current_selected_users, fn user ->
          ids =
            [
              id(user),
              e(user, :id, nil),
              e(user, "id", nil),
              to_string(id(user))
            ]
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

          debug("User #{inspect(user)} has IDs: #{inspect(ids)}")
          ids
        end)
        |> Enum.uniq()

      debug(user_ids, "All user IDs to set permissions to nil")

      # Set each user's permission to nil for each verb using existing handle_verb_update logic
      final_socket =
        Enum.reduce(current_verb_permissions, socket, fn {verb, permissions}, acc_socket ->
          # For each verb, set permissions to nil for all cleared users
          user_verbs_to_update =
            Enum.filter(permissions, fn {role_id, _value} ->
              role_id in user_ids or to_string(role_id) in user_ids
            end)

          debug("Setting #{length(user_verbs_to_update)} permissions to nil for verb #{verb}")

          # Update each user's permission for this verb using the existing logic
          Enum.reduce(user_verbs_to_update, acc_socket, fn {role_id, _value}, user_socket ->
            debug("Setting permission to nil for role_id #{role_id} in verb #{verb}")

            # Use the existing handle_verb_update function which handles ACL/boundary mode properly
            case handle_verb_update(user_socket, role_id, verb, nil) do
              {:noreply, updated_socket} -> updated_socket
              # fallback if something goes wrong
              _ -> user_socket
            end
          end)
        end)

      # Clear selected users from the final socket
      {:noreply, assign(final_socket, :selected_users, [])}
    end
  end

  # Helper to handle user selection
  defp handle_user_selection(data, socket) do
    debug(data, "Processing user selection data")

    # Convert data to user objects
    selected_users =
      if is_list(data) do
        Enum.map(data, fn item ->
          cond do
            is_binary(item) ->
              # Try to decode JSON
              case Jason.decode(item) do
                {:ok, user_data} ->
                  debug(user_data, "Decoded user data from JSON")

                  %{
                    id: user_data["id"],
                    name: user_data["name"],
                    character: %{username: get_in(user_data, ["username"])},
                    user_type: "permission_entry"
                  }

                {:error, _} ->
                  debug("Failed to decode JSON: #{item}")
                  nil
              end

            is_map(item) ->
              debug(item, "Direct map user data")

              %{
                id: item["id"] || item[:id],
                name: item["name"] || item[:name],
                character: %{username: item["username"] || item[:username]},
                user_type: "permission_entry"
              }

            true ->
              debug("Unknown user data format: #{inspect(item)}")
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)
      else
        debug("Data is not a list: #{inspect(data)}")
        []
      end

    debug(selected_users, "Final processed selected users")

    {:noreply, assign(socket, :selected_users, selected_users)}
  end

  # Helper to get type information for debugging
  defp type_of(value) when is_binary(value), do: :string
  defp type_of(value) when is_list(value), do: :list
  defp type_of(value) when is_map(value), do: :map
  defp type_of(value) when is_atom(value), do: :atom
  defp type_of(value) when is_integer(value), do: :integer
  defp type_of(value), do: :other

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
