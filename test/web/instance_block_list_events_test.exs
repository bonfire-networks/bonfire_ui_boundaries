defmodule Bonfire.UI.Boundaries.InstanceBlockListEventsTest do
  @moduledoc "Lifting an instance-wide block is for those who may block on the instance. The page shows its lists read-only to everyone else, but the list's `remove` event is sent by the browser, so the server has to refuse it."
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Boundaries.Blocks

  test "I cannot lift an instance-wide block when I am not allowed to block on the instance" do
    account = fake_account!()
    me = fake_user!(account)
    blocked = fake_user!(fake_account!())

    {:ok, _} = Blocks.block(blocked, :block, scope: :instance_wide, skip_boundary_check: true)

    assert Blocks.is_blocked?(blocked, :ghost, :instance_wide),
           "control: they are blocked instance-wide to begin with"

    refute Bonfire.Boundaries.can?(me, :block, :instance),
           "control: I may not block instance-wide"

    {:ok, view, _html} =
      live(conn(user: me, account: account), "/settings/boundaries/instance_blocked")

    render_async(view)

    view
    |> with_target("#circle_members")
    |> render_click("remove", %{"subject" => blocked.id})

    assert Blocks.is_blocked?(blocked, :ghost, :instance_wide)
    assert Blocks.is_blocked?(blocked, :silence, :instance_wide)
  end

  # the picked person arrives as the JSON the member search puts in the form
  defp add_to_silenced(account, user, target) do
    {:ok, view, _html} =
      live(conn(user: user, account: account), "/settings/boundaries/instance_silenced")

    render_async(view)

    view
    |> with_target("#circle_members")
    |> render_hook("change", %{
      "_target" => ["multi_select", "add_to_circles"],
      "multi_select" => %{
        "add_to_circles" =>
          Jason.encode!(%{"id" => target.id, "name" => "target", "type" => "user"})
      }
    })
  end

  test "I cannot silence someone instance-wide when I am not allowed to block on the instance" do
    admin_account = fake_account!()
    admin = fake_admin!(admin_account)
    by_admin = fake_user!(fake_account!())
    account = fake_account!()
    me = fake_user!(account)
    victim = fake_user!(fake_account!())

    add_to_silenced(admin_account, admin, by_admin)

    assert Blocks.is_blocked?(by_admin, :silence, :instance_wide),
           "control: an admin adding through the same event does silence them"

    add_to_silenced(account, me, victim)

    refute Blocks.is_blocked?(victim, :silence, :instance_wide)
  end
end
