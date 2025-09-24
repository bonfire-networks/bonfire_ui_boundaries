defmodule Bonfire.UI.Boundaries.AclLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Grants
  alias Bonfire.Boundaries.LiveHandler
  # alias Bonfire.Boundaries.Integration
  require Integer

  prop acl_id, :string, default: nil
  prop edit_circle_id, :string, default: nil
  prop parent_back, :any, default: nil
  prop columns, :integer, default: 1
  prop selected_tab, :any, default: nil
  prop section, :any, default: nil
  prop setting_boundaries, :atom, default: nil
  prop scope, :any, default: nil
  prop usage, :any, default: :all
  prop type, :atom, default: nil
  prop title, :string, default: nil
  prop description, :string, default: nil
  prop show_general_boundary, :boolean, default: false
  prop to_boundaries, :any, default: nil
  prop to_circles, :list, default: []
  prop exclude_circles, :list, default: []

  def update(assigns, %{assigns: %{loaded: true}} = socket) do
    params = e(assigns, :__context__, :current_params, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(section: e(params, "section", "permissions"))}
  end

  def update(assigns, socket) do
    current_user = current_user(assigns) || current_user(socket)
    params = e(assigns, :__context__, :current_params, %{})

    acl_id = e(assigns, :acl_id, nil) || e(assigns(socket), :acl_id, nil) || e(params, "id", nil)
    scope = e(assigns, :scope, nil) || e(assigns(socket), :scope, nil)

    scope_type = Types.object_type(scope) || scope

    # note: Verbs only needed if doing custom permissions rather than using roles
    # verbs = Bonfire.Boundaries.Verbs.list(:db, :id)
    # verbs =
    #   if scope != :instance do
    #     # filter out instance-related roles (to show only content related ones)
    #
    #     instance_verbs =
    #       Bonfire.Boundaries.Verbs.list(:instance, :id)
    #       |> debug

    #     verbs
    #     |> Enum.reject(&(elem(&1, 0) in instance_verbs))
    #     |> debug
    #   else
    #     verbs
    #   end

    # global_circles = Bonfire.Boundaries.Scaffold.Instance.global_circles()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       scope_type: scope_type,
       section: e(params, "section", "permissions"),
       acl_id: acl_id,
       my_circles:
         Bonfire.UI.Boundaries.CustomizeBoundaryLive.fetch_my_circles_with_global(
           current_user(socket)
         ),
       settings_section_title: "View boundary preset",
       settings_section_description: l("Create and manage your boundary preset."),
       selected_tab: "acls"
     )
     |> assign_updated()}
  end

  def assign_updated(socket, force? \\ false) do
    current_user = current_user(socket)
    acl_id = e(assigns(socket), :acl_id, nil)

    case load_acl(socket, acl_id, current_user, force?) do
      {:ok, acl} ->
        read_only = determine_read_only_status(acl, socket)
        maybe_send_page_updates(socket, acl, acl_id, read_only)

        acl_subject_verb_grants = Grants.subject_verb_grants(e(acl, :grants, []))
        debug(acl_subject_verb_grants, "Processed acl_subject_verb_grants")

        assign_acl_data(socket, acl, acl_subject_verb_grants, read_only)

      {:error, reason} ->
        error(reason, "Failed to load ACL")
        assign_error(socket, l("Could not load boundary"))
    end
  end

  # Load ACL with caching and preloading
  defp load_acl(socket, acl_id, current_user, force?) do
    cached_acl = e(assigns(socket), :acl, nil)

    # Use cached ACL if it matches the requested ID, otherwise fetch fresh
    acl_result =
      if id(cached_acl) == acl_id do
        {:ok, cached_acl}
      else
        Acls.get_for_caretaker(acl_id, current_user)
      end

    case acl_result do
      {:ok, acl} ->
        preloaded_acl =
          acl
          |> repo().maybe_preload(
            [
              grants: [
                :verb,
                subject: [:named, :profile, :character, stereotyped: [:named]]
              ]
            ],
            force: force?
          )

        {:ok, preloaded_acl}

      error ->
        error
    end
  end

  # Determine if ACL should be read-only
  defp determine_read_only_status(acl, socket) do
    (Acls.is_built_in?(acl) and
       id(acl) == Bonfire.Boundaries.Scaffold.Instance.instance_acl()) or
      (!Acls.is_object_custom?(acl) and
         (Acls.is_stereotyped?(acl) and
            !Bonfire.Boundaries.can?(assigns(socket)[:__context__], :grant, :instance)))
  end

  # Send page updates if conditions are met
  defp maybe_send_page_updates(socket, acl, acl_id, read_only) do
    if (socket_connected?(socket) && !e(assigns(socket), :setting_boundaries, nil)) and
         e(assigns(socket), :scope_type, nil) not in [:group, Bonfire.Classify.Category] do
      send_self(
        back: true,
        page_title:
          e(assigns(socket), :title, nil) || e(acl, :named, :name, nil) ||
            e(acl, :stereotyped, :named, :name, nil),
        acl: acl,
        page_header_aside: [
          {Bonfire.UI.Boundaries.EditAclButtonLive,
           [
             acl: acl,
             read_only: read_only,
             acl_id: acl_id
           ]}
        ]
      )
    end
  end

  # Assign ACL data to socket
  defp assign_acl_data(socket, acl, acl_subject_verb_grants, read_only) do
    socket
    |> assign(
      loaded: true,
      settings_section_title: "View " <> e(acl, :named, :name, "") <> " boundary",
      acl: acl,
      acl_subject_verb_grants: acl_subject_verb_grants,
      read_only: read_only
    )
  end

  def handle_event("add_to_acl", %{"id" => id, "name" => name} = _attrs, socket) do
    subject = %{
      id: id,
      name: name
    }

    add_to_acl(subject, socket)
  end

  def handle_event("add_to_acl", %{"id" => id} = _attrs, socket) do
    add_to_acl(id, socket)
  end

  def handle_event("edit_verb_value", %{"subject" => subjects} = _attrs, socket) do
    # debug(attrs)
    current_user = current_user_required!(socket)
    acl = e(assigns(socket), :acl, nil)
    # verb_value = List.first(Map.values(subjects))
    grant =
      Enum.flat_map(subjects, fn {subject_id, verb_value} ->
        Enum.flat_map(verb_value, fn {verb, value} ->
          debug(acl, "#{subject_id} -- #{verb} = #{value}")

          [
            Grants.grant(subject_id, acl, verb, value, current_user: current_user)
          ]
        end)
      end)

    # |> debug("done")
    # Check results - handle multiple grants with mixed success/failure
    {successes, failures} =
      Enum.split_with(grant, fn
        {:ok, _} -> true
        _ -> false
      end)

    case {successes, failures} do
      {[], _} ->
        # All failed
        error(failures, "All permission updates failed")
        {:noreply, assign_error(socket, l("Could not edit permission"))}

      {_, []} ->
        # All succeeded
        debug(successes, "All permission updates succeeded")

        {
          :noreply,
          socket
          |> assign_flash(:info, l("Permission edited!"))
          |> assign_updated(true)
        }

      {_, _} ->
        # Mixed results
        debug({successes, failures}, "Mixed permission update results")

        {
          :noreply,
          socket
          |> assign_flash(:info, l("Some permissions edited successfully"))
          |> assign_updated(true)
        }
    end
  end

  def handle_event("edit_circle", %{"id" => id}, socket) do
    debug(id, "circle_edit")

    {:noreply, assign(socket, :edit_circle_id, id)}
  end

  # TODO
  def handle_event("back", _, socket) do
    {:noreply,
     assign(
       socket,
       edit_circle_id: nil,
       section: nil
     )}
  end

  # Handle preset changes from CustomizeBoundaryLive
  def handle_event("change_acl_preset", %{"id" => preset_id}, socket) do
    # TODO: Apply preset template to current ACL when function is available
    debug(preset_id, "preset_id to apply")

    {:noreply,
     socket
     |> assign_flash(:info, l("Preset change not yet implemented"))}
  end

  def add_to_acl(id, socket) when is_binary(id) do
    add_to_acl(%{id: id}, socket)
  end

  def add_to_acl(subject, socket) do
    {:noreply, do_add_to_acl(subject, socket)}
  end

  defp do_add_to_acl(subject, socket) do
    id = uid(subject)
    subject_map = %{id => %{subject: subject, grants: nil}}

    socket
    |> assign(
      acl_subject_verb_grants:
        e(assigns(socket), :acl_subject_verb_grants, %{}) |> Map.merge(subject_map)
    )
    |> assign_flash(
      :info,
      l("Select a role (or custom permissions) to finish adding it to the boundary.")
    )
  end

  def remove_from_acl(subject, socket) do
    acl_id = uid!(e(assigns(socket), :acl, nil))

    case Grants.remove_subject_from_acl(subject, acl_id) do
      {del, _} when is_integer(del) and del > 0 ->
        Bonfire.UI.Common.OpenModalLive.close()

        {:noreply,
         socket
         |> assign_flash(:info, l("Removed from boundary"))
         |> assign_updated(true)}

      {0, _} ->
        {:noreply, assign_flash(socket, :info, l("No permissions removed from boundary"))}

      {:error, reason} ->
        error(reason, "Failed to remove subject from ACL")
        {:noreply, assign_error(socket, l("Could not remove from boundary"))}
    end
  end

  def can(grants) do
    grants
    |> Enum.filter(fn {_, grant} -> e(grant, :value, nil) == true end)
    |> Enum.map(fn {_, grant} ->
      e(grant, :verb, :verb, nil) || e(grant, :verb, nil)
    end)

    # |> maybe_join(l "Can")
  end

  def cannot(grants) do
    grants
    # |> debug
    |> Enum.filter(fn {_, grant} ->
      is_map(grant) and Map.get(grant, :value, nil) == false
    end)
    |> Enum.map(fn {_, grant} ->
      e(grant, :verb, :verb, nil) || e(grant, :verb, nil)
    end)

    # |> maybe_join(l "Cannot")
  end

  def maybe_join(list, prefix) when is_list(list) and length(list) > 0 do
    prefix <> ": " <> Enum.join(list, ", ")
  end

  def maybe_join(_, _) do
    nil
  end

  # def columns(context) do
  #  if context[:ui_compact], do: 3, else: 2
  # end

  def predefined_subjects(subjects) do
    Enum.map(subjects, fn s ->
      %{"value" => uid(s), "text" => LiveHandler.subject_name(s) || uid(s)}
    end)
    # |> Enum.join(", ")
    |> Jason.encode!()

    # |> debug()
    # [{"value":"good", "text":"The Good, the Bad and the Ugly"}, {"value":"matrix", "text":"The Matrix"}]
  end

  def circle_member_count(subject) do
    if Types.object_type(subject) == Bonfire.Data.AccessControl.Circle do
      Bonfire.Boundaries.Circles.count_members(id(subject))
    end
  end
end
