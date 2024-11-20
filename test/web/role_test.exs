defmodule Bonfire.Boundaries.RoleTest do
  use Bonfire.UI.Boundaries.ConnCase, async: true
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
    |> assert_has("td", text: "Facilitator")
  end

  test "I can edit the permissions of a role I've previously created", %{conn: conn} do
    conn
    |> visit("/boundaries/roles")
    |> click_button("[data-role=open_modal]", "New role")
    |> fill_in("Enter a name for the role", with: "facilitator")
    |> click_button("Create role")
    |> assert_has("td", text: "Facilitator")
    |> refute_has("[data-value=facilitator_see_can]")
    |> refute_has("[data-value=facilitator_read_can]")
    |> refute_has("[data-value=facilitator_request_can]")
    |> refute_has("[data-value=facilitator_like_can]")
    |> refute_has("[data-value=facilitator_boost_can]")
    |> refute_has("[data-value=facilitator_reply_can]")
    |> click_button("[data-id=facilitator_see_can]", "Can")
    |> click_button("[data-id=facilitator_read_can]", "Can")
    |> click_button("[data-id=facilitator_request_can]", "Can")
    |> click_button("[data-id=facilitator_like_can]", "Can")
    |> click_button("[data-id=facilitator_boost_can]", "Can")
    |> click_button("[data-id=facilitator_reply_can]", "Can")
    |> click_button("[data-id=facilitator_edit_cannot]", "Cannot")
    |> assert_has("[data-value=facilitator_see_can]")
    |> assert_has("[data-value=facilitator_read_can]")
    |> assert_has("[data-value=facilitator_request_can]")
    |> assert_has("[data-value=facilitator_like_can]")
    |> assert_has("[data-value=facilitator_boost_can]")
    |> assert_has("[data-value=facilitator_reply_can]")
    |> assert_has("[data-value=facilitator_edit_cannot]")
  end

  test "I can edit the name of a role I've previously created", %{conn: conn} do
    conn
    |> visit("/boundaries/roles")
    |> click_button("[data-role=open_modal]", "New role")
    |> fill_in("Enter a name for the role", with: "facilitator")
    |> click_button("Create role")
    |> assert_has("td", text: "Facilitator")
    |> click_button("[data-role=open_modal]", "Edit role")
    |> within("#edit_role_form_facilitator", fn session ->
      session
      |> fill_in("Edit the role name", with: "Mod")
      |> click_button("Save")
    end)
    |> assert_has("td", text: "Mod")
  end

  test "I can delete a role I've previously created", %{conn: conn} do
    conn
    |> visit("/boundaries/roles")
    |> click_button("[data-role=open_modal]", "New role")
    |> fill_in("Enter a name for the role", with: "facilitator")
    |> click_button("Create role")
    |> assert_has("td", text: "Facilitator")
    |> click_button("[data-role=open_modal]", "Edit role")
    |> within("#delete_role_form_facilitator", fn session ->
      session
      |> click_button("Delete")
    end)
    |> refute_has("td", text: "Facilitator")
  end

  test "I can see the default list of roles", %{conn: conn} do
    conn
    |> visit("/boundaries/default_roles")
    |> assert_has("td", text: "None")
    |> assert_has("td", text: "Read")
    |> assert_has("td", text: "Edit")
    |> assert_has("td", text: "Administer")
    |> assert_has("td", text: "Cannot Discover")
    |> assert_has("td", text: "Cannot Participate")
    |> assert_has("td", text: "Cannot Read")
    |> assert_has("td", text: "Moderate")
    |> assert_has("[data-value=none_see_undefined]")
    |> assert_has("[data-value=read_request_can]")
    |> assert_has("[data-value=edit_mention_can]")
    |> assert_has("[data-value=administer_create_can]")
    |> assert_has("[data-value=cannot_discover_see_cannot]")
    |> assert_has("[data-value=cannot_participate_reply_cannot]")
    |> assert_has("[data-value=cannot_read_read_cannot]")
    |> assert_has("[data-value=moderate_mediate_can]")
  end
end
