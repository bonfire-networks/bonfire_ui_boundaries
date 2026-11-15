defmodule Bonfire.UI.Boundaries.AddToCircleWidgetTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"

  alias Bonfire.Boundaries.Circles
  alias Bonfire.UI.Boundaries.AddToCircleWidgetLive

  setup do
    account = fake_account!()
    me = fake_user!(account)
    person = fake_user!(account)

    %{me: me, person: person, conn: conn(user: me, account: account)}
  end

  test "loads descriptions and uses existing membership for the action", %{me: me, person: person} do
    description = Faker.Lorem.sentence()

    {:ok, circle} =
      Circles.create(me, %{named: %{name: "Astronomy"}, extra_info: %{summary: description}})

    {:ok, _} = Circles.add_to_circles(person, circle, current_user: me)

    html = render_widget(me, person)

    assert element_text(html, "[data-role=circle-description]") == description
    assert element_text(html, "[data-role=remove_from_circle]") == "Remove"
    assert element_text(html, "[data-role=circle-membership]") == "Added"
    assert element_text(html, "[data-role=circle-selection-count]") == "1 of 1 selected"
    refute html =~ "data-role=\"circle-member-count\""
    refute html =~ "data-role=\"add_to_circle\""
  end

  test "preloads descriptions for circles passed by a parent without inventing counts", %{
    me: me,
    person: person
  } do
    description = Faker.Lorem.sentence()

    {:ok, _circle} =
      Circles.create(me, %{named: %{name: "Astronomy"}, extra_info: %{summary: description}})

    circles = Circles.list_my_for_sidebar(me, exclude_stereotypes: true, exclude_built_ins: true)

    html = render_widget(me, person, circles: circles)

    assert element_text(html, "[data-role=circle-description]") == description
    assert element_text(html, "[data-role=add_to_circle]") == "Add"
    refute html =~ "data-role=\"circle-member-count\""
  end

  test "omits missing descriptions and preserves supplied counts", %{me: me, person: person} do
    {:ok, circle} = Circles.create(me, %{named: %{name: "Astronomy"}})
    circle = Map.put(circle, :encircles_count, 0)

    html = render_widget(me, person, circles: [circle])

    refute html =~ "data-role=\"circle-description\""
    assert element_text(html, "[data-role=circle-member-count]") == "0 members"
  end

  test "adds and removes through the existing profile modal events", %{
    me: me,
    person: person,
    conn: conn
  } do
    description = Faker.Lorem.sentence()

    {:ok, circle} =
      Circles.create(me, %{named: %{name: "Astronomy"}, extra_info: %{summary: description}})

    session =
      conn
      |> visit("/@#{person.character.username}")
      |> click_button("[data-id=profile_main_actions] [data-role=open_modal]", "Add to circles")
      |> assert_has("[data-role=circle-description]", text: description)
      |> click_button("button[data-role=add_to_circle]", "Add")
      |> assert_has("[data-role=remove_from_circle]", text: "Remove")
      |> assert_has("[data-role=circle-membership]", text: "Added")
      |> assert_has("[data-role=circle-selection-count]", text: "1 of 1 selected")

    assert Circles.is_encircled_by?(person, circle)

    session
    |> click_button("[data-role=remove_from_circle]", "Remove")
    |> assert_has("button[data-role=add_to_circle]", text: "Add")
    |> assert_has("[data-role=circle-selection-count]", text: "0 of 1 selected")

    refute Circles.is_encircled_by?(person, circle)
  end

  test "creates a circle with a description without automatically adding the person", %{
    me: me,
    person: person,
    conn: conn
  } do
    description = Faker.Lorem.sentence()

    conn
    |> visit("/@#{person.character.username}")
    |> click_button("[data-id=profile_main_actions] [data-role=open_modal]", "Add to circles")
    |> assert_has("li", text: "No circles yet. Create one to get started.")
    # PhoenixTest cannot execute visibility-only JS; submit the mounted form directly.
    |> assert_has("button", text: "Create a new circle")
    |> fill_in("Enter a name for the circle", with: "Astronomy", exact: false)
    |> fill_in("Enter a description for the circle", with: description, exact: false)
    |> click_button("[data-role=new_circle_submit]", "Create")
    |> assert_has("[data-role=circle-description]", text: description)
    |> assert_has("button[data-role=add_to_circle]", text: "Add")
    |> assert_has("[data-role=circle-selection-count]", text: "0 of 1 selected")
    |> click_button("Done")
    |> refute_has("[role=dialog] [data-role=add-to-circles-widget]", timeout: 1000)

    [circle] = Circles.list_my_for_sidebar(me, exclude_stereotypes: true, exclude_built_ins: true)
    refute Circles.is_encircled_by?(person, circle)
  end

  describe "events pushed to the widget with crafted params" do
    test "I cannot add myself to the built-in admin circle", %{me: me, person: person, conn: conn} do
      admin_circle = Circles.get_id!(:admin)
      refute Circles.is_encircled_by?(me, admin_circle), "control: I am not in it to begin with"

      conn
      |> widget_view(person)
      |> push_widget("add", %{"id" => me.id, "circle" => admin_circle})

      refute Circles.is_encircled_by?(me, admin_circle)

      # `can?(_, _, :instance)` memoises per process, so checking `me` before the event would cache the answer: a separate plain user is the control
      control = fake_user!(fake_account!())

      refute Bonfire.Boundaries.can?(control, :invite, :instance),
             "control: a plain user cannot invite"

      refute Bonfire.Boundaries.can?(me, :invite, :instance)
    end

    test "I cannot add someone to a circle another user owns", %{
      me: me,
      person: person,
      conn: conn
    } do
      {:ok, circle} = Circles.create(person, %{named: %{name: "Their friends"}})
      {:ok, mine} = Circles.create(me, %{named: %{name: "My friends"}})
      refute Circles.is_encircled_by?(me, circle), "control: I am not in it to begin with"
      refute Circles.is_encircled_by?(person, mine), "control: they are not in mine to begin with"

      widget = widget_view(conn, person)

      push_widget(widget, "add", %{"id" => me.id, "circle" => circle.id})

      refute Circles.is_encircled_by?(me, circle)

      # the same event, for a circle I own, works
      push_widget(widget, "add", %{"id" => person.id, "circle" => mine.id})

      assert Circles.is_encircled_by?(person, mine)
    end

    test "I cannot remove someone from a circle another user owns", %{
      me: me,
      person: person,
      conn: conn
    } do
      member = fake_user!(fake_account!())
      {:ok, circle} = Circles.create(person, %{named: %{name: "Their friends"}})
      {:ok, _} = Circles.add_to_circles(member, circle, current_user: person)
      {:ok, mine} = Circles.create(me, %{named: %{name: "My friends"}})
      {:ok, _} = Circles.add_to_circles(member, mine, current_user: me)
      assert Circles.is_encircled_by?(member, circle), "control: they are in it to begin with"
      assert Circles.is_encircled_by?(member, mine), "control: they are in mine to begin with"

      widget = widget_view(conn, person)

      push_widget(widget, "remove", %{"id" => member.id, "circle" => circle.id})

      assert Circles.is_encircled_by?(member, circle)

      # the same event, for a circle I own, works
      push_widget(widget, "remove", %{"id" => member.id, "circle" => mine.id})

      refute Circles.is_encircled_by?(member, mine)
    end
  end

  defp widget_view(conn, person) do
    {:ok, view, _html} = live(conn, "/@#{person.character.username}")

    view
    |> element(
      "[data-id=profile_main_actions] [data-role=open_modal][aria-label='Add to circles']"
    )
    |> render_click()

    [id] =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.attribute("[id]", "id")
      |> Enum.filter(&(&1 =~ ~r/add.to.circle.widget/i))
      |> Enum.uniq()
      |> Enum.take(1)

    {view, id}
  end

  defp push_widget({view, id}, event, params) do
    view
    |> with_target("##{id}")
    |> render_click(event, params)
  end

  defp render_widget(me, person, opts \\ []) do
    render_component(AddToCircleWidgetLive,
      id: "circle-picker-test",
      user_id: person.id,
      name: person.profile.name,
      circles: Keyword.get(opts, :circles, []),
      __context__: %{current_user: me, current_user_id: me.id}
    )
  end

  defp element_text(html, selector) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find(selector)
    |> Floki.text()
    |> String.trim()
  end
end
