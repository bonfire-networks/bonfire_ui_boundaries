defmodule Bonfire.UI.Boundaries.NegativeBoundariesTest do
  use Bonfire.UI.Boundaries.ConnCase, async: true
  @moduletag :ui

  alias Bonfire.Social.Fake
  alias Bonfire.Posts
  alias Bonfire.Social.Boosts
  alias Bonfire.Social.Graph.Follows
  import Bonfire.Common.Enums
  alias Bonfire.Boundaries.Circles

  setup do
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)
    carl = fake_user!(account)
    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, me: me, alice: alice, bob: bob, carl: carl}
  end

  test "Assign cannot_read to Alice, She cannot see the post, but Bob does", %{
    me: me,
    alice: alice,
    bob: bob,
    account: account
  } do
    # create a post with local boundary and add Alice as Reader
    html_body = "epic html message"
    attrs = %{post_content: %{html_body: html_body}}

    {:ok, post} =
      Posts.publish(
        current_user: me,
        post_attrs: attrs,
        boundary: "local",
        to_circles: %{alice.id => "cannot_read"}
      )

    # login as alice and verify that she cannot see the post
    conn =
      conn(user: alice, account: account)
      |> visit("/feed/local")
      |> refute_has("[data-id=object_body]", text: html_body)

    conn =
      conn(user: bob, account: account)
      |> visit("/feed/local")
      |> assert_has("[data-id=object_body]", text: html_body)
      |> assert_has("article button[data-role=like_enabled]")
  end

  test "Assign 'cannot interact' to Alice, She can see but not like the post, Bob can see and interact with it",
       %{me: me, alice: alice, bob: bob, account: account} do
    # create a post with local boundary and add Alice as Reader
    html_body = "epic html message"
    attrs = %{post_content: %{html_body: html_body}}

    {:ok, post} =
      Posts.publish(
        current_user: me,
        post_attrs: attrs,
        boundary: "local",
        to_circles: %{alice.id => "cannot_interact"}
      )

    # login as alice and verify that she can see the post
    conn =
      conn(user: alice, account: account)
      |> visit("/feed/local")
      |> assert_has("[data-id=object_body]", text: html_body)
      |> refute_has("article button[data-role=like_enabled]")
      |> refute_has("article button[data-role=boost_enabled]")

    # login as bob and verify that he can like the post
    conn =
      conn(user: bob, account: account)
      |> visit("/feed/local")
      |> assert_has("[data-id=object_body]", text: html_body)
      |> assert_has("article button[data-role=like_enabled]")
  end

  # Test adding a user with a 'cannot participate' role and verify that the user can see and interact with the post but not reply to it but another local user can." do
  test "Assign 'cannot_participate' to Alice, She can see, like and boost but not reply to the post, Bob can see and reply to it",
       %{me: me, alice: alice, bob: bob, account: account} do
    # create a post with local boundary and add Alice as Reader
    html_body = "epic html message"
    attrs = %{post_content: %{html_body: html_body}}

    {:ok, post} =
      Posts.publish(
        current_user: me,
        post_attrs: attrs,
        boundary: "public",
        to_circles: %{alice.id => "cannot_participate"}
      )

    # login as alice and verify that she can see the post
    conn =
      conn(user: alice, account: account)
      |> visit("/feed/local")
      |> assert_has("[data-id=object_body]", text: html_body)
      |> assert_has("article button[data-role=like_enabled]")
      |> assert_has("article button[data-role=boost_enabled]")
      |> assert_has("article button[data-role=reply_enabled]")

    conn =
      conn(user: bob, account: account)
      |> visit("/feed/local")
      |> assert_has("[data-id=object_body]", text: html_body)
      |> assert_has("article button[data-role=like_enabled]")
      |> assert_has("article button[data-role=boost_enabled]")
      |> assert_has("article button[data-role=reply_enabled]")
  end
end
