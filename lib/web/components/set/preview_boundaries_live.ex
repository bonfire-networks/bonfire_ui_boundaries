defmodule Bonfire.UI.Boundaries.PreviewBoundariesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  use Bonfire.Common.Utils
  # alias Bonfire.Boundaries.Roles

  # declare_module_optional(l("Preview boundaries in composer"),
  #   description:
  #     l(
  #       "Adds a button to calculate and display how boundaries will be applied for a specific user."
  #     )
  # )

  prop preview_boundary_for_id, :any, default: nil
  prop preview_boundary_for_username, :any, default: nil
  prop preview_boundary_verbs, :any, default: nil

  prop to_boundaries, :any, default: nil
  prop boundary_preset, :any, default: nil
  prop to_circles, :list, default: []

  # def update(
  #       %{preview_boundary_for_id: preview_boundary_for_id} = assigns,
  #       %{assigns: %{preview_boundary_for_id: preview_boundary_for_id}} = socket
  #     ) do
  #   {
  #     :ok,
  #     socket
  #     |> assign(assigns)
  #   }
  # end

  # def update(%{preview_boundary_for_id: preview_boundary_for_id} = assigns, socket)
  #     when not is_nil(preview_boundary_for_id) do
  #   {
  #     :ok,
  #     socket
  #     |> assign(assigns)
  #     |> preview(preview_boundary_for_id, assigns[:preview_boundary_for_username])
  #     #  |> debug()
  #   }
  # end

  # def update(assigns, socket) do
  #   socket =
  #     socket
  #     |> assign(assigns)
  #     |> assign_new(:boundary_preset, fn ->
  #       assigns[:boundary_preset] || socket.assigns[:boundary_preset]
  #     end)
  #     |> assign_new(:to_boundaries, fn ->
  #       assigns[:to_boundaries] || socket.assigns[:to_boundaries]
  #     end)
  #     |> assign(all_verbs: Bonfire.Boundaries.Verbs.verbs())
  #   {:ok, socket}
  # end

  def handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket) do
    # Only trigger search if the search text is at least 3 characters to prevent unnecessary operations
    Utils.maybe_apply(
      Bonfire.Me.Users,
      :search,
      [search]
    )
    |> Enum.map(fn
      %Needle.Pointer{activity: %{object: user}} -> user
      other -> other
    end)
    |> Bonfire.UI.Boundaries.SetBoundariesLive.results_for_multiselect()
    |> maybe_send_update(LiveSelect.Component, live_select_id, options: ...)

    {:noreply, socket}
  end

  def handle_event(
        "multi_select",
        %{data: %{"id" => id, "username" => username}} = _params,
        socket
      )
      when not is_nil(id) and not is_nil(username) do
    {:noreply, preview(socket, id, username)}
  end

  def handle_event(
        "multi_select",
        %{
          "_target" => _target,
          "preview_boundaries_form" => %{
            id: id,
            username: username
          },
          "preview_boundaries_text_input" => text_input
        } = _params,
        socket
      )
      when not is_nil(id) and not is_nil(username) do
    {:noreply, preview(socket, id, username)}
  end

  # THIS SHOULD NOT BE FIRED AT ALL
  def handle_event(
        "multi_select",
        %{
          "_target" => _target,
          "multi_select" => %{
            "Elixir.Bonfire.UI.Boundaries.PreviewBoundariesLive" => "",
            "Elixir.Bonfire.UI.Boundaries.PreviewBoundariesLive_text_input" => ""
          }
        },
        socket
      ) do
    {:noreply, socket}
  end

  # THIS I DONT KNOW WHY IT IS FIRED
  def handle_event(
        "multi_select",
        %{
          "_target" => _target,
          "multi_select" => multi_select_data
        } = _params,
        socket
      ) do
    debug(multi_select_data, "multi_select_data")
    {:noreply, socket}
  end

  def preview(socket, id, username) do
    current_user = current_user(socket)

    boundaries =
      Enum.map(
        List.wrap(socket.assigns[:boundary_preset] || socket.assigns[:to_boundaries] || []),
        fn
          {slug, _} -> slug
          slug -> slug
        end
      )

    opts = [
      preview_for_id: id,
      boundary: e(boundaries, "mentions"),
      to_circles: e(assigns(socket), :to_circles, []),
      context_id: e(assigns(socket), :context_id, nil)
      # TODO: also calculate mentions from current draft text to take those into account in boundary calculation
      # mentions: [],
      # reply_to_id: e(assigns(socket), :reply_to_id, nil),
    ]

    with {:ok, verbs} <-
           Bonfire.Boundaries.Acls.preview(current_user, opts)
           |> debug("preview") do
      role = Bonfire.Boundaries.Roles.preset_boundary_role_from_acl(verbs)

      role_name =
        case role do
          {role_name, _permissions} -> role_name
          _ -> nil
        end

      socket
      |> assign(
        role_name: role_name,
        preview_boundary_for_username: username,
        preview_boundary_for_id: id || :guests,
        preview_boundary_verbs: verbs
      )

      # |> push_event("change", "#smart_input")
    end
  end

  # def preview(socket, id, username), do: socket
end
