defmodule Bonfire.UI.Boundaries.Web.CustomizeBoundaryLive do
  use Bonfire.UI.Common.Web, :stateful_component
  # alias Bonfire.Boundaries.Roles

  prop to_boundaries, :any, default: nil
  prop hide_presets, :boolean, default: false
  prop boundary_preset, :any, default: nil
  prop set_action, :any, default: nil
  prop set_opts, :any, default: nil
  prop my_acls, :any, default: nil
  prop is_customizable, :boolean, default: false
  prop hide_custom, :boolean, default: false
  prop to_circles, :list, default: []
  prop exclude_circles, :list, default: []

  def update(assigns, socket) do
    {
      :ok,
      socket
      |> assign(assigns)
    }
  end

  def handle_event(
        "multi_select",
        %{data: data, text: _text},
        socket
      ) do
    # debug(data, text)

    field =
      maybe_to_atom(e(data, "field", :to_boundaries))
      |> debug("field")

    appended_data =
      case field do
        :to_boundaries ->
          # [{"public", l("Public")}]
          []
          |> (e(assigns(socket), field, ...) ++
                [{id(data), data}])

        :to_circles ->
          e(assigns(socket), field, []) ++
            [{data, nil}]

        :exclude_circles ->
          e(assigns(socket), field, []) ++
            [{data, nil}]

        _ ->
          e(assigns(socket), field, []) ++
            [{data, id(data)}]
      end
      |> debug("list")
      |> Enum.uniq()
      |> debug("uniq")

    maybe_send_update(
      Bonfire.UI.Boundaries.Web.CustomizeBoundaryLive,
      "customize_boundary_live",
      %{field => appended_data}
    )

    {:noreply,
     socket
     |> assign(
       field,
       appended_data
     )
     |> assign_global(
       _already_live_selected_:
         Enum.uniq(e(assigns(socket), :__context, :_already_live_selected_, []) ++ [field])
     )}
  end
end
