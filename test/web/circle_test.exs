defmodule Bonfire.UI.Boundaries.CircleTest do
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

  # WIP: TEST LIVESELECT TO ADD USERS TO A CIRCLE

  test "I can create a new circle", %{conn: conn} do
    conn
    |> visit("/boundaries/circles")
    |> click_button("[data-role=open_modal]", "New circle")
    |> fill_in("Enter a name for the circle", with: "friends")
    |> click_button("[data-role=new_circle_submit]", "Create")
    |> assert_has("[role=banner]", text: "friends")
  end

  test "I can remove a user from a circle", %{conn: conn, alice: alice, me: me} do
    {:ok, circle} = Bonfire.Boundaries.Circles.create(me, %{named: %{name: "family"}})
    {:ok, _} = Bonfire.Boundaries.Circles.add_to_circles(alice, circle)

    conn
    |> visit("/boundaries/scope/user/circle/#{circle.id}")
    |> assert_has("#circle_members", text: alice.profile.name)
    |> click_button("[data-role=remove_user]", "Remove")
    |> assert_has("[role=alert]", text: "Removed from circle!")
    |> refute_has("#circle_members", text: alice.profile.name)
  end

  test "I can edit the name of a circle I've previously created", %{conn: conn, me: me} do
    {:ok, circle} = Bonfire.Boundaries.Circles.create(me, %{named: %{name: "family"}})

    conn
    |> visit("/boundaries/scope/user/circle/#{circle.id}")
    |> assert_has("[role=banner]", text: "family")
    |> click_button("[data-role=open_modal]", "Edit circle")
    |> fill_in("Edit the circle name", with: "friends")
    |> click_button("[data-role=edit_name_submit]", "Save")
    |> assert_has("[role=alert]", text: "Edited!")
    |> refute_has("[role=banner]", text: "family")
    |> assert_has("[role=banner]", text: "friends")
  end

  test "I can delete a circle I've previously created", %{conn: conn, me: me} do
    {:ok, circle} = Bonfire.Boundaries.Circles.create(me, %{named: %{name: "family"}})

    conn
    |> visit("/boundaries/scope/user/circle/#{circle.id}")
    |> assert_has("[role=banner]", text: "family")
    |> click_button("[data-role=open_modal]", "Delete circle")
    |> click_button("[data-role=confirm_delete_circle]", "Delete this circle")
    |> refute_has("[role=banner]", text: "family")
  end

  test "I can assign a user to a circle from the user profile", %{
    conn: conn,
    me: me,
    alice: alice
  } do
    {:ok, circle} = Bonfire.Boundaries.Circles.create(me, %{named: %{name: "family"}})

    conn
    |> visit("/@#{alice.character.username}")
    |> click_button("[data-id=profile_main_actions] [data-role=open_modal]", "Add to circles")
    |> click_button("[data-role=add_to_circle]", "family")
    |> assert_has("[role=alert]", text: "Added to circle!")
  end
end
