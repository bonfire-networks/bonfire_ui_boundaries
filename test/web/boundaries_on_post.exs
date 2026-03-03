defmodule Bonfire.UI.Boundaries.OnPostTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Posts
  alias Bonfire.Boundaries.Circles

  setup do
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)

    Process.put(:feed_live_update_many_preload_mode, :inline)

    {:ok, account: account, me: me, alice: alice, bob: bob}
  end

  test "creating a post with a 'custom' boundary and verify that only users in the circle can read it",
       %{account: account, me: me, alice: alice, bob: bob} do
    carl = fake_user!(account)
    # create a circle with alice and bob
    {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
    {:ok, _} = Circles.add_to_circles(alice, circle)
    {:ok, _} = Circles.add_to_circles(bob, circle)

    # create a post with custom boundary and add family to to_circle
    html_body = "epic html message"

    {:ok, post} =
      Posts.publish(
        current_user: me,
        post_attrs: %{post_content: %{html_body: html_body}},
        boundary: "custom",
        to_circles: %{circle.id => "read"}
      )

    # login as myself and verify that I can see the post
    conn(user: me, account: account)
    |> visit("/post/#{post.id}")
    |> assert_has("article", text: html_body)

    # login as alice and verify that she can see the post too
    conn(user: alice, account: account)
    |> visit("/post/#{post.id}")
    |> assert_has("article", text: html_body)

    # login as bob and verify that he can see the post too
    conn(user: bob, account: account)
    |> visit("/post/#{post.id}")
    |> assert_has("article", text: html_body)

    # login as carl and verify that he cannot see the post
    conn(user: carl, account: account)
    |> visit("/post/#{post.id}")
    |> refute_has("article", text: html_body)
  end

  test "adding a user with a 'participate' role allows them to engage in the post",
       %{account: account, me: me, alice: alice, bob: bob} do
    # create a post with custom boundary and add Alice as participate
    html_body = "epic html message"

    {:ok, post} =
      Posts.publish(
        current_user: me,
        post_attrs: %{post_content: %{html_body: html_body}},
        boundary: "custom",
        to_circles: %{alice.id => "participate"}
      )

    # login as myself and verify that I can see the post
    conn(user: me, account: account)
    |> visit("/post/#{post.id}")
    |> assert_has("article")
    # ...and can like and boost and reply
    |> assert_has("article button[data-role=like_enabled]")
    |> assert_has("article button[data-role=boost_enabled]")
    |> assert_has("article button[data-role=reply_enabled]")

    # login as alice and verify that she can see the post
    conn(user: alice, account: account)
    |> visit("/post/#{post.id}")
    |> assert_has("article")
    # ...and can like and boost and reply
    |> assert_has("article button[data-role=like_enabled]")
    |> assert_has("article button[data-role=boost_enabled]")
    |> assert_has("article button[data-role=reply_enabled]")

    # login as bob and verify that he cannot like, boost and reply
    conn(user: bob, account: account)
    |> visit("/post/#{post.id}")
    |> refute_has("article button[data-role=like_enabled]")
    |> refute_has("article button[data-role=boost_enabled]")
    |> refute_has("article button[data-role=reply_enabled]")
  end
end
