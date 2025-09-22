defmodule Bonfire.UI.Boundaries.BoundaryUIManagementTest do
  use Bonfire.UI.Boundaries.ConnCase, async: true
  @moduletag :ui

  alias Bonfire.Social.Fake
  alias Bonfire.Posts
  alias Bonfire.Boundaries.{Circles, Acls, Grants}
  import Bonfire.Common.Enums

  setup do
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)
    carl = fake_user!(account)

    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, me: me, alice: alice, bob: bob, carl: carl}
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
      |> PhoenixTest.visit("/boundaries/acls")
      |> PhoenixTest.assert_has("button", text: "New preset")
      |> click_button("New preset")
      |> PhoenixTest.fill_in("Enter a name for the boundary preset", with: "close friends")
      |> click_button("Create")
      |> PhoenixTest.assert_has("div", text: "close friends")

      # Configure Read permission for friends circle (enable it)
      # |> PhoenixTest.open_browser()
      |> PhoenixTest.assert_has(
        "button[phx-value-role='#{friends_circle.id}'][phx-value-verb='read'][phx-value-status='1']"
      )
      |> click_button(
        "button[phx-value-role='#{friends_circle.id}'][phx-value-verb='read'][phx-value-status='1']",
        "Can"
      )
      |> PhoenixTest.assert_has(
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
      |> PhoenixTest.assert_has(
        "button[phx-value-role='#{family_circle.id}'][phx-value-verb='reply'][phx-value-status='1'].bg-success"
      )
      |> PhoenixTest.assert_has(
        "button[phx-value-role='#{family_circle.id}'][phx-value-verb='like'][phx-value-status='1'].bg-success"
      )

      # Verify the preset is saved and appears in the list
      |> PhoenixTest.visit("/boundaries/acls")
      |> PhoenixTest.assert_has("div", text: "close friends")
    end

    test "I can configure custom verb permissions with different states", %{
      conn: conn,
      me: me,
      alice: alice
    } do
      {:ok, circle} = Circles.create(me, %{named: %{name: "bestie"}})
      {:ok, _} = Circles.add_to_circles(alice, circle)

      conn
      |> PhoenixTest.visit("/boundaries/acls")
      |> PhoenixTest.assert_has("button", text: "New preset")
      |> PhoenixTest.click_button("New preset")
      |> PhoenixTest.fill_in("Enter a name for the boundary preset", with: "custom perms")
      |> PhoenixTest.click_button("Create")
      |> PhoenixTest.assert_has("div", text: "custom perms")

      # Test different verb permission states
      |> PhoenixTest.assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1']"
      )
      # Allow reading
      |> PhoenixTest.click_button(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1']",
        "Can"
      )
      |> PhoenixTest.assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1']"
      )
      # Allow replying
      |> PhoenixTest.click_button(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1']",
        "Can"
      )
      |> PhoenixTest.assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0']"
      )
      # Explicitly deny boosting
      |> PhoenixTest.click_button(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0']",
        "Cannot"
      )
      |> PhoenixTest.assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1']"
      )
      # Allow liking
      |> PhoenixTest.click_button(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1']",
        "Can"
      )

      # Verify the states are set correctly
      # |> PhoenixTest.open_browser()
      |> PhoenixTest.assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1'].bg-success"
      )
      |> PhoenixTest.assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1'].bg-success"
      )
      |> PhoenixTest.assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0'].bg-error"
      )
      |> PhoenixTest.assert_has(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1'].bg-success"
      )
    end

    test "I see error messages for invalid preset creation", %{conn: conn} do
      conn
      |> PhoenixTest.visit("/boundaries/acls")
      |> PhoenixTest.assert_has("button", text: "New preset")
      |> PhoenixTest.click_button("New preset")
      # Try to create without name
      |> PhoenixTest.click_button("Create")
      |> PhoenixTest.assert_has("[data-role='error']", text: "Name is required")
    end
  end

  describe "Assign Boundary Preset in Composer with Custom Permissions" do
    # Note: Wallaby tests have been moved to boundary_ui_browser_test.exs

    # test "I can override preset permissions in composer", %{conn: conn, me: me, alice: alice} do
    #   {:ok, circle} = Circles.create(me, %{named: %{name: "test_circle"}})
    #   {:ok, _} = Circles.add_to_circles(alice, circle)

    #   # Create preset with read-only permissions
    #   {:ok, preset_acl} = Acls.create(%{named: %{name: "read_only"}}, current_user: me)
    #   [ok: _] = Grants.grant(circle, preset_acl, :read, true, current_user: me)

    #   conn
    #   |> PhoenixTest.visit("/compose")
    #   |> fill_in("Share your thoughts", with: "Testing permission override")
    #   |> PhoenixTest.assert_has("button[data-role='boundary_settings']")
    #   |> click_button("button[data-role='boundary_settings']", "Custom")
    #   |> PhoenixTest.assert_has("button", text: "Custom")
    #   |> click_button("Custom")
    #   |> PhoenixTest.assert_has("button", text: "read_only")
    #   |> click_button("read_only")

    #   # Override the preset to add more verb permissions beyond what the preset allows
    #   |> PhoenixTest.assert_has("button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1']")
    #   |> click_button("button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1']", "Can") # Add reply
    #   |> PhoenixTest.assert_has("button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1']")
    #   |> click_button("button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1']", "Can")   # Add like

    #   |> PhoenixTest.assert_has("button", text: "Publish")
    #   |> click_button("Publish")
    #   |> PhoenixTest.assert_has("[data-role='success']", text: "Published")
    # end

    # test "I see boundary summary with configured verbs before publishing", %{conn: conn, me: me, alice: alice} do
    #   {:ok, circle} = Circles.create(me, %{named: %{name: "summary_test"}})
    #   {:ok, _} = Circles.add_to_circles(alice, circle)

    #   conn
    #   |> PhoenixTest.visit("/compose")
    #   |> fill_in("Share your thoughts", with: "Testing boundary summary")
    #   |> click_button("[data-role='boundary_settings']")
    #   |> click_button("Local")

    #   # Configure some permissions
    #   |> click_button("[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1']")
    #   |> click_button("[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1']")

    #   # Check that boundary summary shows the configured permissions
    #   |> PhoenixTest.assert_has("[data-role='boundary_summary']")
    #   |> PhoenixTest.assert_has("[data-role='boundary_summary']", text: "Local")
    #   |> PhoenixTest.assert_has("[data-role='boundary_summary']", text: "summary_test")
    # end
  end

  # describe "Edit an Existing Boundary Preset" do
  #   test "I can edit an existing boundary preset verb permissions", %{conn: conn, me: me, alice: alice, bob: bob} do
  #     # Create circles
  #     {:ok, friends_circle} = Circles.create(me, %{named: %{name: "friends"}})
  #     {:ok, family_circle} = Circles.create(me, %{named: %{name: "family"}})
  #     {:ok, _} = Circles.add_to_circles(alice, friends_circle)
  #     {:ok, _} = Circles.add_to_circles(bob, family_circle)

  #     # Create an existing preset with basic permissions
  #     {:ok, preset_acl} = Acls.create(%{named: %{name: "editable_preset"}}, current_user: me)
  #     [ok: _] = Grants.grant(friends_circle, preset_acl, :read, true, current_user: me)

  #     # Navigate to edit the preset
  #     conn
  #     |> PhoenixTest.visit("/boundaries/acl/#{preset_acl.id}")
  #     |> PhoenixTest.assert_has("h1", text: "editable_preset")

  #     # Configure verb permissions for family circle
  #     |> click_button("[phx-value-role='#{family_circle.id}'][phx-value-verb='reply'][phx-value-status='1']")
  #     |> click_button("[phx-value-role='#{family_circle.id}'][phx-value-verb='like'][phx-value-status='1']")

  #     # Modify existing friends circle permissions (add more verbs)
  #     |> click_button("[phx-value-role='#{friends_circle.id}'][phx-value-verb='reply'][phx-value-status='1']")
  #     |> click_button("[phx-value-role='#{friends_circle.id}'][phx-value-verb='boost'][phx-value-status='1']")

  #     # Verify changes are reflected in UI
  #     |> PhoenixTest.assert_has("[phx-value-role='#{family_circle.id}'][phx-value-verb='reply'][phx-value-status='1'].bg-neutral")
  #     |> PhoenixTest.assert_has("[phx-value-role='#{friends_circle.id}'][phx-value-verb='boost'][phx-value-status='1'].bg-neutral")
  #   end

  #   test "I can modify verb permissions for existing circles in preset", %{conn: conn, me: me, alice: alice} do
  #     {:ok, circle} = Circles.create(me, %{named: %{name: "permission_test"}})
  #     {:ok, _} = Circles.add_to_circles(alice, circle)

  #     # Create preset with basic read permission
  #     {:ok, preset_acl} = Acls.create(%{named: %{name: "upgradeable"}}, current_user: me)
  #     [ok: _] = Grants.grant(circle, preset_acl, :read, true, current_user: me)

  #     conn
  #     |> PhoenixTest.visit("/boundaries/acl/#{preset_acl.id}")
  #     |> PhoenixTest.assert_has("[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1'].bg-neutral")

  #     # Add more verb permissions
  #     |> click_button("[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1']")
  #     |> click_button("[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1']")
  #     |> click_button("[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='1']")
  #     |> click_button("[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='0']") # Remove read permission

  #     # Verify the changes
  #     |> PhoenixTest.assert_has("[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1'].bg-neutral")
  #     |> PhoenixTest.assert_has("[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1'].bg-neutral")
  #     |> PhoenixTest.assert_has("[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='1'].bg-neutral")
  #     |> PhoenixTest.assert_has("[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='0'].bg-neutral")

  #     # Verify the changes persist by refreshing
  #     |> PhoenixTest.visit("/boundaries/acl/#{preset_acl.id}")
  #     |> PhoenixTest.assert_has("[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1'].bg-neutral")
  #     |> PhoenixTest.assert_has("[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1'].bg-neutral")
  #     |> PhoenixTest.assert_has("[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='1'].bg-neutral")
  #     |> PhoenixTest.assert_has("[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='0'].bg-neutral")
  #   end

  #   test "I can remove circles by setting all verbs to undefined", %{conn: conn, me: me, alice: alice, bob: bob} do
  #     {:ok, friends_circle} = Circles.create(me, %{named: %{name: "friends"}})
  #     {:ok, family_circle} = Circles.create(me, %{named: %{name: "family"}})
  #     {:ok, _} = Circles.add_to_circles(alice, friends_circle)
  #     {:ok, _} = Circles.add_to_circles(bob, family_circle)

  #     # Create preset with multiple circles
  #     {:ok, preset_acl} = Acls.create(%{named: %{name: "multi_circle"}}, current_user: me)
  #     [ok: _] = Grants.grant(friends_circle, preset_acl, :read, true, current_user: me)
  #     [ok: _] = Grants.grant(family_circle, preset_acl, :reply, true, current_user: me)

  #     conn
  #     |> PhoenixTest.visit("/boundaries/acl/#{preset_acl.id}")
  #     |> PhoenixTest.assert_has("[phx-value-role='#{friends_circle.id}'][phx-value-verb='read'][phx-value-status='1'].bg-neutral")
  #     |> PhoenixTest.assert_has("[phx-value-role='#{family_circle.id}'][phx-value-verb='reply'][phx-value-status='1'].bg-neutral")

  #     # "Remove" the family circle by setting all its permissions to undefined
  #     |> click_button("[phx-value-role='#{family_circle.id}'][phx-value-verb='reply'][phx-value-status='']")
  #     |> PhoenixTest.assert_has("[phx-value-role='#{family_circle.id}'][phx-value-verb='reply'][phx-value-status=''].bg-neutral")

  #     # Friends circle should remain active
  #     |> PhoenixTest.assert_has("[phx-value-role='#{friends_circle.id}'][phx-value-verb='read'][phx-value-status='1'].bg-neutral")
  #   end
  # end

  # describe "Boundary Permissions Verification" do
  #   test "users can only see posts based on their verb permissions", %{conn: conn, me: me, alice: alice, bob: bob, carl: carl} do
  #     # Create circles with different users
  #     {:ok, friends_circle} = Circles.create(me, %{named: %{name: "friends"}})
  #     {:ok, family_circle} = Circles.create(me, %{named: %{name: "family"}})
  #     {:ok, _} = Circles.add_to_circles(alice, friends_circle)
  #     {:ok, _} = Circles.add_to_circles(bob, family_circle)
  #     # Carl is not in any circle

  #     # Create a post with custom boundary (friends can read, family can reply and like)
  #     html_body = "Testing boundary verification"
  #     attrs = %{post_content: %{html_body: html_body}}

  #     {:ok, post} =
  #       Posts.publish(
  #         current_user: me,
  #         post_attrs: attrs,
  #         boundary: "custom",
  #         to_circles: %{
  #           friends_circle.id => %{read: true},
  #           family_circle.id => %{reply: true, like: true}
  #         }
  #       )

  #     # Me (creator) should see the post with all interaction options
  #     conn
  #     |> PhoenixTest.visit("/post/#{post.id}")
  #     |> PhoenixTest.assert_has("article", text: html_body)

  #     # Alice (friends circle, read permission) should see the post but limited interactions
  #     conn(user: alice, account: alice.account)
  #     |> PhoenixTest.visit("/post/#{post.id}")
  #     |> PhoenixTest.assert_has("article", text: html_body)
  #     |> refute_has("[data-role='reply_enabled']")
  #     |> refute_has("[data-role='boost_enabled']")

  #     # Bob (family circle, reply + like permissions) should see and interact with specific verbs
  #     conn(user: bob, account: bob.account)
  #     |> PhoenixTest.visit("/post/#{post.id}")
  #     |> PhoenixTest.assert_has("article", text: html_body)
  #     |> PhoenixTest.assert_has("[data-role='reply_enabled']")
  #     |> PhoenixTest.assert_has("[data-role='like_enabled']")
  #     |> refute_has("[data-role='boost_enabled']") # Not granted boost permission

  #     # Carl (no permissions) should not see the post
  #     conn(user: carl, account: carl.account)
  #     |> PhoenixTest.visit("/post/#{post.id}")
  #     |> refute_has("article", text: html_body)
  #   end

  #   test "preset boundaries work correctly when applied to posts", %{conn: conn, me: me, alice: alice, bob: bob} do
  #     {:ok, circle} = Circles.create(me, %{named: %{name: "preset_test"}})
  #     {:ok, _} = Circles.add_to_circles(alice, circle)

  #     # Create a preset with specific verb permissions
  #     {:ok, preset_acl} = Acls.create(%{named: %{name: "test_preset"}}, current_user: me)
  #     [ok: _] = Grants.grant(circle, preset_acl, :read, true, current_user: me)
  #     [ok: _] = Grants.grant(circle, preset_acl, :like, true, current_user: me)

  #     # Create a post using the preset
  #     attrs = %{post_content: %{html_body: "Preset boundary test"}}

  #     {:ok, post} =
  #       Posts.publish(
  #         current_user: me,
  #         post_attrs: attrs,
  #         boundary: preset_acl.id
  #       )

  #     # Alice should be able to read and like, but not reply or boost
  #     conn(user: alice, account: alice.account)
  #     |> PhoenixTest.visit("/post/#{post.id}")
  #     |> PhoenixTest.assert_has("article", text: "Preset boundary test")
  #     |> PhoenixTest.assert_has("[data-role='like_enabled']")
  #     |> refute_has("[data-role='reply_enabled']")
  #     |> refute_has("[data-role='boost_enabled']")

  #     # Bob (not in circle) should not see the post
  #     conn(user: bob, account: bob.account)
  #     |> PhoenixTest.visit("/post/#{post.id}")
  #     |> refute_has("article", text: "Preset boundary test")
  #   end
  # end

  # describe "Error Handling and Edge Cases" do
  #   test "I see appropriate errors when trying to edit a preset I don't own", %{alice: alice, me: me} do
  #     # Create a preset as alice
  #     {:ok, alice_preset} = Acls.create(%{named: %{name: "alice_preset"}}, current_user: alice)

  #     # Try to edit as me (should fail)
  #     conn(user: me, account: me.account)
  #     |> PhoenixTest.visit("/boundaries/acl/#{alice_preset.id}")
  #     |> PhoenixTest.assert_has("[data-role='error']", text: "You don't have permission to edit this boundary")
  #   end

  #   test "I can handle circles being deleted while editing boundaries", %{conn: conn, me: me, alice: alice} do
  #     {:ok, circle} = Circles.create(me, %{named: %{name: "temp_circle"}})
  #     {:ok, _} = Circles.add_to_circles(alice, circle)

  #     {:ok, preset_acl} = Acls.create(%{named: %{name: "temp_preset"}}, current_user: me)
  #     [ok: _] = Grants.grant(circle, preset_acl, :read, true, current_user: me)

  #     # Start editing the preset
  #     conn
  #     |> PhoenixTest.visit("/boundaries/acl/#{preset_acl.id}")
  #     |> PhoenixTest.assert_has("[phx-value-role='#{circle.id}']")

  #     # Simulate circle being deleted (in another process/tab)
  #     Circles.delete(circle)

  #     # Continue editing - should handle gracefully
  #     |> PhoenixTest.visit("/boundaries/acl/#{preset_acl.id}")
  #     |> refute_has("[phx-value-role='#{circle.id}']")
  #     |> PhoenixTest.assert_has("[data-role='info']", text: "Some circles may have been removed")
  #   end

  #   test "I see helpful messages when no circles exist", %{conn: conn} do
  #     conn
  #     |> PhoenixTest.visit("/boundaries/acls")
  #     |> click_button("New preset")
  #     |> fill_in("Enter a name for the boundary preset", with: "empty_test")
  #     |> click_button("Create")
  #     |> PhoenixTest.assert_has("[data-role='empty_circles_message']", text: "No circles found")
  #     |> PhoenixTest.assert_has("[data-role='create_circle_link']", text: "Create your first circle")
  #   end

  #   test "I can toggle verb permissions between all three states", %{conn: conn, me: me, alice: alice} do
  #     {:ok, circle} = Circles.create(me, %{named: %{name: "toggle_test"}})
  #     {:ok, _} = Circles.add_to_circles(alice, circle)

  #     conn
  #     |> PhoenixTest.visit("/boundaries/acls")
  #     |> click_button("New preset")
  #     |> fill_in("Enter a name for the boundary preset", with: "toggle_test")
  #     |> click_button("Create")

  #     # Test cycling through all three states for a verb
  #     # Start undefined -> Can -> Cannot -> Undefined
  #     |> click_button("[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1']") # Set to Can
  #     |> PhoenixTest.assert_has("[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1'].bg-neutral")
  #     |> click_button("[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='0']") # Set to Cannot
  #     |> PhoenixTest.assert_has("[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='0'].bg-neutral")
  #     |> click_button("[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='']") # Set to Undefined
  #     |> PhoenixTest.assert_has("[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status=''].bg-neutral")
  #   end
  # end
end
