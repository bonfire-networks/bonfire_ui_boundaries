defmodule Bonfire.UI.Boundaries.WidgetCircleSelectLive do
  @moduledoc "The \"Circle shown on the dashboard\" select, rendered by the dashboard settings inside their own form: it writes `[Bonfire.UI.Boundaries.WidgetCircleMembersLive, :circle]` through `Bonfire.Common.Settings:set`, offering the viewer's circles."
  use Bonfire.UI.Common.Web, :stateless_component

  prop id, :string, default: "widget-circle-select"
  prop scope, :any, default: nil

  data options, :list, default: []
  data circle, :any, default: nil

  def render(assigns) do
    assigns
    |> assign(options: options(assigns), circle: chosen(assigns.scope, assigns))
    |> render_sface()
  end

  @doc "The name of the circle the widget shows (nil when none), for edit mode's tile."
  def current_label(context) do
    # the circles are only listed when one is chosen
    with circle when not is_nil(circle) <- chosen(nil, context) do
      Enum.find_value(options(context), fn {id, name} -> id == circle && name end)
    end
  end

  defp options(context) do
    context
    |> current_user()
    |> Bonfire.Boundaries.Circles.list_my()
    |> Enum.map(&{id(&1), e(&1, :named, :name, nil) || l("Untitled circle")})
  end

  defp chosen(scope, context) do
    Bonfire.Common.Settings.get(
      [Bonfire.UI.Boundaries.WidgetCircleMembersLive, :circle],
      nil,
      Bonfire.Common.Settings.LiveHandler.scoped(scope, context[:__context__] || context)
    )
  end
end
