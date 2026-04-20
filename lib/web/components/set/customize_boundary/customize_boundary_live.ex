defmodule Bonfire.UI.Boundaries.CustomizeBoundaryLive do
  use Bonfire.UI.Common.Web, :stateful_component
  use Bonfire.Common.Utils
  # alias Bonfire.Boundaries.Roles
  alias Bonfire.UI.Boundaries.VerbPermissionsHelper
  alias Bonfire.Common.Media

  prop to_boundaries, :any, default: nil
  prop hide_presets, :boolean, default: false
  prop read_only, :boolean, default: false
  prop boundary_preset, :any, default: nil
  prop set_action, :any, default: nil
  prop set_opts, :any, default: %{}
  prop my_acls, :any, default: nil
  prop scope, :any, default: nil
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

    # Get my_acls from props, context, or fetch if needed (once only in update, not render)
    # Handles both :user and :instance scope
    scope = assigns(socket)[:scope]

    my_acls =
      assigns(socket)[:my_acls] ||
        e(assigns(socket)[:__context__], :my_acls, nil) ||
        (warn("my_acls should be preloaded at top level") &&
           if scope == :user or is_nil(scope) do
             Bonfire.Boundaries.LiveHandler.my_acls(current_user_id(socket))
           else
             Bonfire.Boundaries.LiveHandler.my_acls(scope)
           end)

    # Get base circles from DB
    base_circles =
      assigns(socket)[:my_circles] ||
        (warn("my_circles should be preloaded at top level") &&
           fetch_my_circles_with_global(current_user(socket)))

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
          assigns(socket)[:scope],
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
      |> assign(:my_acls, my_acls)
      |> assign(:selected_users, selected_users)
      |> assign_per_action_state()
    }
  end

  defp assign_per_action_state(socket) do
    verb_permissions = e(assigns(socket), :verb_permissions, %{})
    preset_boundary = e(assigns(socket), :preset_boundary, nil)
    my_circles = e(assigns(socket), :my_circles, [])
    sig = :erlang.phash2({verb_permissions, preset_boundary, my_circles})

    if sig == e(assigns(socket), :per_action_state_sig, nil) do
      socket
    else
      state =
        Bonfire.UI.Boundaries.PerActionDefaultsLive.build_states(
          verb_permissions,
          preset_boundary,
          my_circles
        )

      socket
      |> assign(:per_action_state, state)
      |> assign(:per_action_state_sig, sig)
    end
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
  def get_available_verbs(
        scope \\ nil,
        setting_boundaries \\ nil,
        include_verbs \\ nil,
        exclude_verbs \\ []
      ) do
    # WIP: list verbs appropriate for the each scope/context
    default_verbs =
      if setting_boundaries == :instance_acl or scope == :instance,
        do: [],
        else: default_verbs_for(:objects)

    # Start with either the specified include list, default verbs, or all verbs
    debug(default_verbs, "Default verbs for setting_boundaries")

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
      name =
        e(verb_config, :name, nil) ||
          e(verb_config, :verb, verb_slug |> to_string() |> String.capitalize())

      %{
        slug: verb_slug,
        icon: e(verb_config, :icon, "ph:circle-duotone"),
        name: name,
        summary: e(verb_config, :summary, l("Who can %{verb} the post", verb: name))
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

  # # Helper to detect and load custom ACL from to_boundaries
  # defp detect_custom_acl_from_to_boundaries(assigns, socket) do
  #   to_boundaries = e(assigns, :to_boundaries, [])
  #   current_user = current_user_required!(socket)

  #   with {:ok, acl_id} <- extract_acl_id_from_boundaries(to_boundaries),
  #        {:ok, verb_permissions, extracted_users} <- load_and_transform_acl(acl_id, current_user) do
  #     {:ok, verb_permissions, extracted_users}
  #   else
  #     error ->
  #       debug(error, "Custom ACL detection failed")
  #       :error
  #   end
  # end

  # # Extract ACL ID from to_boundaries if it contains a valid ULID
  # defp extract_acl_id_from_boundaries(to_boundaries) do
  #   acl_id =
  #     case to_boundaries do
  #       [{acl_id, _name}] when is_binary(acl_id) ->
  #         if Needle.ULID.valid?(acl_id), do: acl_id, else: nil

  #       [acl_id] when is_binary(acl_id) ->
  #         if Needle.ULID.valid?(acl_id), do: acl_id, else: nil

  #       _ ->
  #         nil
  #     end

  #   case acl_id do
  #     nil -> {:error, :no_acl_id}
  #     valid_id -> {:ok, valid_id}
  #   end
  # end

  # # Load ACL and transform to verb permissions format, also extracting users
  # defp load_and_transform_acl(acl_id, current_user) do
  #   case Bonfire.Boundaries.Acls.get_for_caretaker(acl_id, current_user) do
  #     {:ok, acl} ->
  #       transform_acl_to_verb_permissions(acl)

  #     error ->
  #       debug(error, "Failed to load ACL for caretaker")
  #       {:error, :acl_load_failed}
  #   end
  # end

  # # Transform ACL to verb permissions format with preloading and extract users
  # defp transform_acl_to_verb_permissions(acl) do
  #   # Preload grants
  #   acl_with_grants =
  #     acl
  #     |> repo().maybe_preload(
  #       [
  #         grants: [:verb, subject: [:named, :profile, :character, stereotyped: [:named]]]
  #       ],
  #       force: true
  #     )

  #   # Get grants for processing
  #   grants = e(acl_with_grants, :grants, [])

  #   # Extract users who are subjects in the grants (not circles/stereotypes)
  #   extracted_users = extract_users_from_grants(grants)

  #   # Transform to verb_permissions format
  #   acl_subject_verb_grants = Bonfire.Boundaries.Grants.subject_verb_grants(grants)

  #   {verb_permissions, _} =
  #     VerbPermissionsHelper.transform_acl_to_verb_format(acl_subject_verb_grants)

  #   {:ok, verb_permissions, extracted_users}
  # end

  # # Extract individual users from ACL grants (filtering out circles and stereotypes)
  # defp extract_users_from_grants(grants) do
  #   debug(grants, "Raw grants for user extraction")

  #   subjects =
  #     grants
  #     |> Enum.map(fn grant -> e(grant, :subject, nil) end)
  #     |> Enum.reject(&is_nil/1)

  #   debug(subjects, "All subjects from grants")

  #   user_subjects =
  #     subjects
  #     |> Enum.filter(&is_user_subject?/1)

  #   debug(user_subjects, "Filtered user subjects")

  #   unique_users =
  #     user_subjects
  #     |> Enum.uniq_by(&id/1)

  #   debug(unique_users, "Unique user subjects")

  #   formatted_users =
  #     unique_users
  #     |> Enum.map(&format_user_for_selected_list/1)

  #   debug(formatted_users, "Final formatted users")

  #   formatted_users
  # end

  # # Check if a subject is an individual user (not a circle or stereotype)
  # defp is_user_subject?(subject) do
  #   # Users have profile and character, but are not stereotyped circles
  #   has_profile = not is_nil(e(subject, :profile, nil))
  #   has_character = not is_nil(e(subject, :character, nil))
  #   is_not_stereotyped = is_nil(e(subject, :stereotyped, nil))

  #   debug(
  #     "Subject check - ID: #{id(subject)}, has_profile: #{has_profile}, has_character: #{has_character}, is_not_stereotyped: #{is_not_stereotyped}"
  #   )

  #   result = has_profile and has_character and is_not_stereotyped

  #   if not result do
  #     debug(subject, "Subject rejected as not a user")
  #   end

  #   result
  # end

  # # Format user from ACL subject to match selected_users format
  # defp format_user_for_selected_list(user) do
  #   %{
  #     id: id(user),
  #     name: e(user, :profile, :name, nil) || e(user, :named, :name, nil) || "Unnamed User",
  #     character: %{username: e(user, :character, :username, nil)},
  #     user_type: "permission_entry",
  #     username: e(user, :character, :username, nil)
  #   }
  # end

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
        # If verb_permissions are already there, no need to extract users from ACL
        {provided, []}

      _ ->
        if editing_acl?(e(assigns, :setting_boundaries, nil)) do
          load_acl_verb_permissions_and_users(assigns, socket)
        else
          # NOTE: For now we don't display permissions derived from the preset
          # load_boundary_verb_permissions_and_users(assigns, socket) || 
          {%{}, []}
        end
    end
  end

  # Load ACL verb permissions and extract users
  defp load_acl_verb_permissions_and_users(assigns, socket) do
    acl_subject_verb_grants = e(assigns, :acl_subject_verb_grants, nil)

    if acl_subject_verb_grants && acl_subject_verb_grants != %{} do
      {perms, _} = VerbPermissionsHelper.transform_acl_to_verb_format(acl_subject_verb_grants)
      # TODO: Extract users from acl_subject_verb_grants if needed
      {perms, []}
    else
      # case detect_custom_acl_from_to_boundaries(assigns, socket) do
      #   {:ok, verb_permissions, extracted_users} -> {verb_permissions, extracted_users}
      #   _ -> 
      {%{}, []}
      # end
    end
  end

  # # Load boundary verb permissions and extract users
  # defp load_boundary_verb_permissions_and_users(assigns, socket) do
  #   if preset_boundary = Bonfire.UI.Boundaries.SetBoundariesLive.boundaries_to_preset_name(assigns[:to_boundaries]) do
  #       # Preset boundaries don't have individual users, only circles
  #       verb_permissions = load_preset_verb_permissions(preset_boundary, assigns, socket)
  #       {verb_permissions, []}
  #    else
  #       case detect_custom_acl_from_to_boundaries(assigns, socket) do
  #         {:ok, verb_permissions, extracted_users} -> {verb_permissions, extracted_users}
  #         _ -> {reconstruct_from_circles(assigns), []}
  #       end
  #   end
  # end

  # defp load_preset_verb_permissions(preset_boundary, assigns, socket) do
  #   # Load preset's default circles and permissions
  #   preset_circles =
  #     Bonfire.UI.Boundaries.SetBoundariesLive.get_preset_circles_info(preset_boundary)

  #   # Expand roles to individual verbs
  #   preset_circles_with_verbs = expand_preset_roles_to_verbs(preset_circles)

  #   # Convert to verb permissions format
  #   preset_verb_permissions =
  #     VerbPermissionsHelper.reconstruct_verb_permissions(preset_circles_with_verbs, [])

  #   # Check if preset has changed - if so, start fresh
  #   current_preset = e(assigns(socket), :preset_boundary, nil)
  #   current_verb_permissions = e(assigns(socket), :verb_permissions, %{})

  #   if preset_changed?(current_preset, preset_boundary) do
  #     preset_verb_permissions
  #   else
  #     # Merge preset defaults with custom overrides
  #     merge_verb_permissions(preset_verb_permissions, current_verb_permissions)
  #   end
  # end

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
        "toggle_action_allowed",
        %{"action" => action_key, "allowed" => allowed?},
        socket
      ) do
    {verbs, current_verbs} = action_context(socket, action_key)
    preset_boundary = e(assigns(socket), :preset_boundary, nil)

    {updated_verbs, grants} =
      apply_action_toggle(allowed?, preset_boundary, verbs, current_verbs)

    socket =
      socket
      |> assign(:verb_permissions, persist_grants(socket, updated_verbs, grants))
      |> assign_per_action_state()

    {:noreply, socket}
  end

  @doc """
  Returns `{updated_verb_permissions, grants}` for a per-action toggle. `grants`
  is the list of `{circle_id, verb, value}` tuples to persist.
  """
  def apply_action_toggle(allowed?, preset_boundary, verbs, current_verb_permissions) do
    {mode, target_circle_ids} = toggle_targets(allowed?, preset_boundary, verbs)
    compute_action_mode_change(mode, verbs, target_circle_ids, current_verb_permissions)
  end

  # Toggling ON: if the preset already grants these verbs to someone, clearing
  # any user overrides is enough for the preset default to re-apply. If it
  # grants nothing (e.g. quote under public), clearing would just land back on
  # OFF — write explicit :can for the preset's read audience so the toggle
  # behaves as users expect ("allow quote for the public audience"). Fall back
  # to guest only when the preset has no discernible audience.
  defp toggle_targets(true, preset_boundary, verbs) do
    if Bonfire.UI.Boundaries.PerActionDefaultsLive.preset_grants_any?(preset_boundary, verbs) do
      {"same", []}
    else
      audience =
        Bonfire.UI.Boundaries.PerActionDefaultsLive.preset_audience_circle_ids(preset_boundary)

      targets =
        if audience == [],
          do: [Bonfire.Boundaries.Circles.get_id(:guest)],
          else: audience

      {"grant", targets}
    end
  end

  defp toggle_targets(false, preset_boundary, verbs) do
    {"nobody",
     Bonfire.UI.Boundaries.PerActionDefaultsLive.preset_block_circle_ids(preset_boundary, verbs)}
  end

  def handle_event(
        "toggle_action_exception",
        %{"action" => action_key, "circle_id" => circle_id},
        socket
      ) do
    {verbs, current_verbs} = action_context(socket, action_key)

    if is_nil(circle_id) or circle_id == "" or verbs == [] do
      {:noreply, socket}
    else
      already_granted? =
        Enum.all?(verbs, fn v ->
          Map.get(current_verbs, v, %{}) |> Map.get(circle_id) == :can
        end)

      new_value = if already_granted?, do: nil, else: :can

      updated_verbs =
        Enum.reduce(verbs, current_verbs, fn verb, acc ->
          VerbPermissionsHelper.update_verb_permission(acc, circle_id, verb, new_value)
        end)

      grants = Enum.map(verbs, fn v -> {circle_id, v, new_value} end)

      socket =
        socket
        |> assign(:verb_permissions, persist_grants(socket, updated_verbs, grants))
        |> assign_per_action_state()

      {:noreply, socket}
    end
  end

  def handle_event("save_and_close", _params, socket) do
    Bonfire.UI.Common.OpenModalLive.close("persistent_modal")
    {:noreply, socket}
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

  defp action_context(socket, action_key) do
    {Bonfire.UI.Boundaries.PerActionDefaultsLive.verbs_for(action_key),
     e(assigns(socket), :verb_permissions, %{})}
  end

  defp compute_action_mode_change("same", verbs, _block_ids, current_verbs) do
    updated = Enum.reduce(verbs, current_verbs, fn v, acc -> Map.delete(acc, v) end)

    grants =
      Enum.flat_map(verbs, fn v ->
        Map.get(current_verbs, v, %{})
        |> Enum.map(fn {cid, _val} -> {cid, v, nil} end)
      end)

    {updated, grants}
  end

  # "nobody" writes :cannot for every circle the preset would otherwise grant
  # `:can` to (guest + locals/fediverse on a public preset, etc.) — otherwise
  # those implicit preset grants stay in effect and toggling the action OFF
  # only blocks strangers while locals keep replying. Other existing grants on
  # the same verb are cleared so stale :can entries don't leak back through.
  defp compute_action_mode_change("nobody", verbs, block_ids, current_verbs)
       when is_list(block_ids) and block_ids != [] do
    blocks_map = Map.new(block_ids, fn cid -> {cid, :cannot} end)

    updated =
      Enum.reduce(verbs, current_verbs, fn v, acc ->
        Map.put(acc, v, blocks_map)
      end)

    grants =
      Enum.flat_map(verbs, fn v ->
        previous = Map.get(current_verbs, v, %{})
        blocks = Enum.map(block_ids, fn cid -> {cid, v, :cannot} end)

        clears =
          previous
          |> Map.drop(block_ids)
          |> Enum.map(fn {cid, _val} -> {cid, v, nil} end)

        blocks ++ clears
      end)

    {updated, grants}
  end

  # "grant" writes :can for each target circle on the action's verbs, clearing
  # any other existing grants on those verbs so a previous "nobody" :cannot
  # flip doesn't leak through and keep the action blocked.
  defp compute_action_mode_change("grant", verbs, target_ids, current_verbs)
       when is_list(target_ids) and target_ids != [] do
    grants_map = Map.new(target_ids, fn cid -> {cid, :can} end)

    updated =
      Enum.reduce(verbs, current_verbs, fn v, acc ->
        Map.put(acc, v, grants_map)
      end)

    grants =
      Enum.flat_map(verbs, fn v ->
        previous = Map.get(current_verbs, v, %{})
        sets = Enum.map(target_ids, fn cid -> {cid, v, :can} end)

        clears =
          previous
          |> Map.drop(target_ids)
          |> Enum.map(fn {cid, _val} -> {cid, v, nil} end)

        sets ++ clears
      end)

    {updated, grants}
  end

  defp compute_action_mode_change(_, _, _, current_verbs), do: {current_verbs, []}

  defp persist_grants(socket, updated_verbs, grants) do
    if editing_acl?(e(assigns(socket), :setting_boundaries, nil)) do
      Enum.reduce(grants, updated_verbs, fn {cid, verb, val}, acc ->
        case update_acl_mode_permissions(socket, cid, verb, val, acc) do
          {:ok, v} -> v
          _ -> acc
        end
      end)
    else
      update_boundary_mode_permissions(socket, updated_verbs)
    end
  end
end
