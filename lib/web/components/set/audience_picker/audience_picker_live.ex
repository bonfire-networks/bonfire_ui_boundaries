defmodule Bonfire.UI.Boundaries.AudiencePickerLive do
  @moduledoc """
  The composer's searchable "Post in" (`:destination`) and "Visible to" (`:visibility`) menus. Like the user menu's profile switcher, nothing is queried on render: the trigger pushes `load` when the menu is first opened.
  """
  use Bonfire.UI.Common.Web, :stateful_component

  @group_limit 20

  slot default
  prop to_circles, :list, default: []

  # `:destination` picks where to post (profile or a joined group), `:visibility` who can see a personal post
  prop mode, :atom, required: true, values: [:destination, :visibility]
  prop to_boundaries, :any, default: []
  prop exclude_circles, :list, default: []
  prop verb_permissions, :map, default: %{}
  prop context_group, :any, default: nil
  prop event_target, :any, default: "#smart_input"

  # nil until the menu is first opened
  data audiences, :list, default: nil
  data my_circles, :list, default: nil
  data search_term, :string, default: ""
  data options, :list, default: []
  data circles, :list, default: []
  data groups, :list, default: []
  data more_groups?, :boolean, default: false

  def handle_event("load", _params, %{assigns: %{audiences: nil}} = socket) do
    {audiences, my_circles} =
      if socket.assigns.mode == :visibility do
        presets =
          for slug <- Bonfire.Boundaries.Presets.preset_order(),
              do: {slug, Bonfire.Boundaries.Presets.for_preset(slug)}

        {presets ++ Bonfire.Boundaries.LiveHandler.my_acls(current_user_id(socket)),
         if(current_user_id(socket),
           do:
             Bonfire.Boundaries.Circles.list_my_for_sidebar(current_user(socket),
               exclude_stereotypes: true
             ),
           else: []
         )}
      else
        {[], []}
      end

    {:noreply,
     socket
     |> assign(audiences: audiences, my_circles: my_circles)
     |> search(socket.assigns.search_term)}
  end

  def handle_event("load", _params, socket), do: {:noreply, socket}

  def handle_event("search", %{"search" => term}, socket), do: {:noreply, search(socket, term)}

  @doc "Whether a circle is among the composer's `to_circles` (entries may be `{circle, role}` or bare circles)."
  def circle_selected?(to_circles, circle_id) do
    Enum.any?(to_circles || [], fn
      {selected, _role} -> id(selected) == circle_id
      selected -> id(selected) == circle_id
    end)
  end

  # Filters the loaded audience metadata and circles, and searches joined groups the user may post in.
  defp search(socket, term) do
    term = String.trim(term)
    needle = String.downcase(term)
    matches? = &(&1 |> String.downcase() |> String.contains?(needle))

    options =
      Enum.filter(socket.assigns.audiences || [], fn {_id, meta} ->
        matches?.(e(meta, :label, nil) || e(meta, :name, ""))
      end)

    circles = Enum.filter(socket.assigns.my_circles || [], &matches?.(e(&1, :named, :name, "")))

    groups =
      if socket.assigns.mode == :destination and
           module_enabled?(Bonfire.Classify.Categories, socket) and
           not is_nil(current_user_id(socket)) do
        Bonfire.Classify.Categories.list_joined_groups(
          current_user(socket),
          search: term,
          verbs: [:create],
          pagination: %{limit: @group_limit}
        )
        |> e(:edges, [])
      else
        []
      end

    assign(socket,
      search_term: term,
      options: options,
      circles: circles,
      groups: groups,
      more_groups?: length(groups) == @group_limit
    )
  end
end
