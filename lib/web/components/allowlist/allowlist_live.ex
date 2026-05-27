defmodule Bonfire.UI.Boundaries.AllowlistLive do
  use Bonfire.UI.Common.Web, :stateful_component

  prop selected_tab, :any
  prop name, :string, default: nil
  prop title, :string, default: nil
  prop description, :string, default: nil
  prop scope, :any, default: nil

  def update(assigns, socket) do
    context = assigns[:__context__] || assigns(socket)[:__context__]
    current_user = current_user(context)

    scope = e(assigns, :scope, nil)

    read_only =
      scope == :instance_wide and
        Bonfire.Boundaries.can?(context, :configure, :instance) != true

    circles =
      if scope == :instance_wide do
        Bonfire.Boundaries.Allowlist.list(:instance_wide)
      else
        Bonfire.Boundaries.Allowlist.list(current_user: current_user)
      end

    circle =
      case List.first(List.wrap(circles)) do
        nil when not is_nil(current_user) and scope != :instance_wide ->
          case Bonfire.Boundaries.Circles.get_or_create_stereotype_circle(
                 current_user,
                 :allow_them
               ) do
            {:ok, c} -> c
            _ -> nil
          end

        c ->
          c
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       scope: scope,
       read_only: read_only,
       circle: if(is_map(circle), do: circle),
       circle_id: id(circle),
       title: e(assigns, :title, nil),
       description: e(assigns, :description, nil)
     )}
  end
end
