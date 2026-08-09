defmodule Bonfire.UI.Boundaries.DashboardCirclesWidgetTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"

  alias Bonfire.Boundaries.Circles

  doctest Bonfire.UI.Boundaries.WidgetCirclesLive

  setup do
    account = fake_account!()
    me = fake_user!(account)

    %{account: account, conn: conn(user: me, account: account), me: me}
  end

  test "shows an actionable empty state when the user has no circles", %{me: me} do
    html = render_widget(me)

    assert html_has_element?(html, "[data-id=widget_circles] [data-role=widget-empty-state]")
    assert html_has_element?(html, "#dashboard_new_circle button[data-role=open_modal]")
    assert html =~ "Create a circle to organise people you follow."
    assert html =~ "Create a circle"
  end

  test "renders links to the current user's circles", %{me: me} do
    {:ok, friends} = Circles.create(me, %{named: %{name: "Friends"}})
    {:ok, work} = Circles.create(me, %{named: %{name: "Work"}})

    html = render_widget(me)

    assert html_has_element?(html, "[data-id=widget_circles] [data-role=circles-scroll]")

    assert html_has_element?(
             html,
             "#dashboard-circle-#{friends.id} a[href='/circle/#{friends.id}']"
           )

    assert html_has_element?(html, "#dashboard-circle-#{work.id} a[href='/circle/#{work.id}']")
    assert html_element_text(html, "#dashboard-circle-#{friends.id} [data-role=circle-marker]") == "F"
    assert html_element_text(html, "#dashboard-circle-#{work.id} [data-role=circle-marker]") == "W"
    assert html =~ "Friends"
    assert html =~ "Work"
  end

  test "does not render the circles widget on the Jacobin dashboard", %{conn: conn} do
    conn
    |> visit("/dashboard")
    |> refute_has("[data-id=widget_circles]")
  end

  defp render_widget(me) do
    render_component(Bonfire.UI.Boundaries.WidgetCirclesLive,
      id: "dashboard_circles",
      widget_title: "Circles",
      __context__: %{current_user: me, current_user_id: me.id}
    )
  end

  defp html_has_element?(html, selector) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find(selector)
    |> Enum.empty?()
    |> Kernel.not()
  end

  defp html_element_text(html, selector) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find(selector)
    |> Floki.text()
    |> String.trim()
  end
end
