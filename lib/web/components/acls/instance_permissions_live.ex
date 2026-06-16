defmodule Bonfire.UI.Boundaries.InstancePermissionsLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Grants
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Verbs

  prop acl, :any, default: nil
  prop scope, :any, default: nil
  prop can_edit, :boolean, default: false

  @capabilities [
    %{key: :moderate, icon: "ph:shield-check-duotone", verbs: [:mediate, :block]},
    %{key: :invite, icon: "ph:gift-duotone", verbs: [:invite]},
    %{key: :curate, icon: "ph:pencil-line-duotone", verbs: [:describe]},
    %{key: :configure, icon: "ph:sliders-duotone", verbs: [:configure, :toggle]},
    %{key: :grant_roles, icon: "ph:key-duotone", verbs: [:grant, :assign]}
  ]

  def capabilities, do: @capabilities

  def capability_label(:moderate), do: l("Moderate")
  def capability_label(:invite), do: l("Invite members")
  def capability_label(:curate), do: l("Edit info & metadata")
  def capability_label(:configure), do: l("Configure the instance")
  def capability_label(:grant_roles), do: l("Grant roles & permissions")

  def capability_summary(:moderate),
    do: l("See flags, mediate disputes, and manage blocks, ghosts and silences")

  def capability_summary(:invite), do: l("Invite new people and grant them entry to the instance")

  def capability_summary(:curate),
    do: l("Edit info and metadata across the instance, such as thread titles")

  def capability_summary(:configure),
    do: l("Change instance settings and enable or disable features")

  def capability_summary(:grant_roles),
    do: l("Add, edit or remove boundaries and assign roles to others")

  def capability_label(key), do: key |> to_string() |> String.replace("_", " ")
  def capability_summary(_key), do: ""

  def update(assigns, socket) do
    socket = assign(socket, assigns) |> assign_new(:edit_mode, fn -> false end)
    acl_id = id(e(assigns, :acl, nil))

    cond do
      # Defer the grants preload + instance-circles query until the LiveView
      # connects: the capability matrix isn't useful on the disconnected/static
      # render, and the load would otherwise run twice per page view. Provide
      # empty defaults (without setting loaded_acl_id) so the template renders
      # and the real load still runs on the connected mount.
      not connected?(socket) ->
        {:ok,
         socket
         |> assign_new(:audiences, fn -> [] end)
         |> assign_new(:capabilities_with_ids, fn -> [] end)}

      acl_id == e(assigns(socket), :loaded_acl_id, nil) and e(assigns(socket), :audiences, nil) ->
        {:ok, socket}

      true ->
        {:ok, socket |> assign(:loaded_acl_id, acl_id) |> assign_capability_state()}
    end
  end

  defp assign_capability_state(socket) do
    acl =
      e(assigns(socket), :acl, nil)
      |> repo().maybe_preload(
        [grants: [:verb, subject: [:named, :profile, :character, stereotyped: [:named]]]],
        force: true
      )

    subject_verb_grants = Grants.subject_verb_grants(e(acl, :grants, []))
    caps_with_ids = capabilities_with_verb_ids()

    socket
    |> assign(
      acl: acl,
      audiences: build_audiences(caps_with_ids, subject_verb_grants),
      capabilities_with_ids: caps_with_ids
    )
  end

  defp capabilities_with_verb_ids do
    Enum.map(@capabilities, fn capability ->
      verb_ids =
        capability.verbs
        |> Enum.map(&Verbs.get_id/1)
        |> Enum.reject(&is_nil/1)

      Map.put(capability, :verb_ids, verb_ids)
    end)
  end

  defp build_audiences(caps_with_ids, subject_verb_grants) do
    standard = standard_audiences()
    instance_circles = instance_candidate_circles()

    base = uniq_audiences(standard ++ instance_circles)
    base_ids = Enum.map(base, & &1.id)

    granted_extras =
      subject_verb_grants
      |> Map.values()
      |> Enum.reject(fn entry -> id(e(entry, :subject, nil)) in base_ids end)
      |> Enum.map(&audience_from_subject(e(&1, :subject, nil)))
      |> Enum.reject(&is_nil(&1.id))

    public_ids = public_circle_ids()

    uniq_audiences(base ++ granted_extras)
    |> Enum.map(fn audience ->
      Map.put(
        audience,
        :states,
        capability_states(caps_with_ids, subject_verb_grants, audience.id)
      )
    end)
    |> Enum.reject(fn audience ->
      audience.id in public_ids and Enum.all?(Map.values(audience.states), &(&1 == :off))
    end)
  end

  defp public_circle_ids do
    [Circles.get_id(:guest), Circles.get_id(:activity_pub)]
    |> Enum.reject(&is_nil/1)
  end

  defp uniq_audiences(audiences), do: Enum.uniq_by(audiences, & &1.id)

  defp audience_from_subject(subject) do
    %{
      id: id(subject),
      name: Bonfire.UI.Boundaries.AclAudienceSummaryLive.subject_name(subject),
      icon: Bonfire.UI.Boundaries.AclAudienceSummaryLive.subject_icon(subject),
      is_user: Bonfire.UI.Boundaries.AclAudienceSummaryLive.is_user?(subject)
    }
  end

  defp instance_candidate_circles do
    admin_circle = Bonfire.Boundaries.Scaffold.Instance.admin_circle()

    excluded =
      [admin_circle, Circles.get_id(:guest), Circles.get_id(:activity_pub)]
      |> Enum.reject(&is_nil/1)

    Circles.list_my_with_global(admin_circle,
      exclude_block_stereotypes: true,
      exclude_circles: excluded
    )
    |> Enum.map(&audience_from_subject/1)
    |> Enum.reject(fn audience -> is_nil(audience.id) or audience.id in excluded end)
  rescue
    error ->
      warn(error, "Could not list instance circles for permissions")
      []
  end

  defp standard_audiences do
    [:mod, :local]
    |> Enum.map(&Circles.get_built_in/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn circle ->
      %{
        id: e(circle, :id, nil),
        name: e(circle, :name, nil),
        icon: e(circle, :icon, "ph:circle-duotone"),
        is_user: false
      }
    end)
    |> Enum.reject(&is_nil(&1.id))
  end

  defp capability_states(caps_with_ids, subject_verb_grants, subject_id) do
    grants = e(subject_verb_grants, subject_id, :grants, %{})

    Map.new(caps_with_ids, fn capability ->
      {capability.key, capability_state(grants, capability.verb_ids)}
    end)
  end

  defp capability_state(_grants, []), do: :off

  defp capability_state(grants, verb_ids) do
    granted =
      Enum.count(verb_ids, fn verb_id ->
        e(grants, verb_id, :value, nil) == true
      end)

    cond do
      granted == 0 -> :off
      granted == length(verb_ids) -> :on
      true -> :partial
    end
  end

  def handle_event("toggle_edit", _params, socket) do
    {:noreply, assign(socket, :edit_mode, !e(assigns(socket), :edit_mode, false))}
  end

  def handle_event(
        "toggle_capability",
        %{"audience" => subject_id, "capability" => capability_key},
        socket
      ) do
    with true <- e(assigns(socket), :can_edit, false) || {:error, :not_allowed},
         true <-
           Bonfire.Boundaries.can?(e(assigns(socket), :__context__, nil), :grant, :instance) ||
             {:error, :not_allowed},
         current_user when not is_nil(current_user) <- current_user(socket),
         capability when not is_nil(capability) <-
           Enum.find(@capabilities, &(to_string(&1.key) == capability_key)),
         acl when not is_nil(acl) <- e(assigns(socket), :acl, nil) do
      current =
        e(assigns(socket), :audiences, [])
        |> Enum.find(%{}, &(&1.id == subject_id))
        |> e(:states, capability.key, :off)

      new_value = if current == :off, do: true, else: nil

      results =
        Grants.grant(subject_id, acl, capability.verbs, new_value, current_user: current_user)
        |> List.wrap()

      if Enum.any?(results, &match?({:error, _}, &1)) do
        error(results, "Some instance permission grants failed")
        {:noreply, assign_error(socket, l("Could not update instance permissions"))}
      else
        {:noreply,
         socket
         |> assign_flash(:info, l("Instance permissions updated"))
         |> assign_capability_state()}
      end
    else
      _ ->
        {:noreply, assign_error(socket, l("You don't have permission to change this"))}
    end
  end
end
