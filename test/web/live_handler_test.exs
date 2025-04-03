defmodule Bonfire.UI.Boundaries.FeatureTest do
  use Bonfire.UI.Boundaries.ConnCase, async: true

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
      |> fill_in("Enter a name for the circle", with: "Friends")
      |> click_button("[data-role=new_circle_submit]", "Create")
      # |> assert_path("/circle/friends")
      # |> assert_has("[role=banner]", text: "Circle created!")
      |> assert_has("div", text: "Friends")
    end

    test "Add a user to an existing circle works" do
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      conn = conn(user: me, account: account)
      next = "/circle/#{circle.id}/members"
      {:ok, view, _html} = live(conn, next)

      render_submit(view, "multi_select",
      %{
        data: %{
          "field" => "to_circles",
          "icon" => "/images/avatar.png",
          "id" => "01JQ1V2GQ3JCBM8EZESQ10MP1Z",
          "name" => "Nicolas-Carroll",
          "type" => "user",
          "username" => "Nicolas_Carroll"
        },
        text: "Nicolas-Carroll - Nicolas_Carroll"
      })


      assert render(view) =~ "Added to circle!"
    end

    test "I can remove a user from a circle", %{conn: conn, me: me, account: account} do
      alice = fake_user!(account)
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      {:ok, _} = Circles.add_to_circles(alice, circle)

      conn
      |> visit("/circle/#{circle.id}/members")
      |> click_button("Remove")
      |> assert_has(text: "Removed from circle!")
    end

    test "I can edit circle name", %{conn: conn, me: me, account: account} do
      alice = fake_user!(account)
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      {:ok, _} = Circles.add_to_circles(alice, circle)

      conn
      |> visit("/circle/#{circle.id}")
      |> click_button("[data-role=open_modal]", "Edit circle")
      |> fill_in("Enter a name for the circle", with: "friends")
      |> click_button("Submit")
      |> assert_has(text: "Edited!")
    end

    test "I can delete a circle", %{conn: conn, me: me} do
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})

      conn
      |> visit("/boundaries/circle/#{circle.id}")
      |> click_button("[data-role=open_modal]", "Delete circle")
      |> click_button("[data-role=confirm_delete_circle]", "Delete")
      |> assert_has(text: "Deleted")
    end
  end

  describe "Basic Boundaries actions" do
    test "I can create a boundary", %{conn: conn} do
      conn
      |> visit("/boundaries/acls")
      |> click_button("[data-role=open_modal]", "New preset")
      |> fill_in("Enter a name for the boundary preset", with: "meme")
      |> click_button("[data-role=new_acl_submit]", "Create")
      |> assert_has("[role=banner]", text: "Boundary created!")
      |> assert_has(text: "meme")
    end

    test "I can add a user and assign a role to a boundary", %{conn: conn, me: me, account: account} do
      alice = fake_user!(account)
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)

      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> fill_in("Search for a user or circle", with: alice.id)
      |> submit()
      |> assert_has(text: "finish adding it to the boundary")
      |> choose("Administer")
      |> assert_has(text: "Role assigned")
    end

    test "I can remove a user from a boundary", %{conn: conn, me: me, account: account} do
      alice = fake_user!(account)
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
      Grants.grant_role(alice.id, acl.id, "contribute", current_user: me)

      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> click_button("[data-role=open_modal]", "Remove from boundary")
      |> click_button("[data-role=remove_from_boundary_btn]", "Remove")
      |> assert_has(text: "Removed from boundary")
    end

    test "I can add a circle and assign a role to a boundary", %{conn: conn, me: me, account: account} do
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)

      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> fill_in("Search for a user or circle", with: circle.id)
      |> submit()
      |> assert_has("[date-role=edit-acl]", text: "meme")
      |> choose("Administer")
      |> assert_has(text: "Role assigned")
    end

    test "I can remove a circle from a boundary", %{conn: conn, me: me} do
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
      Grants.grant_role(circle.id, acl.id, "contribute", current_user: me)

      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> click_button("[data-role=open_modal]", "Remove from boundary")
      |> click_button("[data-role=remove_from_boundary_btn]", "Remove")
      |> assert_has(text: "Removed from boundary")
    end

    test "I can edit a role in a boundary", %{conn: conn, me: me, account: account} do
      alice = fake_user!(account)
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)

      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> fill_in("Search for a user or circle", with: alice.id)
      |> submit()
      |> assert_has(text: "finish adding it to the boundary")
      |> choose("Cannot Participate")
      |> assert_has(text: "Role assigned")

      # Verify the current role and change it
      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> assert_has("#edit_grants ul:first-child select option[selected]", text: "Cannot Participate")
      |> choose("Cannot Interact")
      |> assert_has(text: "Role assigned")

      # Verify the role was updated
      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> assert_has("#edit_grants ul:first-child select option[selected]", text: "Cannot Interact")
    end

    test "I can add a user, assign a role to a boundary, and then edit that role", %{conn: conn, me: me, account: account} do
      alice = fake_user!(account)
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)

      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> fill_in("Search for a user or circle", with: alice.id)
      |> submit()
      |> assert_has(text: "finish adding it to the boundary")
      |> choose("Cannot Administer")
      |> assert_has(text: "Role assigned")

      # Verify the current role and change it
      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> assert_has("#edit_grants ul:first-child select option[selected]", text: "Cannot Administer")
      |> choose("Cannot Read")
      |> assert_has(text: "Role assigned")

      # Verify the role was updated
      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> assert_has("#edit_grants ul:first-child select option[selected]", text: "Cannot Read")
    end

    test "I can edit settings of a boundary and delete it", %{conn: conn, me: me} do
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)

      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> click_link("Settings")
      |> fill_in("Name", with: "friends")
      |> click_button("Save")
      |> assert_has(text: "Edited!")
      |> assert_has(text: "friends")

      # Delete the boundary
      conn
      |> visit("/boundaries/acl/#{acl.id}")
      |> click_button("[data-role=open_modal]", "Delete boundary")
      |> click_button("[data-id=delete_boundary]", "Delete")
      |> assert_has(text: "Deleted")
    end
  end
end

# defmodule Bonfire.UI.Boundaries.LiveHandlerTest do
#   use Bonfire.UI.Boundaries.ConnCase, async: true

#   @moduletag :ui

#   alias Bonfire.Social.Fake
#   alias Bonfire.Posts
#   alias Bonfire.Social.Boosts
#   alias Bonfire.Social.Graph.Follows
#   import Bonfire.Common.Enums
#   alias Bonfire.Boundaries.{Circles, Acls, Grants}

#   describe "Basic Circle actions" do
#     test "Create a circle works" do
#       account = fake_account!()
#       me = fake_user!(account)
#       conn = conn(user: me, account: account)
#       next = "/boundaries/circles"
#       {:ok, view, _html} = live(conn, next)
#       #       open_browser(view)

#       view
#       |> element("[data-role=new_circle] div[data-role=open_modal]")
#       |> render_click()

#       assert view |> has_element?("button[data-role=new_circle_submit]")

#       circle_name = "Friends"

#       {:ok, circle_view, html} =
#         view
#         |> form("#modal_box", named: %{name: circle_name})
#         |> render_submit()
#         |> follow_redirect(conn)

#       assert html =~ "Circle created!"
#       #       open_browser(circle_view)
#       assert has_element?(circle_view, "span", circle_name)
#       #       assert circle_view |> has_element?("h1[data-role=circle_title]")
#     end

#     test "Add a user to an existing circle works" do
#       # create a bunch of users
#       account = fake_account!()
#       me = fake_user!(account)
#       alice = fake_user!(account)
#       # create a circle
#       {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
#       # navigate to the circle page
#       conn = conn(user: me, account: account)
#       next = "/boundaries/circle/#{circle.id}"
#       {:ok, view, _html} = live(conn, next)
#       # add alice to the circle via the input form
#       assert view
#              |> form("#edit_circle_participant")
#              |> render_change(%{id: alice.id})

#       assert render(view) =~ "Added to circle!"
#     end

#     test "Remove a user from a circle works" do
#       # create a bunch of users
#       account = fake_account!()
#       me = fake_user!(account)
#       alice = fake_user!(account)
#       # create a circle
#       {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
#       {:ok, _} = Circles.add_to_circles(alice, circle)
#       # navigate to the circle page
#       conn = conn(user: me, account: account)
#       next = "/boundaries/circle/#{circle.id}"
#       {:ok, view, _html} = live(conn, next)

#       assert view
#              |> element("button[data-role=remove_user]")
#              |> render_click()

#       assert render(view) =~ "Removed from circle!"
#     end

#     test "Edit circle name works" do
#       # create a bunch of users
#       account = fake_account!()
#       me = fake_user!(account)
#       alice = fake_user!(account)
#       # create a circle
#       {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
#       {:ok, _} = Circles.add_to_circles(alice, circle)
#       # navigate to the circle page
#       conn = conn(user: me, account: account)
#       next = "/boundaries/circle/#{circle.id}"
#       {:ok, view, _html} = live(conn, next)
#       # open_browser(view)
#       view
#       |> element("li[data-role=edit_circle_name] div[data-role=open_modal]")
#       |> render_click()

#       new_circle_name = "friends"

#       view
#       |> form("#modal_box", named: %{name: new_circle_name})
#       |> render_submit(%{id: circle.id})

#       assert render(view) =~ "Edited!"
#       # WIP ERROR TEST: the circle name is not updated in the view
#       # assert render(view) =~ new_circle_name
#     end

#     test "delete circle works" do
#       # create a bunch of users
#       account = fake_account!()
#       me = fake_user!(account)
#       # create a circle
#       {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
#       # navigate to the circle page
#       conn = conn(user: me, account: account)
#       next = "/boundaries/circle/#{circle.id}"
#       {:ok, view, _html} = live(conn, next)
#       # open_browser(view)
#       view
#       |> element("li[data-role=delete_circle] div[data-role=open_modal]")
#       |> render_click()

#       assert {:ok, circles, _html} =
#                view
#                |> element("button[data-role=confirm_delete_circle]")
#                |> render_click()
#                |> follow_redirect(conn, "/boundaries/circles")

#       assert render(circles) =~ "Deleted"
#       # WIP ERROR TEST: the circle name is not updated in the view
#       # assert render(view) =~ new_circle_name
#     end
#   end

#   describe "Basic Boundaries actions" do
#     test "Create a boundary works" do
#       account = fake_account!()
#       me = fake_user!(account)
#       conn = conn(user: me, account: account)
#       next = "/boundaries/acls"
#       {:ok, view, _html} = live(conn, next)
#       # open_browser(view)
#       view
#       |> element("[data-role=new_acl] div[data-role=open_modal]")
#       |> render_click()

#       assert view |> has_element?("button[data-role=new_acl_submit]")

#       acl_name = "meme"

#       {:ok, acl_view, html} =
#         view
#         |> form("#modal_box", named: %{name: acl_name})
#         |> render_submit()
#         |> follow_redirect(conn)

#       assert html =~ "Boundary created!"
#       assert html =~ acl_name
#     end

#     test "Add a user and assign a role to a boundary works" do
#       # create a bunch of users
#       account = fake_account!()
#       me = fake_user!(account)
#       alice = fake_user!(account)
#       # create a boundary
#       {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
#       # navigate to the boundary page
#       conn = conn(user: me, account: account)
#       next = "/boundaries/acl/#{acl.id}"
#       {:ok, view, _html} = live(conn, next)
#       # add alice to the boundary via the input form
#       assert view
#              |> form("#edit_acl_members")
#              |> render_change(%{id: alice.id})

#       assert render(view) =~ "finish adding it to the boundary"

#       assert view
#              |> form("#edit_grants")
#              |> render_change(%{to_circles: %{alice.id => "administer"}})

#       # open_browser(view)

#       assert render(view) =~ "Role assigned"
#     end

#     test "Remove a user from a boundary works" do
#       # create a bunch of users
#       account = fake_account!()
#       me = fake_user!(account)
#       alice = fake_user!(account)
#       # create a boundary
#       {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
#       Grants.grant_role(alice.id, acl.id, "contribute", current_user: me)
#       # navigate to the boundary page
#       conn = conn(user: me, account: account)
#       next = "/boundaries/acl/#{acl.id}"
#       {:ok, view, _html} = live(conn, next)

#       view
#       |> element("li[data-role=remove_from_boundary] div[data-role=open_modal]")
#       |> render_click()

#       assert view
#              |> element("button[data-role=remove_from_boundary_btn]")
#              |> render_click()

#       assert render(view) =~ "Removed from boundary"
#     end

#     test "Add a circle and assign a role to a boundary works" do
#       # create a bunch of users
#       account = fake_account!()
#       me = fake_user!(account)
#       alice = fake_user!(account)
#       # create a circle
#       {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
#       # create a boundary
#       {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
#       # navigate to the boundary page
#       conn = conn(user: me, account: account)
#       next = "/boundaries/acl/#{acl.id}"
#       {:ok, view, _html} = live(conn, next)
#       # add circle family to the boundary via the input form
#       assert view
#              |> form("#edit_acl_members")
#              |> render_change(%{id: circle.id})

#       #       open_browser(view)

#       assert view
#              |> has_element?("[date-role=edit-acl]", "meme")

#       assert view
#              |> form("#edit_grants")
#              |> render_change(%{to_circles: %{circle.id => "administer"}})

#       assert render(view) =~ "Role assigned"
#     end

#     test "Remove a circle from a boundary works" do
#       # create a bunch of users
#       account = fake_account!()
#       me = fake_user!(account)
#       # create a circle
#       {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
#       # create a boundary
#       {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
#       Grants.grant_role(circle.id, acl.id, "contribute", current_user: me)
#       # navigate to the boundary page
#       conn = conn(user: me, account: account)
#       next = "/boundaries/acl/#{acl.id}"
#       {:ok, view, _html} = live(conn, next)

#       view
#       |> element("li[data-role=remove_from_boundary] div[data-role=open_modal]")
#       |> render_click()

#       assert view
#              |> element("button[data-role=remove_from_boundary_btn]")
#              |> render_click()

#       assert render(view) =~ "Removed from boundary"
#     end

#     test "Edit a role in a boundary works" do
#       # create a bunch of users
#       account = fake_account!()
#       me = fake_user!(account)
#       alice = fake_user!(account)
#       # create a boundary
#       {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
#       # navigate to the boundary page
#       conn = conn(user: me, account: account)
#       next = "/boundaries/acl/#{acl.id}"
#       {:ok, view, _html} = live(conn, next)
#       # add alice to the boundary via the input form
#       assert view
#              |> form("#edit_acl_members")
#              |> render_change(%{id: alice.id})

#       assert render(view) =~ "finish adding it to the boundary"

#       assert view
#              |> form("#edit_grants")
#              |> render_change(%{to_circles: %{alice.id => "cannot_participate"}})

#       assert render(view) =~ "Role assigned"

#       # reload
#       next = "/boundaries/acl/#{acl.id}"
#       {:ok, view, _html} = live(conn, next)

#       # check role is correct
#       assert view
#              |> element("#edit_grants ul:first-child select option[selected]")
#              |> render() =~ "Cannot Participate"

#       # downgrade role
#       assert view
#              |> form("#edit_grants")
#              |> render_change(%{to_circles: %{alice.id => "cannot_interact"}})

#       assert render(view) =~ "Role assigned"

#       # open_browser(view)

#       # reload
#       next = "/boundaries/acl/#{acl.id}"
#       {:ok, view, _html} = live(conn, next)

#       # check role is correct
#       assert view
#              |> element("#edit_grants ul:first-child select option[selected]")
#              |> render() =~ "Cannot Interact"
#     end

#     test "Add a user, assign a role to a boundary, and then edit/downgrade that boundary works" do
#       # create a bunch of users
#       account = fake_account!()
#       me = fake_user!(account)
#       alice = fake_user!(account)
#       # create a boundary
#       {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
#       # navigate to the boundary page
#       conn = conn(user: me, account: account)
#       next = "/boundaries/acl/#{acl.id}"
#       {:ok, view, _html} = live(conn, next)
#       # add alice to the boundary via the input form
#       assert view
#              |> form("#edit_acl_members")
#              |> render_change(%{id: alice.id})

#       assert render(view) =~ "finish adding it to the boundary"

#       assert view
#              |> form("#edit_grants")
#              |> render_change(%{to_circles: %{alice.id => "cannot_administer"}})

#       assert render(view) =~ "Role assigned"

#       # reload
#       next = "/boundaries/acl/#{acl.id}"
#       {:ok, view, _html} = live(conn, next)

#       # check role is correct
#       assert view
#              |> element("#edit_grants ul:first-child select option[selected]")
#              |> render() =~ "Cannot Administer"

#       # downgrade role
#       assert view
#              |> form("#edit_grants")
#              |> render_change(%{to_circles: %{alice.id => "cannot_read"}})

#       assert render(view) =~ "Role assigned"

#       # open_browser(view)

#       # reload
#       next = "/boundaries/acl/#{acl.id}"
#       {:ok, view, _html} = live(conn, next)

#       # check role is correct
#       assert view
#              |> element("#edit_grants ul:first-child select option[selected]")
#              |> render() =~ "Cannot Read"
#     end

#     test "Edit Settings of a boundary works" do
#       # create a bunch of users
#       account = fake_account!()
#       me = fake_user!(account)
#       alice = fake_user!(account)
#       # create a circle
#       {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
#       # navigate to the acl settings page
#       conn = conn(user: me, account: account)
#       next = "/boundaries/acl/#{acl.id}"
#       {:ok, view, _html} = live(conn, next)

#       #       click on the settings button
#       view
#       |> element("li[data-role=edit_acl_settings]")
#       |> render_click()

#       new_acl_name = "friends"

#       #       open_browser(view)
#       assert view
#              |> form("#edit_acl", named: %{name: new_acl_name})
#              |> render_submit()

#       assert render(view) =~ "Edited!"
#       assert render(view) =~ new_acl_name

#       # WIP: the view is not updated instantly
#       view
#       |> element("div[data-role=delete_boundary_modal] div[data-role=open_modal]")
#       |> render_click()

#       assert {:ok, acls, _html} =
#                view
#                |> element("button[data-id=delete_boundary]")
#                |> render_click()
#                |> follow_redirect(conn, "/boundaries/acls")

#       assert render(acls) =~ "Deleted"
#     end
#   end
# end
