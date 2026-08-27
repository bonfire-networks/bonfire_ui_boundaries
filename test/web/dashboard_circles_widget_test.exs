defmodule Bonfire.UI.Boundaries.DashboardCirclesWidgetTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  use Surface.LiveViewTest

  alias Bonfire.Boundaries.Circles

  doctest Bonfire.UI.Boundaries.WidgetCirclesLive

  setup do
    account = fake_account!()
    me = fake_user!(account)

    %{account: account, conn: conn(user: me, account: account), me: me}
  end

  test "shows the direct creation action when the user has no circles", %{me: me} do
    html = render_widget(me)

    assert html_has_element?(
             html,
             "[data-id=widget_circles] button[data-role=open_modal][aria-label='Create a circle']"
           )

    assert html =~ "Circles"
    assert html =~ "No circles yet"
    assert html =~ "Create one"
    refute html =~ "All 0"
    refute html_has_element?(html, "[data-id=widget_circles] [data-role=circle-marker]")
  end

  test "opens the empty widget manager on the creation form", %{me: me} do
    html =
      render_component(Bonfire.UI.Boundaries.CirclesManagerLive,
        id: "empty-circles-manager",
        widget_id: "dashboard_circles",
        start_in_create: true,
        __context__: %{current_user: me, current_user_id: me.id}
      )

    assert html_has_element?(html, "[data-role=circles-manager][data-section=create]")
    assert html_has_element?(html, "#empty-circles-manager-create-form")
    assert html_has_element?(html, "[data-role=create-circle-submit]")
    refute html_has_element?(html, "#empty-circles-manager-summary")
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

    assert html_element_text(html, "#dashboard-circle-#{friends.id} a") == "Friends"
    assert html_element_text(html, "#dashboard-circle-#{work.id} a") == "Work"

    assert html =~ "Friends"
    assert html =~ "Work"
    assert html_has_element?(html, "button[aria-label='View all 2 circles']")
    refute html_has_element?(html, "[data-id=widget_circles] [data-role=circle-marker]")
  end

  test "renders the manager overview with counts and preview members", %{
    me: me,
    account: account
  } do
    alice = fake_user!(account)
    bob = fake_user!(account)
    {:ok, friends} = Circles.create(me, %{named: %{name: "Friends"}})
    {:ok, _} = Circles.add_to_circles(alice, friends)
    {:ok, _} = Circles.add_to_circles(bob, friends)

    html =
      render_component(Bonfire.UI.Boundaries.CirclesManagerLive,
        id: "dashboard-circles-manager",
        widget_id: "dashboard_circles",
        __context__: %{current_user: me, current_user_id: me.id}
      )

    assert html_has_element?(html, "[data-role=circles-manager][data-section=overview]")
    assert html_has_element?(html, "#dashboard-circles-manager-heading[tabindex='-1']")
    assert html_has_element?(html, "#manager-circle-#{friends.id} [data-role=manage-circle]")
    assert html_has_element?(html, "#manager-circle-#{friends.id} button.cursor-pointer")
    assert html_has_element?(html, "#manager-circle-#{friends.id} .col-start-4")
    assert html =~ "1 circle"
    assert html =~ "2 people organised across them"
    assert html =~ "2 people"
    assert html =~ "Friends"
  end

  test "renders the unified editor directly with discoverability controls", %{me: me} do
    {:ok, circle} = Circles.create(me, %{named: %{name: "Mutual aid"}})

    html =
      render_component(Bonfire.UI.Boundaries.CirclesManagerLive,
        id: "direct-circle-manager",
        circle_id: circle.id,
        __context__: %{current_user: me, current_user_id: me.id}
      )

    assert html_has_element?(html, "[data-role=circles-manager][data-section=detail]")
    assert html_has_element?(html, "#direct-circle-manager-discoverability")
    assert html_has_element?(html, "#direct-circle-manager-circle-access-#{circle.id}")
    assert html_has_element?(html, "[data-section=detail] .mt-5")
    assert html_has_element?(html, "button[data-scope=public_boundary]")
    assert html_has_element?(html, "button[data-scope=local_boundary]")
    refute html_has_element?(html, "#direct-circle-manager-circle-visibility")
    refute html_has_element?(html, "#direct-circle-manager-back-from-detail")
    assert html =~ "Share this circle"
    assert html =~ "Mutual aid"
  end

  test "associates circle field help and validation messages with their controls" do
    changeset =
      Circles.details_changeset(%{
        "name" => "Community organisers",
        "description" => String.duplicate("a", 241)
      })

    assigns = %{
      id_prefix: "circle-settings-test",
      form: Phoenix.Component.to_form(%{changeset | action: :validate}, as: :circle)
    }

    html =
      render_surface do
        ~F"""
        <Bonfire.UI.Boundaries.CircleSettingsFieldsLive id_prefix={@id_prefix} form={@form} />
        """
      end

    assert html_has_element?(
             html,
             "#circle-settings-test-circle-description[aria-invalid='true'][aria-describedby='circle-settings-test-circle-description-error']"
           )

    assert html_has_element?(html, "#circle-settings-test-circle-description-error[role='alert']")

    refute html_has_element?(html, "#circle-settings-test-circle-visibility")
  end

  # The generated dashboard in `lib/` can come from a previously installed flavour, so verify Jacobin's intentional source-template omission directly.
  if System.get_env("FLAVOUR") == "jacobin" do
    test "does not register the circles widget in the Jacobin dashboard template" do
      template_path =
        Path.expand(
          "../../../jacobin/priv/templates/lib/bonfire/web/views/dashboard_live.ex",
          __DIR__
        )

      refute File.read!(template_path) =~ "Bonfire.UI.Boundaries.WidgetCirclesLive"
    end
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
