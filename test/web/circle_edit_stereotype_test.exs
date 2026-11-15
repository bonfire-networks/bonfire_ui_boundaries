defmodule Bonfire.UI.Boundaries.CircleEditStereotypeTest do
  @moduledoc "Who is in my followers (or followed) circle is decided by who follows me, never by a list the browser sends: the `circle_edit` event may change the members of my own ordinary circles only."
  use Bonfire.UI.Boundaries.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Circles.LiveHandler
  alias Phoenix.LiveView.Socket

  setup do
    account = fake_account!()
    me = fake_user!(account)
    other = fake_user!(fake_account!())

    %{me: me, other: other}
  end

  test "control: I can set the members of one of my own circles with the event", %{
    me: me,
    other: other
  } do
    # without a name: the event fails on a circle that has one (its `named` row is written with no id)
    {:ok, circle} = Circles.create(me, %{})
    refute Circles.is_encircled_by?(other, circle)

    send_circle_edit(me, circle, other)

    assert Circles.is_encircled_by?(other, circle)
  end

  test "I can set the members of one of my own circles that has a name, and it keeps its name", %{
    me: me,
    other: other
  } do
    {:ok, circle} = Circles.create(me, %{named: %{name: "besties"}})

    assert {:noreply, _} = send_circle_edit(me, circle, other)

    assert Circles.is_encircled_by?(other, circle)
    assert {:ok, reloaded} = Circles.get_for_caretaker(circle.id, me)
    assert Bonfire.Common.Repo.maybe_preload(reloaded, :named).named.name == "besties"
  end

  test "an entry naming another circle still lands in the circle being edited", %{
    me: me,
    other: other
  } do
    {:ok, circle} = Circles.create(me, %{})
    {:ok, elsewhere} = Circles.create(me, %{})

    send_circle_edit(me, circle, other, elsewhere.id)

    assert Circles.is_encircled_by?(other, circle)
    refute Circles.is_encircled_by?(other, elsewhere)
  end

  test "I cannot put someone in my followers circle with the event", %{me: me, other: other} do
    assert [followers | _] = Circles.get_stereotype_circles(me, :followers)
    assert {:ok, _} = Circles.get_for_caretaker(followers.id, me), "control: it is my circle"
    refute Circles.is_encircled_by?(other, followers), "control: they do not follow me"

    send_circle_edit(me, followers, other)

    refute Circles.is_encircled_by?(other, followers)
  end

  test "I cannot put someone in my followed circle with the event", %{me: me, other: other} do
    assert [followed | _] = Circles.get_stereotype_circles(me, :followed)
    refute Circles.is_encircled_by?(other, followed), "control: I do not follow them"

    send_circle_edit(me, followed, other)

    refute Circles.is_encircled_by?(other, followed)
  end

  defp send_circle_edit(me, circle, subject, entry_circle_id \\ nil) do
    socket = %Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        __context__: %{current_user: me, current_user_id: me.id},
        current_user: me,
        current_user_id: me.id,
        circle: circle
      }
    }

    LiveHandler.handle_event(
      "circle_edit",
      %{
        "circle" => %{
          "encircle" => [
            %{"subject_id" => subject.id, "circle_id" => entry_circle_id || circle.id}
          ]
        }
      },
      socket
    )
  end
end
