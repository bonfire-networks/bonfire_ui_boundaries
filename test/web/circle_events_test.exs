defmodule Bonfire.UI.Boundaries.CircleEventsTest do
  @moduledoc "Who is in a circle is the business of whoever owns it. The circle page puts the circle in the socket, and the delegated events that add and remove members act on that circle, so a signed-in user who can merely view someone else's circle must not change its members by sending them."
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Social.Objects

  setup do
    owner = fake_user!(fake_account!())
    account = fake_account!()
    attacker = fake_user!(account)
    member = fake_user!(fake_account!())

    {:ok, circle} = Circles.create(owner, %{named: %{name: "visible circle"}})
    # viewable by anyone, so the attacker really can open the page
    Objects.publish(owner, :boost, circle, to_boundaries: "public")
    {:ok, _} = Circles.add_to_circles(member, circle, current_user: owner)

    {:ok, view, _html} = live(conn(user: attacker, account: account), "/circle/#{circle.id}")

    {:ok, attacker: attacker, member: member, circle: circle, view: view}
  end

  test "I cannot remove a member from a circle I do not own", %{
    member: member,
    circle: circle,
    view: view
  } do
    assert Circles.is_encircled_by?(member, circle), "control: they are in it to begin with"

    render_hook(view, "Bonfire.Boundaries.Circles:remove_from_circle", %{
      "subject_id" => member.id
    })

    assert Circles.is_encircled_by?(member, circle)
  end

  test "I cannot add someone to a circle I do not own", %{
    attacker: attacker,
    circle: circle,
    view: view
  } do
    refute Circles.is_encircled_by?(attacker, circle), "control: I am not in it to begin with"

    render_hook(view, "Bonfire.Boundaries.Circles:multi_select", %{
      "data" => %{"id" => attacker.id, "name" => "me", "type" => "user"},
      "text" => "me"
    })

    refute Circles.is_encircled_by?(attacker, circle)
  end
end
