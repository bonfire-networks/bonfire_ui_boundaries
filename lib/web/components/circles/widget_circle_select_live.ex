defmodule Bonfire.UI.Boundaries.WidgetCircleSelectLive do
  @moduledoc "The \"Circle shown on the dashboard\" select, rendered by the dashboard settings inside their own form: it writes `[Bonfire.UI.Boundaries.WidgetCircleMembersLive, :circle]` through `Bonfire.Common.Settings:set`, offering the viewer's circles."
  use Bonfire.UI.Common.Web, :stateless_component

  prop id, :string, default: "widget-circle-select"
  prop scope, :any, default: nil

  data options, :list, default: []
  data circle, :any, default: nil

  def render(assigns) do
    user = current_user(assigns)
    scoped = Bonfire.Common.Settings.LiveHandler.scoped(assigns.scope, assigns[:__context__])

    assigns
    |> assign(
      options:
        user
        |> Bonfire.Boundaries.Circles.list_my()
        |> Enum.map(&{id(&1), e(&1, :named, :name, nil) || l("Untitled circle")}),
      circle:
        Bonfire.Common.Settings.get(
          [Bonfire.UI.Boundaries.WidgetCircleMembersLive, :circle],
          nil,
          scoped
        )
    )
    |> render_sface()
  end
end
