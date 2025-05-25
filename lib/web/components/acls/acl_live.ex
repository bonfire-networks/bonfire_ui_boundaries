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
  prop setting_boundaries, :boolean, default: false
  prop scope, :any, default: nil
  prop usage, :any, default: :all
  prop type, :atom, default: nil

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

    global_circles = Bonfire.Boundaries.Scaffold.Instance.global_circles()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       scope_type: scope_type,
       section: e(params, "section", "permissions"),
       #  verbs: verbs,
       acl_id: acl_id,
       #  suggestions: suggestions,
       global_circles: global_circles,
       my_circles:
         Bonfire.UI.Boundaries.SetBoundariesLive.list_my_circles(
           if is_nil(scope), do: current_user, else: scope
         )
         |> Bonfire.UI.Boundaries.SetBoundariesLive.results_for_multiselect(),
       settings_section_title: "View boundary preset",
       settings_section_description: l("Create and manage your boundary preset."),
       selected_tab: "acls"
     )
     |> assign_updated()}
  end

  def assign_updated(socket, force? \\ false) do
    current_user = current_user(socket)

    acl_id = e(assigns(socket), :acl_id, nil)
    acl = e(assigns(socket), :acl, nil)
    acl = if id(acl) == acl_id, do: {:ok, acl}

    read_only =
      (Acls.is_built_in?(acl) and
         id(acl) == Bonfire.Boundaries.Scaffold.Instance.instance_acl()) or
        (!Acls.is_object_custom?(acl) and
           (Acls.is_stereotyped?(acl) and
              !Bonfire.Boundaries.can?(assigns(socket)[:__context__], :grant, :instance)))

    with {:ok, acl} <-
           (acl || Acls.get_for_caretaker(acl_id, current_user))
           |> repo().maybe_preload(
             [
               grants: [
                 :verb,
                 subject: [:named, :profile, :character, stereotyped: [:named]]
               ]
             ],
             force: force?
           ) do
      debug(acl, "acllll")

      if (socket_connected?(socket) && !e(assigns(socket), :setting_boundaries, nil)) and
           e(assigns(socket), :scope_type, nil) not in [:group, Bonfire.Classify.Category] do
        send_self(
          back: true,
          page_title: e(acl, :named, :name, nil) || e(acl, :stereotyped, :named, :name, nil),
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

      # verbs = e(assigns(socket), :verbs, [])

      feed_by_subject = Grants.subject_verb_grants(e(acl, :grants, []))
      # list_by_verb = verb_subject_grant(e(acl, :grants, []))
      socket
      |> assign(
        loaded: true,
        settings_section_title: "View " <> e(acl, :named, :name, "") <> " boundary",
        acl: acl,
        feed_by_subject: feed_by_subject,
        # list_by_verb: Map.merge(verbs, list_by_verb),
        # subjects: subjects(e(acl, :grants, [])),
        read_only: read_only
      )
    end
  end

  # def handle_event("edit", attrs, socket) do
  #   debug(attrs)

  #   with {:ok, acl} <-
  #          Acls.edit(e(assigns(socket), :acl, nil), current_user_required!(socket), attrs) do
  #     send_self(page_title: e(acl, :named, :name, nil))
  #      {:noreply,
  #      socket
  #      |> assign_flash(:info, l("Edited!"))
  #      |> assign(show: false)
  #      |> assign(acl: acl)}
  #   else
  #     other ->
  #       error(other)

  #       {:noreply, assign_flash(socket, :error, l("Could not edit boundary"))}
  #   end
  # end

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

  def handle_event("remove_from_acl", %{"subject_id" => subject}, socket) do
    remove_from_acl(subject, socket)
  end

  def handle_event("tagify_remove", %{"id" => subject} = _attrs, socket) do
    remove_from_acl(subject, socket)
  end

  def handle_event("tagify_add", %{"id" => id} = _attrs, socket) do
    add_to_acl(id, socket)
  end

  def handle_event("select", %{"id" => id} = _attrs, socket) do
    add_to_acl(id, socket)
  end

  def handle_event("multi_select", %{data: data}, socket) do
    add_to_acl(data, socket)
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
    with [ok: grant] <- grant do
      debug(grant)

      {
        :noreply,
        socket
        |> assign_flash(:info, l("Permission edited!"))
        |> assign_updated(true)

        # |> assign(
        # list: Map.merge(e(assigns(socket), :list, %{}), %{id=> %{subject: %{name: e(assigns(socket), :suggestions, id, nil)}}}) #|> debug
        # )
      }
    else
      other ->
        error(other)

        {:noreply, assign_error(socket, l("Could not edit permission"))}
    end
  end

  def handle_event("edit_grant_role", %{"to_circles" => subjects} = attrs, socket) do
    current_user = current_user_required!(socket)
    acl = e(assigns(socket), :acl, nil)
    scope = e(assigns(socket), :scope, nil)

    granted =
      Enum.map(subjects, fn {subject_id, role_name} ->
        Grants.change_role(subject_id, acl, role_name, current_user: current_user, scope: scope)
      end)
      |> debug("done")

    if Enums.all_ok?(granted) do
      {
        :noreply,
        socket
        |> assign_flash(:info, l("Role assigned!"))
        |> assign_updated(true)
        # |> assign(
        # list: Map.merge(e(assigns(socket), :list, %{}), %{id=> %{subject: %{name: e(assigns(socket), :suggestions, id, nil)}}}) #|> debug
        # )
      }
    else
      error(granted, "Could not grant role")

      {:noreply, assign_error(socket, l("Could not assign the role"))}
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

  def handle_event(
        "live_select_change",
        %{"id" => live_select_id, "text" => search},
        %{assigns: %{scope: :instance}} = socket
      ) do
    (Bonfire.Boundaries.Circles.list_my_with_global(
       [
         Bonfire.Boundaries.Scaffold.Instance.admin_circle(),
         Bonfire.Boundaries.Scaffold.Instance.activity_pub_circle()
       ],
       search: search
     ) ++
       Utils.maybe_apply(
         Bonfire.Me.Users,
         :search,
         [search]
       ))
    |> results_for_multiselect(live_select_id, socket)
  end

  def handle_event(
        "live_select_change",
        %{"id" => live_select_id, "text" => search},
        %{assigns: %{scope: %schema{}}} = socket
      )
      when schema == Bonfire.Classify.Category do
    # current_user = current_user(socket)
    # for groups and the like
    # TODO: should they have their own circles?
    (Bonfire.Boundaries.Circles.list_my_with_global(
       [Bonfire.Boundaries.Scaffold.Instance.activity_pub_circle()],
       search: search
     ) ++
       Utils.maybe_apply(
         Bonfire.Me.Users,
         :search,
         [search]
       ))
    |> results_for_multiselect(live_select_id, socket)
  end

  def handle_event(
        "live_select_change",
        %{"id" => live_select_id, "text" => search},
        socket
      ) do
    current_user = current_user(socket)

    (Bonfire.Boundaries.Circles.list_my_with_global(
       [current_user, Bonfire.Boundaries.Scaffold.Instance.activity_pub_circle()],
       search: search
     ) ++
       Utils.maybe_apply(
         Bonfire.Me.Users,
         :search,
         [search]
       ))
    |> results_for_multiselect(live_select_id, socket)
  end

  defp results_for_multiselect(results, live_select_id, socket) do
    results
    |> Bonfire.UI.Boundaries.SetBoundariesLive.results_for_multiselect()
    |> debug()

    # |> maybe_send_update(LiveSelect.Component, live_select_id, options: ...)
    # FIXME! creates an infinite loop

    {:noreply, socket}
  end

  def add_to_acl(id, socket) when is_binary(id) do
    {:noreply,
     do_add_to_acl(
       %{
         id: id
       },
       socket
     )}
  end

  def add_to_acl(subject, socket) do
    {:noreply, do_add_to_acl(subject, socket)}
  end

  defp do_add_to_acl(subject, socket) do
    id = uid(subject)
    # |> debug("id")

    subject_map = %{id => %{subject: subject, grants: nil}}

    # subject_name = LiveHandler.subject_name(subject)
    # |> debug("name")

    socket
    |> assign(
      # subjects: ([subject] ++ e(assigns(socket), :subjects, [])) |> Enum.uniq_by(&uid/1),
      # so tagify doesn't remove it as invalid
      # suggestions: Map.put(e(assigns(socket), :suggestions, %{}), id, subject_name),
      feed_by_subject: e(assigns(socket), :feed_by_subject, %{}) |> Map.merge(subject_map)
      # list_by_verb:
      #   e(assigns(socket), :list_by_verb, %{})
      #   |> Enum.map(fn
      #     {verb_id, %{verb: verb, subject_verb_grants: subject_verb_grants}} ->
      #       {
      #         verb_id,
      #         %{
      #           verb: verb,
      #           subject_verb_grants: Map.merge(subject_verb_grants, subject_map)
      #         }
      #       }

      #     {verb_id, %Bonfire.Data.AccessControl.Verb{} = verb} ->
      #       {
      #         verb_id,
      #         %{
      #           verb: verb,
      #           subject_verb_grants: subject_map
      #         }
      #       }
      #   end)
      #   # |> debug
      #   |> Map.new()

      # list: Map.merge(e(assigns(socket), :list, %{}), %{id=> %{subject: %{name: e(assigns(socket), :suggestions, id, nil)}}}) #|> debug
    )
    |> assign_flash(
      :info,
      l("Select a role (or custom permissions) to finish adding it to the boundary.")
    )

    # |> assign_updated()
  end

  def remove_from_acl(subject, socket) do
    # IO.inspect(subject, label: "ULLID")
    acl_id = uid!(e(assigns(socket), :acl, nil))
    # subject_id = uid!(subject)

    {:noreply,
     with {del, _} when is_integer(del) and del > 0 <-
            Grants.remove_subject_from_acl(subject, acl_id) do
       Bonfire.UI.Common.OpenModalLive.close()

       assign_flash(socket, :info, l("Removed from boundary"))
       |> assign_updated(true)

       # |> redirect_to(~p"/boundaries/acl/#{id}")
     else
       _ ->
         assign_flash(socket, :info, l("No permissions removed from boundary"))
     end}
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
end
