defmodule Bonfire.UI.Boundaries.FeatureTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"

  alias Bonfire.Social.Fake
  alias Bonfire.Posts
  alias Bonfire.Social.Boosts
  alias Bonfire.Social.Graph.Follows
  import Bonfire.Common.Enums
  alias Bonfire.Boundaries.{Circles, Acls, Grants}

  setup do
    account = fake_account!()
    me = fake_user!(account)

    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, me: me}
  end

  describe "Basic Circle actions" do
    test "I can create a circle", %{conn: conn} do
      conn
      |> visit("/boundaries/circles")
      |> click_button("[data-role=open_modal]", "New circle")
      |> fill_in("Enter a name for the circle", with: "Friends", exact: false)
      |> click_button("[data-role=new_circle_submit]", "Create")
      # |> assert_path("/circle/friends")
      # |> assert_has("[role=banner]", text: "Circle created!")
      |> assert_has("div", text: "Friends")
    end

    @tag :skip
    test "Add a user to an existing circle works" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)

      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      conn = conn(user: me, account: account)
      next = "/circle/#{circle.id}/members"
      {:ok, view, _html} = live(conn, next)

      assert render_submit(view, "Bonfire.UI.Boundaries.CircleMembersLive:multi_select", %{
               "data" => %{
                 "field" => "to_circles",
                 "icon" => "/images/avatar.png",
                 "id" => id(alice),
                 "name" => "alice",
                 "type" => "user",
                 "username" => "alice"
               },
               "text" => "alice"
             }) =~ "Added to circle!"
    end

    test "I can remove a user from a circle", %{conn: conn, me: me, account: account} do
      alice = fake_user!(account)
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      {:ok, _} = Circles.add_to_circles(alice, circle)

      conn
      |> visit("/circle/#{circle.id}/members")
      |> click_button("Remove")
      |> assert_has("[role=alert]", text: "Removed from circle!")
    end

    test "I can edit circle name", %{conn: conn, me: me, account: account} do
      alice = fake_user!(account)
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      {:ok, _} = Circles.add_to_circles(alice, circle)

      conn
      |> visit("/circle/#{circle.id}")
      |> click_button("[data-role=open_modal]", "Edit circle")
      |> PhoenixTest.open_browser()

      # |> within("#edit_circle_general", fn conn ->
      #   conn
      #   |> fill_in("Circle name", with: "friends")
      #   |> click_button("Save")
      # end)
      # |> assert_has("[role=alert]", text: "Edited!")
    end

    test "I can delete a circle", %{conn: conn, me: me} do
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})

      conn
      |> visit("/circle/#{circle.id}")
      |> click_button("[data-role=open_modal]", "Edit circle")
      |> click_button("[data-role=confirm_delete_circle]", "Delete")
      # |> PhoenixTest.open_browser()
      |> assert_path("/boundaries/circles")

      # |> assert_has("[role=alert]", text: "Deleted")
    end

    test "I can assign a user to a circle from the user profile", %{
      conn: conn,
      me: me
    } do
      {:ok, circle} = Bonfire.Boundaries.Circles.create(me, %{named: %{name: "family"}})
      alice = fake_user!()

      conn
      |> visit("/@#{alice.character.username}")
      |> click_button("[data-id=profile_main_actions] [data-role=open_modal]", "Add to circles")
      |> click_button("[data-role=add_to_circle]", "family")
      |> assert_has("[role=alert]", text: "Added to circle!")
    end
  end

  describe "Basic Boundaries actions" do
    test "I can create a boundary", %{conn: conn, me: me} do
      conn
      |> visit("/boundaries/acls")
      |> click_button("[data-role=open_modal]", "New preset")
      |> fill_in("Enter a name for the boundary preset", with: "meme")
      |> click_button("[data-role=new_acl_submit]", "Create")
      |> wait_async()

      # Verify ACL was created by checking user's ACL list
      my_acls = Acls.list_my(me)
      assert Enum.any?(my_acls, fn acl -> acl.named.name == "meme" end)
    end

    @tag :skip
    # FIXME: UI now uses MultiselectLive (LiveSelect) for searching/adding circles to boundaries
    # instead of showing a list of circle buttons. Test needs to be rewritten to interact with
    # the search input and selection flow.
    test "I can add a circle and assign a role to a boundary", %{
      conn: conn,
      me: me,
      account: account
    } do
      alice = fake_user!(account)
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})

      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> within("#edit_acl_members", fn conn ->
        conn
        |> click_button("[data-role=add-circle-to-acl]", "family")
      end)
      |> assert_has("[role=alert]",
        text: "Select a role (or custom permissions) to finish adding it to the boundary."
      )
      |> click_button("[data-role=open_modal]", "Edit role")
      |> within("#edit_grants", fn conn ->
        conn
        |> choose("Administer")
      end)
      |> assert_has("[role=alert]", text: "Role assigned")
    end

    @tag :skip
    # FIXME: UI changed from EditAclLive (with Remove buttons) to SetBoundariesLive (verb-based permissions).
    # Removal UX needs to be redesigned or test rewritten for new flow.
    test "I can remove a user from a boundary", %{conn: conn, me: me, account: account} do
      alice = fake_user!(account)
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
      Grants.grant_role(alice.id, acl.id, "contribute", current_user: me)

      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> wait_async()
      |> within("[data-role=remove_from_boundary]", fn session ->
        click_button(session, "[data-role=open_modal]", "Remove")
      end)
      |> click_button("[data-role=remove_from_boundary_btn]", "Remove")
      |> assert_has("[role=alert]", text: "Removed from boundary")
    end

    test "I can view a boundary with assigned permissions", %{
      conn: conn,
      me: me,
      account: account
    } do
      alice = fake_user!(account)
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
      Grants.grant_role(alice.id, acl.id, "contribute", current_user: me)

      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> wait_async()
      # Verify we're on the correct boundary page
      |> assert_path("/boundaries/acl/#{acl.id}")
    end

    # test "I can add a circle and assign a role to a boundary", %{
    #   conn: conn,
    #   me: me,
    #   account: account
    # } do
    #   {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
    #   {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)

    #   conn
    #   |> visit("/boundaries/acl/#{acl.id}")
    #   |> fill_in("Search for a user or circle", with: circle.id)
    #   |> submit()
    #   |> assert_has("[date-role=edit-acl]", text: "meme")
    #   |> choose("Administer")
    #   |> assert_has(text: "Role assigned")
    # end

    # test "I can remove a circle from a boundary", %{conn: conn, me: me} do
    #   {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
    #   {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
    #   Grants.grant_role(circle.id, acl.id, "contribute", current_user: me)

    #   conn
    #   |> visit("/boundaries/acl/#{acl.id}")
    #   |> click_button("[data-role=open_modal]", "Remove from boundary")
    #   |> click_button("[data-role=remove_from_boundary_btn]", "Remove")
    #   |> assert_has(text: "Removed from boundary")
    # end

    @tag :skip
    # FIXME: EditAclButtonLive is sent via async send_self to page_header_aside,
    # which doesn't work reliably in tests. Need to investigate async page updates in test env.
    test "I can edit settings of a boundary and delete it", %{conn: conn, me: me} do
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)

      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> wait_async()
      |> click_button("[data-role=edit_boundary] [data-role=open_modal]", "Edit")
      |> within("#edit_acl", fn conn ->
        conn
        |> fill_in("Edit the boundary preset name", with: "friends")
        |> click_button("Save")
      end)
      |> assert_has("[role=alert]", text: "Edited!")

      # Delete the boundary
      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> wait_async()
      |> click_button("[data-role=edit_boundary] [data-role=open_modal]", "Edit")
      |> click_button("[data-role=open_modal]", "Delete")
      |> click_button("[data-id=delete_boundary]", "Delete this boundary preset")
      |> assert_path("/boundaries/acls")
    end

    @tag :skip
    # FIXME: Custom boundaries are now in a dropdown/modal that must be opened first.
    # Test needs to click the boundary picker button before asserting.
    test "I can pick the preset previously created from the list of presets on composer", %{
      conn: conn,
      me: me
    } do
      {:ok, acl} = Bonfire.Boundaries.Acls.create(%{named: %{name: "New ACL"}}, current_user: me)

      conn
      |> visit("/dashboard")
      |> wait_async()
      |> assert_has("[data-role=custom_boundary]", text: "New ACL")
    end
  end
end
