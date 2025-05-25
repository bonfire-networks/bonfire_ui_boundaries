defmodule Bonfire.UI.Boundaries.ManageCircleLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Blocks

  prop circle_id, :any, default: nil
  prop circle, :any, default: nil
  prop circle_type, :atom, default: nil
  prop name, :string, default: nil
  prop parent_back, :any, default: nil
  prop scope, :any, default: nil
  prop showing_within, :atom, default: nil
  prop feedback_title, :string, default: nil
  prop feedback_message, :string, default: nil
  prop read_only, :any, default: nil

  prop setting_boundaries, :boolean, default: false
  prop boundary_preset, :any, default: nil
  prop to_boundaries, :any, default: nil

  slot default, required: false

  def update(assigns, %{assigns: %{loaded: true}} = socket) do
    debug(assigns, "all already loaded")
    # params = e(assigns, :__context__, :current_params, %{})

    {
      :ok,
      socket
      |> assign(Enums.filter_empty(assigns, []))
      #  |> assign(page_title: l("Circle"))
      #  |> assign(section: e(params, "section", "members"))
    }
  end

  def update(%{circle: nil} = assigns, socket) do
    debug("need to load the circle")
    current_user = current_user(assigns) || current_user(socket)

    params =
      e(assigns, :__context__, :current_params, %{}) ||
        e(assigns(socket), :__context__, :current_params, %{})
        |> debug("current_params")

    id =
      (e(params, "id", nil) || e(assigns, :circle_id, nil) || e(assigns(socket), :circle_id, nil))
      |> debug("circle_id")

    scope = e(assigns, :scope, nil) || e(assigns(socket), :scope, nil)

    with %{id: id} = circle <-
           (e(assigns, :circle, nil) ||
              Circles.get_for_caretaker(id, current_user, scope: scope))
           |> repo().maybe_preload(:extra_info)
           |> ok_unwrap() do
      stereotype_id = e(circle, :stereotyped, :stereotype_id, nil)

      follow_stereotypes = Circles.stereotypes(:follow)

      read_only = e(assigns, :read_only, nil) || e(assigns(socket), :read_only, nil)

      read_only =
        if is_nil(read_only) and stereotype_id do
          Circles.is_built_in?(circle) ||
            stereotype_id in follow_stereotypes || []
        else
          read_only
        end

      Map.merge(assigns, %{
        loaded: true,
        circle_id: id,
        # |> Map.drop([:encircles]),
        circle: circle,
        #  page_title: l("Circle"),
        #  suggestions: suggestions,
        #  stereotype_id: stereotype_id,
        read_only: read_only
        #  settings_section_title: "Manage " <> e(circle, :named, :name, "") <> " circle"
      })
      |> debug("circle loaded")
      |> assign(socket)

      # else other ->
      #   error(other)
      #   {:ok, socket
      #     |> assign_flash(:error, l "Could not find circle")
      #     |> assign(
      #       circle: nil,
      #       members: [],
      #       suggestions: [],
      #       read_only: true
      #     )
      #     # |> redirect_to("/boundaries/circles")
      #   }
    end
  end

  def update(%{boundary_preset: boundary_preset} = assigns, socket)
      when is_nil(boundary_preset) or boundary_preset == {"custom", "Custom"} do
    circle =
      debug(
        e(assigns, :circle, :id, nil) || e(assigns, :circle_id, nil) ||
          e(assigns(socket), :circle, :id, nil) || e(assigns(socket), :circle_id, nil),
        "circle already loaded, but we're not sure what its boundaries are"
      )

    socket
    |> assign(assigns)
    |> load_boundaries(circle)
  end

  def update(assigns, socket) do
    debug(assigns, "nothing to do")

    {:ok,
     socket
     |> assign(assigns)}
  end

  def load_boundaries(socket, circle) do
    debug(circle, "circle already loaded, but we're not sure what its boundaries are")

    object_acls = Bonfire.Boundaries.list_object_boundaries(circle)
    # |> debug("acls")

    boundary_preset =
      if object_acls == [] do
        {"private", l("Private")}
      end

    # {preset_acls, custom_acls} =
    #   object_acls
    #   |> Enum.split_with(&e(&1, :named, nil))
    # |> debug("preset vs custom acls")

    {:ok,
     assign(
       socket,
       loaded: true,
       #  page_title: l("Circle"),
       #  suggestions: suggestions,
       #  settings_section_title: "Manage " <> e(circle, :named, :name, "") <> " circle",
       to_boundaries: object_acls |> debug("custom_acls"),
       boundary_preset:
         (boundary_preset ||
            Bonfire.Boundaries.preset_boundary_tuple_from_acl(
              object_acls,
              Bonfire.Data.AccessControl.Circle
            ))
         |> debug("boundary_preset")
     )}
  end
end
