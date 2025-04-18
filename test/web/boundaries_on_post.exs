defmodule Bonfire.UI.Boundaries.OnPostTest do
  use Bonfire.UI.Boundaries.ConnCase, async: true
  @moduletag :ui

  alias Bonfire.Social.Fake
  alias Bonfire.Posts
  alias Bonfire.Social.Boosts
  alias Bonfire.Social.Graph.Follows
  import Bonfire.Common.Enums
  alias Bonfire.Boundaries.Circles

  test "Test creating a post with a 'custom' boundary and verify that only users that belong to the circle selected can read the post." do
    # create a bunch of users
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)
    carl = fake_user!(account)
    # create a circle with alice and bob
    {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
    {:ok, _} = Circles.add_to_circles(alice, circle)
    {:ok, _} = Circles.add_to_circles(bob, circle)

    # create a post with custom boundary and add family to to_circle
    html_body = "epic html message"
    attrs = %{post_content: %{html_body: html_body}}

    {:ok, post} =
      Posts.publish(
        current_user: me,
        post_attrs: attrs,
        boundary: "custom",
        to_circles: %{circle.id => "read"}
      )

    # login as myself and verify that I can see the post
    conn = conn(user: me, account: account)
    {:ok, view, _html} = live(conn, "/post/#{post.id}")
    # open_browser(view)
    assert has_element?(view, "article", html_body)

    # login as alice and verify that she can see the post too
    conn = conn(user: alice, account: account)
    {:ok, view, _html} = live(conn, "/post/#{post.id}")
    assert has_element?(view, "article", html_body)

    # login as bob and verify that he can see the post too
    conn = conn(user: bob, account: account)
    {:ok, view, _html} = live(conn, "/post/#{post.id}")
    assert has_element?(view, "article", html_body)

    # login as carl and verify that he cannot see the post
    conn = conn(user: carl, account: account)
    {:ok, view, _html} = live(conn, "/post/#{post.id}")
    refute has_element?(view, "article", html_body)
  end

  test "adding a user with a 'participate' role and verify that the user can engage in the post's activities and discussions." do
    # create a bunch of users
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)

    # create a post with local boundary and add Alice as participate
    html_body = "epic html message"
    attrs = %{post_content: %{html_body: html_body}}

    {:ok, post} =
      Posts.publish(
        current_user: me,
        post_attrs: attrs,
        boundary: "custom",
        to_circles: %{alice.id => "participate"}
      )

    # login as myself and verify that I can see the post
    conn = conn(user: me, account: account)
    {:ok, view, _html} = live(conn, "/post/#{post.id}")
    assert has_element?(view, "article")
    # element(view, "article") |> render() |> debug

    # ...and can like and boost and reply
    assert has_element?(view, "article button[data-role=like_enabled]")
    assert has_element?(view, "article button[data-role=boost_enabled]")
    assert has_element?(view, "article button[data-role=reply_enabled]")

    # login as alice and verify that she can see the post
    conn = conn(user: alice, account: account)
    {:ok, view, _html} = live(conn, "/post/#{post.id}")
    assert has_element?(view, "article")

    # ...and can like and boost and reply
    assert has_element?(view, "article button[data-role=like_enabled]")
    assert has_element?(view, "article button[data-role=boost_enabled]")
    assert has_element?(view, "article button[data-role=reply_enabled]")

    # login as bob and verify that he cannot see, like, boost and reply
    conn = conn(user: bob, account: account)
    {:ok, view, _html} = live(conn, "/post/#{post.id}")
    refute has_element?(view, "article button[data-role=like_enabled]")
    refute has_element?(view, "article button[data-role=boost_enabled]")
    refute has_element?(view, "article button[data-role=reply_enabled]")
  end
end
