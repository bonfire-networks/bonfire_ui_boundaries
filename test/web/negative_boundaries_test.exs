defmodule Bonfire.UI.Boundaries.NegativeBoundariesTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Posts

  setup do
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)
    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, me: me, alice: alice, bob: bob}
  end

  test "Assign cannot_read to Alice, She cannot see the post, but Bob does", %{
    me: me,
    alice: alice,
    bob: bob,
    account: account
  } do
    Process.put(:feed_live_update_many_preload_mode, :inline)

    html_body = "epic html message"
    attrs = %{post_content: %{html_body: html_body}}

    {:ok, _post} =
      Posts.publish(
        current_user: me,
        post_attrs: attrs,
        boundary: "local",
        to_circles: %{alice.id => "cannot_read"}
      )

    # login as alice and verify that she cannot see the post
    conn(user: alice, account: account)
    |> visit("/feed/local")
    |> refute_has("[data-id=object_body]", text: html_body)

    conn(user: bob, account: account)
    |> visit("/feed/local")
    |> assert_has("[data-id=object_body]", text: html_body)
    |> assert_has("article button[data-role=like_enabled]")
  end

  test "Assign 'cannot interact' to Alice, She can see but not like the post, Bob can see and interact with it",
       %{me: me, alice: alice, bob: bob, account: account} do
    Process.put(:feed_live_update_many_preload_mode, :inline)

    html_body = "epic html message"
    attrs = %{post_content: %{html_body: html_body}}

    {:ok, post} =
      Posts.publish(
        current_user: me,
        post_attrs: attrs,
        boundary: "local",
        to_circles: %{alice.id => "cannot_interact"}
      )

    # login as alice - buttons render as enabled (optimistic UI) but clicking should fail
    conn(user: alice, account: account)
    |> visit("/post/#{post.id}")
    |> assert_has("[data-id=object_body]", text: html_body)
    |> assert_has("button[data-role=like_enabled]")
    |> click_button("[data-role=like_enabled]", "Like")
    |> assert_has("[role=alert]")

    # login as bob and verify that he can like the post
    conn(user: bob, account: account)
    |> visit("/feed/local")
    |> within("[data-object_id='#{post.id}']", fn session ->
      session
      |> assert_has("[data-id=object_body]", text: html_body)
      |> assert_has("button[data-role=like_enabled]")
    end)
  end

  # Test adding a user with a 'cannot participate' role and verify that the user can see and interact with the post but not reply to it but another local user can.
  test "Assign 'cannot_participate' to Alice, She can see, like and boost but not reply to the post, Bob can see and reply to it",
       %{me: me, alice: alice, bob: bob, account: account} do
    Process.put(:feed_live_update_many_preload_mode, :inline)

    html_body = "epic html message"
    attrs = %{post_content: %{html_body: html_body}}

    {:ok, post} =
      Posts.publish(
        current_user: me,
        post_attrs: attrs,
        boundary: "public",
        to_circles: %{alice.id => "cannot_participate"}
      )

    # login as alice - she can see, like and boost but reply should fail (optimistic UI)
    conn(user: alice, account: account)
    |> visit("/feed/local")
    |> within("[data-object_id='#{post.id}']", fn session ->
      session
      |> assert_has("[data-id=object_body]", text: html_body)
      |> assert_has("button[data-role=like_enabled]")
      |> assert_has("button[data-role=boost_enabled]")
      |> assert_has("button[data-role=reply_enabled]")
    end)

    conn(user: bob, account: account)
    |> visit("/feed/local")
    |> within("[data-object_id='#{post.id}']", fn session ->
      session
      |> assert_has("[data-id=object_body]", text: html_body)
      |> assert_has("button[data-role=like_enabled]")
      |> assert_has("button[data-role=boost_enabled]")
      |> assert_has("button[data-role=reply_enabled]")
    end)
  end
end
