defmodule Bonfire.Boundaries.BoundaryPresetsTest do
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

  test "I can create a new preset", %{conn: conn} do
    conn
    |> visit("/boundaries/acls")
    |> click_button("[data-role=open_modal]", "New preset")
    |> fill_in("Enter a name for the boundary preset", with: "friends")
    |> click_button("[data-role=new_acl_submit]", "Create")
    |> assert_has("[role=banner]", text: "friends")
  end

  test "I can add a circle to a preset and specify the role", %{conn: conn, me: me} do
    {:ok, circle} = Bonfire.Boundaries.Circles.create(me, %{named: %{name: "bestie"}})

    conn
    |> visit("/boundaries/acls")
    |> click_button("[data-role=open_modal]", "New preset")
    |> fill_in("Enter a name for the boundary preset", with: "friends")
    |> click_button("[data-role=new_acl_submit]", "Create")
    |> assert_has("[role=banner]", text: "friends")
    |> click_button("[data-role=add-circle-to-acl]", "bestie")
    |> assert_has("#edit_grants", text: "bestie")
  end

  test "I can edit a preset I've previously created" do
  end

  test "I can delete a preset I've previously created" do
  end

  test "I can pick the preset previously created from the list of presets on composer" do
  end
end
