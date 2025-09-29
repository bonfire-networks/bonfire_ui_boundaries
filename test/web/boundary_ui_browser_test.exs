defmodule Bonfire.UI.Boundaries.BoundaryUIBrowserTest do
  use Bonfire.UI.Boundaries.BrowserCase, async: true

  alias Bonfire.Boundaries.{Circles, Acls, Grants}

  @tag :browser
  feature "can use a preset in composer and customize verb permissions", %{session: session} do
    # First get the logged-in user from browser session
    {user_session, me} = user_browser_session(session)

    # Create additional users for the test
    account = fake_account!()
    alice = fake_user!(account)
    bob = fake_user!(account)

    # Create circles and preset using the logged-in user
    circles = create_circles_and_preset(me)

    # Add users to circles
    {:ok, _} = Circles.add_to_circles(alice, circles.friends_circle)
    {:ok, _} = Circles.add_to_circles(bob, circles.work_circle)
    text = "Testing boundary assignment"

    user_session
    |> open_composer()
    |> open_boundary_modal()
    |> edit_permission("edit", circles.work_circle.id, 1)
    |> edit_default_boundary("local")
    |> close_boundary_modal()
    |> compose(text)
    |> publish()
    |> navigate_to_post()
    |> open_boundary_details()

  end



  feature "can switch from public to local preset", %{session: session} do

  end

  feature "can add a user to the boundary and remove a permission", %{session: session} do

  end

  feature "can add a user to the boundary and grant a permission", %{session: session} do

  end

  @tag :browser
  # feature "can create boundary preset with custom permissions", %{session: session} do
  #   account = fake_account!()
  #   me = fake_user!(account)
  #   alice = fake_user!(account)
  #   bob = fake_user!(account)

  #   # Create circles
  #   {:ok, friends_circle} = Circles.create(me, %{named: %{name: "friends"}})
  #   {:ok, family_circle} = Circles.create(me, %{named: %{name: "family"}})

  #   # Add users to circles
  #   {:ok, _} = Circles.add_to_circles(alice, friends_circle)
  #   {:ok, _} = Circles.add_to_circles(bob, family_circle)

  #   user_browser_session(session)
  #   |> Browser.visit("/boundaries/acls")
  #   |> Browser.assert_has(Query.button("New preset"))
  #   |> Browser.click(Query.button("New preset"))
  #   |> Browser.fill_in(Query.fillable_field("Enter a name for the boundary preset"),
  #     with: "close friends"
  #   )
  #   |> Browser.click(Query.button("Create"))
  #   |> Browser.assert_text("close friends")
  #   # Configure Read permission for friends circle (enable it)
  #   |> Browser.assert_has(
  #     Query.css(
  #       "button[phx-value-role='#{friends_circle.id}'][phx-value-verb='read'][phx-value-status='1']"
  #     )
  #   )
  #   |> Browser.click(
  #     Query.css(
  #       "button[phx-value-role='#{friends_circle.id}'][phx-value-verb='read'][phx-value-status='1']"
  #     )
  #   )
  #   |> Browser.assert_has(
  #     Query.css(
  #       "[phx-value-role='#{friends_circle.id}'][phx-value-verb='read'][phx-value-status='1'].bg-success"
  #     )
  #   )
  #   # Configure Reply and Like permissions for family circle
  #   |> Browser.click(
  #     Query.css(
  #       "button[phx-value-role='#{family_circle.id}'][phx-value-verb='reply'][phx-value-status='1']"
  #     )
  #   )
  #   |> Browser.click(
  #     Query.css(
  #       "button[phx-value-role='#{family_circle.id}'][phx-value-verb='like'][phx-value-status='1']"
  #     )
  #   )
  #   |> Browser.assert_has(
  #     Query.css(
  #       "button[phx-value-role='#{family_circle.id}'][phx-value-verb='reply'][phx-value-status='1'].bg-success"
  #     )
  #   )
  #   |> Browser.assert_has(
  #     Query.css(
  #       "button[phx-value-role='#{family_circle.id}'][phx-value-verb='like'][phx-value-status='1'].bg-success"
  #     )
  #   )
  #   # Verify the preset is saved and appears in the list
  #   |> Browser.visit("/boundaries/acls")
  #   |> Browser.assert_text("close friends")
  # end

  @tag :browser
  # feature "can configure custom verb permissions with different states", %{session: session} do
  #   account = fake_account!()
  #   me = fake_user!(account)
  #   alice = fake_user!(account)

  #   {:ok, circle} = Circles.create(me, %{named: %{name: "bestie"}})
  #   {:ok, _} = Circles.add_to_circles(alice, circle)

  #   user_browser_session(session)
  #   |> Browser.visit("/boundaries/acls")
  #   |> Browser.assert_has(Query.button("New preset"))
  #   |> Browser.click(Query.button("New preset"))
  #   |> Browser.fill_in(Query.fillable_field("Enter a name for the boundary preset"),
  #     with: "custom perms"
  #   )
  #   |> Browser.click(Query.button("Create"))
  #   |> Browser.assert_text("custom perms")
  #   # Test different verb permission states
  #   |> Browser.assert_has(
  #     Query.css(
  #       "button[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1']"
  #     )
  #   )
  #   # Allow reading
  #   |> Browser.click(
  #     Query.css(
  #       "button[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1']"
  #     )
  #   )
  #   |> Browser.assert_has(
  #     Query.css(
  #       "button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1']"
  #     )
  #   )
  #   # Allow replying
  #   |> Browser.click(
  #     Query.css(
  #       "button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1']"
  #     )
  #   )
  #   |> Browser.assert_has(
  #     Query.css(
  #       "button[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0']"
  #     )
  #   )
  #   # Explicitly deny boosting
  #   |> Browser.click(
  #     Query.css(
  #       "button[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0']"
  #     )
  #   )
  #   |> Browser.assert_has(
  #     Query.css(
  #       "button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1']"
  #     )
  #   )
  #   # Allow liking
  #   |> Browser.click(
  #     Query.css(
  #       "button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1']"
  #     )
  #   )
  #   # Verify the states are set correctly
  #   |> Browser.assert_has(
  #     Query.css(
  #       "button[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1'].bg-success"
  #     )
  #   )
  #   |> Browser.assert_has(
  #     Query.css(
  #       "button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1'].bg-success"
  #     )
  #   )
  #   |> Browser.assert_has(
  #     Query.css(
  #       "button[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0'].bg-error"
  #     )
  #   )
  #   |> Browser.assert_has(
  #     Query.css(
  #       "button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1'].bg-success"
  #     )
  #   )
  # end
end
