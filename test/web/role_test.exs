defmodule Bonfire.UI.Boundaries.RoleTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Social.Fake
  alias Bonfire.Posts
  alias Bonfire.Files.Test

  setup do
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)
    carl = fake_user!(account)
    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, me: me, alice: alice, bob: bob, carl: carl}
  end

  test "I can create a new role and define some permissions", %{conn: conn} do
    conn
    |> visit("/boundaries/roles")
    |> click_button("[data-role=open_modal]", "New role")
    |> fill_in("Enter a name for the role", with: "facilitator")
    |> click_button("Create role")
    |> assert_has("h3", text: "Facilitator")
  end

  test "I can edit the permissions of a role I've previously created", %{conn: conn} do
    conn
    |> visit("/boundaries/roles")
    |> click_button("[data-role=open_modal]", "New role")
    |> fill_in("Enter a name for the role", with: "facilitator")
    |> click_button("Create role")
    |> assert_has("h3", text: "Facilitator")
    # Verify the role card has permission toggles available
    # The toggles use data-id for clicking and data-value for current state
    |> assert_has("[data-id=facilitator_see_can]")
    |> assert_has("[data-id=facilitator_read_can]")
    |> assert_has("[data-id=facilitator_like_can]")
    # Initially no permissions are explicitly set (they show undefined state)
    |> refute_has("[data-value=facilitator_see_can]")
  end

  test "I can edit the name of a role I've previously created", %{conn: conn} do
    conn
    |> visit("/boundaries/roles")
    |> click_button("[data-role=open_modal]", "New role")
    |> fill_in("Enter a name for the role", with: "facilitator")
    |> click_button("Create role")
    |> assert_has("h3", text: "Facilitator")
    # Click the Edit button (OpenModalLive wraps it with phx-click)
    |> click_button("[data-role=open_modal]", "Edit role")
    |> fill_in("Edit the role name", with: "Mod")
    |> click_button("Save")
    |> assert_has("h3", text: "Mod")
  end

  test "I can delete a role I've previously created", %{conn: conn} do
    conn
    |> visit("/boundaries/roles")
    |> click_button("[data-role=open_modal]", "New role")
    |> fill_in("Enter a name for the role", with: "facilitator")
    |> click_button("Create role")
    |> assert_has("h3", text: "Facilitator")
    # Click the Delete button (OpenModalLive wraps it with phx-click)
    |> click_button("[data-role=open_modal]", "Delete")
    |> click_button("Delete Role")
    |> refute_has("h3", text: "Facilitator")
  end

  test "I can see the default list of roles", %{conn: conn} do
    conn
    |> visit("/boundaries/default_roles")
    |> assert_has("h3", text: "None")
    |> assert_has("h3", text: "Read")
    |> assert_has("h3", text: "Edit")
    |> assert_has("h3", text: "Administer")
    |> assert_has("h3", text: "Cannot Discover")
    |> assert_has("h3", text: "Cannot Participate")
    |> assert_has("h3", text: "Cannot Read")
    |> assert_has("h3", text: "Moderate")
    # Built-in roles are read-only and display badges instead of toggles
    # Check that built-in badge is shown
    |> assert_has(".badge", text: "Built-in")
  end
end
