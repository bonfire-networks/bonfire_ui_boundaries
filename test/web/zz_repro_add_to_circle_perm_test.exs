# TEMPORARY repro, delete after checking
defmodule Bonfire.UI.Boundaries.ReproAddToCirclePermTest do
  use Bonfire.UI.Boundaries.ConnCase, async: false

  alias Bonfire.Boundaries.Circles

  test "plain user adds themselves to the admin circle via the widget event" do
    account = fake_account!()
    me = fake_user!(account)
    other = fake_user!(fake_account!())
    control = fake_user!(fake_account!())
    admin_circle = Circles.get_id!(:admin)

    # can?(_, _, :instance) memoises per process, so only the control is checked up front
    refute Circles.is_encircled_by?(me, admin_circle)

    conn = conn(user: me, account: account)
    {:ok, view, _html} = live(conn, "/@#{other.character.username}")

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

    IO.inspect(id, label: "widget id")

    view
    |> with_target("##{id}")
    |> render_click("add", %{"id" => me.id, "circle" => admin_circle})

    IO.inspect(Circles.is_encircled_by?(me, admin_circle), label: "me in admin circle")
    IO.inspect(Bonfire.Boundaries.can?(me, :invite, :instance), label: "me can invite")
    IO.inspect(Bonfire.Boundaries.can?(control, :invite, :instance), label: "control can invite")

    assert Circles.is_encircled_by?(me, admin_circle)
    assert Bonfire.Boundaries.can?(me, :invite, :instance)
    refute Bonfire.Boundaries.can?(control, :invite, :instance)
  end
end
