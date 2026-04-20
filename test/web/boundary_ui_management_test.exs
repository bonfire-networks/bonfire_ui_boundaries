defmodule Bonfire.UI.Boundaries.BoundaryUIManagementTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Boundaries.{Circles, Acls, Grants}

  setup do
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)

    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, me: me, alice: alice, bob: bob}
  end

  describe "Create a New Boundary Preset" do
    test "I can create a new boundary preset and configure verb permissions", %{
      conn: conn,
      me: me,
      alice: alice,
      bob: bob
    } do
      # First create some circles to use in the preset
      {:ok, friends_circle} = Circles.create(me, %{named: %{name: "friends"}})
      {:ok, family_circle} = Circles.create(me, %{named: %{name: "family"}})

      # Add users to circles
      {:ok, _} = Circles.add_to_circles(alice, friends_circle)
      {:ok, _} = Circles.add_to_circles(bob, family_circle)

      # Navigate to boundaries settings page and create new preset
      conn
      |> visit("/settings/boundaries/acls")
      |> assert_has("button", text: "New preset")
      |> click_button("New preset")
      |> fill_in("Enter a name for the boundary preset", with: "close friends")
      |> click_button("Create")
      |> assert_has("[data-role=acl_name]", text: "close friends")

      # Configure Read permission for friends circle (enable it)
      |> assert_has(
        "button[phx-value-role='#{friends_circle.id}'][phx-value-verb='read'][phx-value-status='1']"
      )
      |> click_button(
        "button[phx-value-role='#{friends_circle.id}'][phx-value-verb='read'][phx-value-status='1']",
        "Can"
      )
      |> assert_has(
        "[phx-value-role='#{friends_circle.id}'][phx-value-verb='read'][phx-value-status='1'].bg-success"
      )

      # Configure Reply and Like permissions for family circle
      |> click_button(
        "button[phx-value-role='#{family_circle.id}'][phx-value-verb='reply'][phx-value-status='1']",
        "Can"
      )
      |> click_button(
        "button[phx-value-role='#{family_circle.id}'][phx-value-verb='like'][phx-value-status='1']",
        "Can"
      )
      |> assert_has(
        "button[phx-value-role='#{family_circle.id}'][phx-value-verb='reply'][phx-value-status='1'].bg-success"
      )
      |> assert_has(
        "button[phx-value-role='#{family_circle.id}'][phx-value-verb='like'][phx-value-status='1'].bg-success"
      )

      # Verify the preset is saved and appears in the list
      |> visit("/settings/boundaries/acls")
      |> assert_has("div", text: "close friends")
    end

    @tag :skip
    # FIXME: Test works but LiveView doesn't show the new preset in the list after creation
    test "I can configure custom verb permissions with different states", %{
      conn: conn,
      me: me,
      alice: alice
    } do
      {:ok, circle} = Circles.create(me, %{named: %{name: "bestie"}})
      {:ok, _} = Circles.add_to_circles(alice, circle)

      conn
      |> visit("/settings/boundaries/acls")
      |> assert_has("button", text: "New preset")
      |> click_button("New preset")
      |> fill_in("Enter a name for the boundary preset", with: "custom perms")
      |> click_button("Create")
      |> assert_has("div", text: "custom perms")

      # Test different verb permission states
      |> assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1']"
      )
      # Allow reading
      |> click_button(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1']",
        "Can"
      )
      |> assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1']"
      )
      # Allow replying
      |> click_button(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1']",
        "Can"
      )
      |> assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0']"
      )
      # Explicitly deny boosting
      |> click_button(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0']",
        "Cannot"
      )
      |> assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1']"
      )
      # Allow liking
      |> click_button(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1']",
        "Can"
      )

      # Verify the states are set correctly
      |> assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1'].bg-success"
      )
      |> assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1'].bg-success"
      )
      |> assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0'].bg-error"
      )
      |> assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1'].bg-success"
      )
    end

    @tag :skip
    # FIXME: Validation for empty name needs to be implemented in the form/backend
    test "I see error messages for invalid preset creation", %{conn: conn} do
      conn
      |> visit("/settings/boundaries/acls")
      |> assert_has("button", text: "New preset")
      |> click_button("New preset")
      # Try to create without name
      |> click_button("Create")
      |> assert_has("[data-role='error']", text: "Name is required")
    end
  end
end
