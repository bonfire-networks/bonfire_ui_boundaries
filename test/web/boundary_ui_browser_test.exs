defmodule Bonfire.UI.Boundaries.BoundaryUIBrowserTest do
  use Bonfire.UI.Boundaries.BrowserCase, async: true
  require Phoenix.ConnTest

  alias Bonfire.Boundaries.{Circles, Acls, Grants}

  @cookie_key "_bonfire_key"
  def user_browser_session(session) do
    username = System.get_env("ADMIN_USER", "test_user")
    pw = System.get_env("ADMIN_PASSWORD", "for-testing-only")
    account = fake_account!(%{credential: %{password: pw}})

    user =
      fake_user!(account, %{
        username: username,
        name: username
      })

    # alice = fake_user!()
    # conn = conn(user: alice)
    # conn = Phoenix.ConnTest.get(conn, "/")
    # %{@cookie_key => %{value: token}} = conn.resp_cookies

    user_session =
      session
      |> visit("/login")
      |> fill_in(Query.fillable_field("login_fields[email_or_username]"),
        with: username
      )
      |> fill_in(Query.fillable_field("login_fields[password]"), with: pw)
      # |> Browser.send_keys([:enter])
      |> click(Query.button("Log in"))

    # |> Browser.set_cookie(@cookie_key, token)
  end

  def create_circles_and_preset(user) do
    # Create circles
    {:ok, friends_circle} = Circles.create(user, %{named: %{name: "friends"}})
    {:ok, work_circle} = Circles.create(user, %{named: %{name: "work"}})

    # Create a preset with specific verb permissions
    {:ok, preset_acl} = Acls.create(%{named: %{name: "social"}}, current_user: user)
    [ok: _] = Grants.grant(friends_circle, preset_acl, :read, true, current_user: user)

    %{
      friends_circle: friends_circle,
      work_circle: work_circle,
      preset_acl: preset_acl
    }
  end

  def create_post_with_boundaries(session, circles, text \\ "Testing boundary assignment") do
    session
    |> Browser.visit("/feed")
    # Wait for composer to load
    |> Browser.assert_has(Query.css("#smart_input_container"))
    # Click the boundary settings button
    |> Browser.click(Query.css("[data-role='open_modal']"))
    |> Browser.assert_text("Public")
    # Wait for modal to open and select the preset
    |> Browser.assert_has(Query.css("[data-role='selected_preset']"))
    |> Browser.assert_text("social")
    # Customize verb permissions for the work circle
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{circles.work_circle.id}'][phx-value-verb='read'][phx-value-status='1']"
      )
    )
    |> Browser.click(
      Query.css(
        "button[phx-value-role='#{circles.work_circle.id}'][phx-value-verb='read'][phx-value-status='1']"
      )
    )
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{circles.work_circle.id}'][phx-value-verb='reply'][phx-value-status='1']"
      )
    )
    |> Browser.click(
      Query.css(
        "button[phx-value-role='#{circles.work_circle.id}'][phx-value-verb='reply'][phx-value-status='1']"
      )
    )
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{circles.work_circle.id}'][phx-value-verb='boost'][phx-value-status='0']"
      )
    )
    # Explicitly deny
    |> Browser.click(
      Query.css(
        "button[phx-value-role='#{circles.work_circle.id}'][phx-value-verb='boost'][phx-value-status='0']"
      )
    )
    # Fill in post content and publish
    |> Browser.fill_in(Query.text_field("Share your thoughts"), with: text)
    |> Browser.assert_has(Query.button("Publish"))
    |> Browser.click(Query.button("Publish"))
    |> Browser.assert_has(Query.css("[data-role='success']"))
    |> Browser.assert_text("Published")
  end

  @tag :browser
  feature "can use a preset in composer and customize verb permissions", %{session: session} do
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)

    circles = create_circles_and_preset(me)

    # Add users to circles
    {:ok, _} = Circles.add_to_circles(alice, circles.friends_circle)
    {:ok, _} = Circles.add_to_circles(bob, circles.work_circle)

    user_browser_session(session)
    |> create_post_with_boundaries(circles)
  end

  @tag :browser
  feature "can create boundary preset with custom permissions", %{session: session} do
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)

    # Create circles
    {:ok, friends_circle} = Circles.create(me, %{named: %{name: "friends"}})
    {:ok, family_circle} = Circles.create(me, %{named: %{name: "family"}})

    # Add users to circles
    {:ok, _} = Circles.add_to_circles(alice, friends_circle)
    {:ok, _} = Circles.add_to_circles(bob, family_circle)

    user_browser_session(session)
    |> Browser.visit("/boundaries/acls")
    |> Browser.assert_has(Query.button("New preset"))
    |> Browser.click(Query.button("New preset"))
    |> Browser.fill_in(Query.fillable_field("Enter a name for the boundary preset"),
      with: "close friends"
    )
    |> Browser.click(Query.button("Create"))
    |> Browser.assert_text("close friends")
    # Configure Read permission for friends circle (enable it)
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{friends_circle.id}'][phx-value-verb='read'][phx-value-status='1']"
      )
    )
    |> Browser.click(
      Query.css(
        "button[phx-value-role='#{friends_circle.id}'][phx-value-verb='read'][phx-value-status='1']"
      )
    )
    |> Browser.assert_has(
      Query.css(
        "[phx-value-role='#{friends_circle.id}'][phx-value-verb='read'][phx-value-status='1'].bg-success"
      )
    )
    # Configure Reply and Like permissions for family circle
    |> Browser.click(
      Query.css(
        "button[phx-value-role='#{family_circle.id}'][phx-value-verb='reply'][phx-value-status='1']"
      )
    )
    |> Browser.click(
      Query.css(
        "button[phx-value-role='#{family_circle.id}'][phx-value-verb='like'][phx-value-status='1']"
      )
    )
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{family_circle.id}'][phx-value-verb='reply'][phx-value-status='1'].bg-success"
      )
    )
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{family_circle.id}'][phx-value-verb='like'][phx-value-status='1'].bg-success"
      )
    )
    # Verify the preset is saved and appears in the list
    |> Browser.visit("/boundaries/acls")
    |> Browser.assert_text("close friends")
  end

  @tag :browser
  feature "can configure custom verb permissions with different states", %{session: session} do
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)

    {:ok, circle} = Circles.create(me, %{named: %{name: "bestie"}})
    {:ok, _} = Circles.add_to_circles(alice, circle)

    user_browser_session(session)
    |> Browser.visit("/boundaries/acls")
    |> Browser.assert_has(Query.button("New preset"))
    |> Browser.click(Query.button("New preset"))
    |> Browser.fill_in(Query.fillable_field("Enter a name for the boundary preset"),
      with: "custom perms"
    )
    |> Browser.click(Query.button("Create"))
    |> Browser.assert_text("custom perms")
    # Test different verb permission states
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1']"
      )
    )
    # Allow reading
    |> Browser.click(
      Query.css(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1']"
      )
    )
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1']"
      )
    )
    # Allow replying
    |> Browser.click(
      Query.css(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1']"
      )
    )
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0']"
      )
    )
    # Explicitly deny boosting
    |> Browser.click(
      Query.css(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0']"
      )
    )
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1']"
      )
    )
    # Allow liking
    |> Browser.click(
      Query.css(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1']"
      )
    )
    # Verify the states are set correctly
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1'].bg-success"
      )
    )
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='reply'][phx-value-status='1'].bg-success"
      )
    )
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0'].bg-error"
      )
    )
    |> Browser.assert_has(
      Query.css(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='like'][phx-value-status='1'].bg-success"
      )
    )
  end
end
