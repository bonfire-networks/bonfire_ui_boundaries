defmodule Bonfire.UI.Boundaries.InFeedsTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Posts
  alias Bonfire.Boundaries.{Circles, Acls, Grants}

  setup do
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)
    Process.put(:feed_live_update_many_preload_mode, :inline)

    {:ok, account: account, me: me, alice: alice, bob: bob}
  end

  test "read role allows seeing a post but not interacting with it", %{
    me: me,
    alice: alice,
    bob: bob,
    account: account
  } do
    html_body = "epic html message"
    attrs = %{post_content: %{html_body: html_body}}

    {:ok, post} =
      Posts.publish(
        current_user: me,
        post_attrs: attrs,
        boundary: "custom",
        to_circles: %{alice.id => "read", bob.id => "interact"}
      )

    # alice has read role — can see but not like
    conn(user: alice, account: account)
    |> visit("/feed/explore")
    |> within("[data-object_id='#{post.id}']", fn session ->
      session
      |> refute_has("button[data-role=like_enabled]")
    end)

    # bob has interact role — can like
    conn(user: bob, account: account)
    |> visit("/post/#{post.id}")
    |> assert_has_or_open_browser("article button[data-role=like_enabled]")
  end

  test "public boundary grants all reaction and reply permissions", %{
    me: me,
    bob: bob,
    account: account
  } do
    html_body = "public post for testing"
    attrs = %{post_content: %{html_body: html_body}}

    {:ok, _post} =
      Posts.publish(current_user: me, post_attrs: attrs, boundary: "public")

    conn(user: bob, account: account)
    |> visit("/feed/local")
    |> assert_has("[data-id=object_body]", text: html_body)
    |> assert_has("article button[data-role=like_enabled]")
    |> assert_has("article button[data-role=boost_enabled]")
    |> assert_has("article button[data-role=reply_enabled]")
  end

  test "interact role allows like and boost but not reply", %{
    me: me,
    alice: alice,
    bob: bob,
    account: account
  } do
    html_body = "interact vs participate test"
    attrs = %{post_content: %{html_body: html_body}}

    {:ok, post} =
      Posts.publish(
        current_user: me,
        post_attrs: attrs,
        boundary: "custom",
        to_circles: %{alice.id => "interact", bob.id => "participate"}
      )

    # alice has interact — can like and boost, cannot reply
    conn(user: alice, account: account)
    |> visit("/feed/explore")
    |> within("[data-object_id='#{post.id}']", fn session ->
      session
      |> assert_has("[data-id=object_body]", text: html_body)
      |> assert_has("button[data-role=like_enabled]")
      |> assert_has("button[data-role=boost_enabled]")
      |> refute_has("button[data-role=reply_enabled]")
    end)

    # bob has participate — can like, boost, and reply
    conn(user: bob, account: account)
    |> visit("/feed/explore")
    |> within("[data-object_id='#{post.id}']", fn session ->
      session
      |> assert_has("[data-id=object_body]", text: html_body)
      |> assert_has("button[data-role=like_enabled]")
      |> assert_has("button[data-role=boost_enabled]")
      |> assert_has("button[data-role=reply_enabled]")
    end)
  end

  test "custom ACL preset with circle grants enforces permissions on a post", %{
    me: me,
    alice: alice,
    bob: bob,
    account: account
  } do
    # create a circle and add alice to it
    {:ok, circle} = Circles.create(me, %{named: %{name: "friends"}})
    {:ok, _} = Circles.add_to_circles(alice, circle)

    # create a custom ACL preset and grant the circle the interact role
    {:ok, acl} = Acls.simple_create(me, "friends_boundary")
    Grants.grant_role(circle.id, acl.id, "interact", current_user: me)

    # publish a post using the custom ACL
    html_body = "custom acl circle test"
    attrs = %{post_content: %{html_body: html_body}}
    {:ok, post} = Posts.publish(current_user: me, post_attrs: attrs, boundary: acl.id)

    # alice (in circle) can see and interact but not reply
    conn(user: alice, account: account)
    |> visit("/post/#{post.id}")
    |> assert_has("[data-id=object_body]", text: html_body)
    |> assert_has("article button[data-role=like_enabled]")
    |> assert_has("article button[data-role=boost_enabled]")
    |> refute_has("article button[data-role=reply_enabled]")

    # bob (not in circle) cannot see the post
    conn(user: bob, account: account)
    |> visit("/post/#{post.id}")
    |> refute_has("[data-id=object_body]", text: html_body)
  end
end
