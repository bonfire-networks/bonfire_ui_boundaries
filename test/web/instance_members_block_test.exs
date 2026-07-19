defmodule Bonfire.UI.Boundaries.InstanceMembersBlockTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Boundaries.Blocks

  setup do
    account = fake_account!()
    me = fake_user!(account)
    Bonfire.Me.Users.make_admin(me)
    # NOTE: alice needs her own account: disabling her force-logs-out her whole account, which
    # would otherwise kill the admin's session too
    alice = fake_user!(fake_account!())
    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, me: me, alice: alice}
  end

  test "members list shows an Active local member with a 'Block or disable' action", %{
    conn: conn,
    alice: alice
  } do
    conn
    |> visit("/settings/instance/members")
    |> wait_async()
    |> assert_has("td", text: alice.profile.name)
    |> assert_has(".badge", text: "Active")
    |> assert_has("#members_menu_links_#{alice.id} [data-role=open_modal]",
      text: "Block or disable"
    )
  end

  test "as an admin I can disable a local user from the members page", %{
    conn: conn,
    alice: alice
  } do
    conn
    |> visit("/settings/instance/members")
    |> wait_async()
    |> within("#members_menu_links_#{alice.id}", fn session ->
      click_button(session, "[data-role=open_modal]", "Block or disable")
    end)
    # the modal renders outside the dropdown, so click its button unscoped
    |> click_button("Disable this user")
    |> assert_has("[role=alert]", text: "blocked instance-wide")

    # the block was applied instance-wide...
    assert Blocks.is_blocked?(alice, :ghost, :instance_wide)
    assert Blocks.is_blocked?(alice, :silence, :instance_wide)
    # ...and the user's account is force-logged-out (the actual "disable" mechanism)
    assert Bonfire.Common.Cache.get!("force_logout:#{alice.id}") == true

    # blocked flags are computed at list-load time, so re-visit to see the new state
    conn
    |> visit("/settings/instance/members")
    |> wait_async()
    |> assert_has(".badge", text: "Blocked")
    |> assert_has("#members_menu_links_#{alice.id} [data-role=open_modal]", text: "Re-enable")
  end

  test "as an admin I can re-enable a previously disabled local user", %{
    conn: conn,
    alice: alice
  } do
    assert {:ok, _blocked} = Blocks.block(alice, :block, :instance_wide)

    conn
    |> visit("/settings/instance/members")
    |> wait_async()
    |> assert_has(".badge", text: "Blocked")
    |> within("#members_menu_links_#{alice.id}", fn session ->
      click_button(session, "[data-role=open_modal]", "Re-enable")
    end)
    |> click_button("Re-enable user")
    |> assert_has("[role=alert]", text: "unblocked instance-wide")

    refute Blocks.is_blocked?(alice, :ghost, :instance_wide)
    refute Blocks.is_blocked?(alice, :silence, :instance_wide)

    conn
    |> visit("/settings/instance/members")
    |> wait_async()
    |> assert_has(".badge", text: "Active")
    |> assert_has("#members_menu_links_#{alice.id} [data-role=open_modal]",
      text: "Block or disable"
    )
  end
end
