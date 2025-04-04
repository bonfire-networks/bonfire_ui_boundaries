defmodule Bonfire.UI.Boundaries.BlockTest do
  use Bonfire.UI.Boundaries.ConnCase, async: true
  @moduletag :ui

  alias Bonfire.Social.Fake
  alias Bonfire.Posts
  alias Bonfire.Files.Test

  setup do
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)
    carl = fake_user!(account)
    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, me: me, alice: alice, bob: bob, carl: carl}
  end

  test "Ghost a user works (PhoenixTest)", %{conn: conn, alice: alice} do
    conn
    |> visit("/@#{alice.character.username}")
    |> click_button("Ghost #{alice.profile.name}")
    |> click_button("[data-role=ghost]", "Ghost")
    |> assert_has("[role=alert]", text: "ghosted")
  end

  test "Silence a user works (PhoenixTest)", %{conn: conn, alice: alice} do
    conn
    |> visit("/@#{alice.character.username}")
    |> click_button("Silence #{alice.profile.name}")
    |> click_button("[data-role=silence]", "Silence")
    |> assert_has("[role=alert]", text: "silenced")
  end

  test "I can see a list of ghosted users", %{
    conn: conn,
    me: me,
    alice: alice,
    bob: bob,
    carl: carl
  } do
    assert {:ok, _ghost} = Bonfire.Boundaries.Blocks.block(alice, :ghost, current_user: me)
    assert {:ok, _ghost} = Bonfire.Boundaries.Blocks.block(bob, :ghost, current_user: me)
    assert {:ok, _silenced} = Bonfire.Boundaries.Blocks.block(carl, :silence, current_user: me)

    conn
    |> visit("/boundaries/ghosted")
    |> assert_has("#circle_members", text: alice.profile.name)
    |> assert_has("#circle_members", text: bob.profile.name)
    |> refute_has("#circle_members", text: carl.profile.name)
  end

  test "I can see a list of silenced users", %{
    conn: conn,
    me: me,
    alice: alice,
    bob: bob,
    carl: carl
  } do
    assert {:ok, _silenced} = Bonfire.Boundaries.Blocks.block(alice, :silence, current_user: me)
    assert {:ok, _silenced} = Bonfire.Boundaries.Blocks.block(bob, :silence, current_user: me)
    assert {:ok, _ghosted} = Bonfire.Boundaries.Blocks.block(carl, :ghost, current_user: me)

    conn
    |> visit("/boundaries/silenced")
    |> assert_has("#circle_members", text: alice.profile.name)
    |> assert_has("#circle_members", text: bob.profile.name)
    |> refute_has("#circle_members", text: carl.profile.name)
  end

  test "I can unghost a previously ghosted user", %{conn: conn, me: me, alice: alice} do
    assert {:ok, _ghost} = Bonfire.Boundaries.Blocks.block(alice, :ghost, current_user: me)

    conn
    |> visit("/boundaries/ghosted")
    |> assert_has("#circle_members", text: alice.profile.name)
    |> click_button("[data-role=remove_user]", "Remove")
    |> assert_has("[role=alert]", text: "Unblocked!")
    |> refute_has("#circle_members", text: alice.profile.name)
  end

  test "I can unsilence a previously silenced user", %{conn: conn, me: me, alice: alice} do
    assert {:ok, _ghost} = Bonfire.Boundaries.Blocks.block(alice, :silence, current_user: me)

    conn
    |> visit("/boundaries/silenced")
    |> assert_has("#circle_members", text: alice.profile.name)
    |> click_button("[data-role=remove_user]", "Remove")
    |> assert_has("[role=alert]", text: "Unblocked!")
    |> refute_has("#circle_members", text: alice.profile.name)
  end

  test "I can see if I silenced a user from their profile page", %{
    conn: conn,
    me: me,
    alice: alice
  } do
    assert {:ok, _ghost} = Bonfire.Boundaries.Blocks.block(alice, :silence, current_user: me)

    conn
    |> visit("/@#{alice.character.username}")
    |> assert_has("[data-id=hero_data]", text: "silenced")
  end

  test "I can see if I ghosted a user from their profile page", %{
    conn: conn,
    me: me,
    alice: alice
  } do
    assert {:ok, _ghost} = Bonfire.Boundaries.Blocks.block(alice, :ghost, current_user: me)

    conn
    |> visit("/@#{alice.character.username}")
    |> assert_has("[data-id=hero_data]", text: "ghosted")
  end

  describe "if I silenced a user i will not receive any update from it" do
    test "i'll not see anything they publish in feeds", %{conn: conn, alice: alice, me: me} do
      assert {:ok, _silenced} = Bonfire.Boundaries.Blocks.block(alice, :silence, current_user: me)
      html_body = "epic html message"
      attrs = %{post_content: %{html_body: html_body}}

      {:ok, post} =
        Posts.publish(
          current_user: alice,
          post_attrs: attrs,
          boundary: "local"
        )

      conn
      |> visit("/feed/local")
      |> refute_has("article", text: html_body)
    end

    test "i'll still be able to view their profile", %{conn: conn, alice: alice, me: me} do
      assert {:ok, _silenced} = Bonfire.Boundaries.Blocks.block(alice, :silence, current_user: me)
      html_body = "epic html message"
      attrs = %{post_content: %{html_body: html_body}}

      {:ok, post} =
        Posts.publish(
          current_user: alice,
          post_attrs: attrs,
          boundary: "local"
        )

      conn
      |> visit("/@#{alice.character.username}")
      |> assert_has("[data-id=hero_data]", text: alice.profile.name)
    end

    test "I can read post via direct link", %{conn: conn, alice: alice, me: me} do
      assert {:ok, _silenced} = Bonfire.Boundaries.Blocks.block(alice, :silence, current_user: me)
      html_body = "epic html message"
      attrs = %{post_content: %{html_body: html_body}}

      {:ok, post} =
        Posts.publish(
          current_user: alice,
          post_attrs: attrs,
          boundary: "local"
        )

      conn
      |> visit("/post/#{post.id}")
      |> assert_has("#thread_main_object", text: html_body)
    end

    test "i'll not see any @ mentions from them", %{conn: conn, me: me, alice: alice} do
      assert {:ok, _silenced} = Bonfire.Boundaries.Blocks.block(alice, :silence, current_user: me)
      html_body = "@#{me.character.username} epic html message"
      attrs = %{post_content: %{html_body: html_body}}

      {:ok, post} =
        Posts.publish(
          current_user: alice,
          post_attrs: attrs,
          boundary: "public"
        )

      conn
      |> visit("/notifications")
      |> refute_has("article", text: html_body)

      conn
      |> visit("/feed/local")
      |> refute_has("article", text: html_body)
    end

    test "i'll not see any DMs from them", %{conn: conn, me: me, alice: alice} do
      assert {:ok, _silenced} = Bonfire.Boundaries.Blocks.block(alice, :silence, current_user: me)
      html_body = "epic html message"
      attrs = %{post_content: %{html_body: html_body}}

      {:ok, post} =
        Posts.publish(
          current_user: alice,
          post_attrs: attrs,
          boundary: "message",
          to_circles: [me.character.id]
        )

      conn
      |> visit("/messages")
      |> refute_has("article", text: html_body)
    end
  end

  describe "if I ghosted a user they will not be able to interact with me or with my content" do
    test "Nothing I post privately will be shown to them from now on", %{
      account: account,
      alice: alice,
      me: me
    } do
      assert {:ok, _ghosted} = Bonfire.Boundaries.Blocks.block(alice, :ghost, current_user: me)
      html_body = "epic html message"
      attrs = %{post_content: %{html_body: html_body}}

      {:ok, post} =
        Posts.publish(
          current_user: me,
          post_attrs: attrs,
          boundary: "local"
        )

      # login as alice
      conn = conn(user: alice, account: account)

      conn
      |> visit("/feed/local")
      |> refute_has("article", text: html_body)
    end

    test "They cannot see things I post publicly when logged.", %{
      account: account,
      alice: alice,
      me: me
    } do
      assert {:ok, _ghosted} = Bonfire.Boundaries.Blocks.block(alice, :ghost, current_user: me)
      html_body = "epic html message"
      attrs = %{post_content: %{html_body: html_body}}

      {:ok, post} =
        Posts.publish(
          current_user: me,
          post_attrs: attrs,
          boundary: "public"
        )

      # login as alice
      conn = conn(user: alice, account: account)

      conn
      |> visit("/feed/explore")
      |> refute_has("article", text: html_body)
    end

    test "I won't be able to @ mention them.", %{account: account, alice: alice, me: me} do
      assert {:ok, _ghosted} = Bonfire.Boundaries.Blocks.block(alice, :ghost, current_user: me)
      html_body = "@#{alice.character.username} epic html message"
      attrs = %{post_content: %{html_body: html_body}}

      {:ok, post} =
        Posts.publish(
          current_user: me,
          post_attrs: attrs,
          boundary: "public"
        )

      # login as alice
      conn = conn(user: alice, account: account)

      conn
      |> visit("/notifications")
      |> refute_has("article", text: html_body)

      conn
      |> visit("/feed/local")
      |> refute_has("article", text: html_body)
    end

    test "I won't be able to DM them.", %{account: account, alice: alice, me: me} do
      assert {:ok, _ghosted} = Bonfire.Boundaries.Blocks.block(alice, :ghost, current_user: me)
      html_body = "epic html message"
      attrs = %{post_content: %{html_body: html_body}}

      {:ok, post} =
        Posts.publish(
          current_user: me,
          post_attrs: attrs,
          boundary: "message",
          to_circles: [alice.character.id]
        )

      # login as alice
      conn = conn(user: alice, account: account)

      conn
      |> visit("/messages")
      |> refute_has("article", text: html_body)
    end
  end

  describe "Admin" do
    test "As an admin I can ghost a user instance-wide", %{
      me: me,
      alice: alice,
      bob: bob,
      account: account
    } do
      Bonfire.Me.Users.make_admin(me)
      assert {:ok, _ghosted} = Bonfire.Boundaries.Blocks.block(alice.id, :ghost, :instance_wide)
      html_body = "epic html message"
      attrs = %{post_content: %{html_body: html_body}}

      {:ok, post} =
        Posts.publish(
          current_user: bob,
          post_attrs: attrs,
          boundary: "local"
        )

      # login as alice
      conn = conn(user: alice, account: account)

      conn
      |> visit("/feed/local")
      |> refute_has("article", text: html_body)

      {:ok, view, _html} = live(conn, "/feed/local")
    end

    test "As an admin I can silence a user instance-wide", %{
      me: me,
      alice: alice,
      bob: bob,
      account: account
    } do
      Bonfire.Me.Users.make_admin(me)
      assert {:ok, _ghosted} = Bonfire.Boundaries.Blocks.block(alice.id, :ghost, :instance_wide)
      # write a post
      html_body = "epic html message"
      attrs = %{post_content: %{html_body: html_body}}

      {:ok, post} =
        Posts.publish(
          current_user: bob,
          post_attrs: attrs,
          boundary: "local"
        )

      # login as bob
      conn = conn(user: alice, account: account)

      conn
      |> visit("/feed/local")
      |> refute_has("article", text: html_body)
    end

    test "As an admin I can see a list of instance-wide ghosted users", %{
      conn: conn,
      me: me,
      alice: alice,
      bob: bob,
      carl: carl
    } do
      Bonfire.Me.Users.make_admin(me)
      assert {:ok, _ghost} = Bonfire.Boundaries.Blocks.block(alice, :ghost, :instance_wide)
      assert {:ok, _ghost} = Bonfire.Boundaries.Blocks.block(bob, :ghost, :instance_wide)
      assert {:ok, _silenced} = Bonfire.Boundaries.Blocks.block(carl, :silence, :instance_wide)

      conn
      |> visit("/boundaries/instance_ghosted")
      |> assert_has("#circle_members", text: alice.profile.name)
      |> assert_has("#circle_members", text: bob.profile.name)
      |> refute_has("#circle_members", text: carl.profile.name)
    end

    test "As an admin I can see a list of instance-wide silenced users", %{
      conn: conn,
      me: me,
      alice: alice,
      bob: bob,
      carl: carl
    } do
      Bonfire.Me.Users.make_admin(me)
      assert {:ok, _ghost} = Bonfire.Boundaries.Blocks.block(alice, :ghost, :instance_wide)
      assert {:ok, _ghost} = Bonfire.Boundaries.Blocks.block(bob, :ghost, :instance_wide)
      assert {:ok, _silenced} = Bonfire.Boundaries.Blocks.block(carl, :silence, :instance_wide)

      conn
      |> visit("/boundaries/instance_silenced")
      |> refute_has("#circle_members", text: alice.profile.name)
      |> refute_has("#circle_members", text: bob.profile.name)
      |> assert_has("#circle_members", text: carl.profile.name)
    end

    test "As an admin I can unghost a previously ghosted user instance-wide", %{
      conn: conn,
      me: me,
      alice: alice,
      bob: bob,
      carl: carl
    } do
      {:ok, me} = Bonfire.Me.Users.make_admin(me)
      assert {:ok, _ghost} = Bonfire.Boundaries.Blocks.block(alice, :ghost, :instance_wide)

      conn
      |> visit("/boundaries/instance_ghosted")
      |> assert_has("#circle_members", text: alice.profile.name)
      |> click_button("[data-role=remove_user]", "Remove")
      |> assert_has("[role=alert]", text: "Unblocked!")
      |> refute_has("#circle_members", text: alice.profile.name)
    end

    test "As an admin I can unsilence a previously silenced user instance-wide", %{
      conn: conn,
      me: me,
      alice: alice,
      bob: bob,
      carl: carl
    } do
      assert {:ok, _ghost} = Bonfire.Boundaries.Blocks.block(alice, :silence, :instance_wide)
      {:ok, me} = Bonfire.Me.Users.make_admin(me)

      conn
      |> visit("/boundaries/instance_silenced")
      |> assert_has("#circle_members", text: alice.profile.name)
      |> click_button("[data-role=remove_user]", "Remove")
      |> assert_has("[role=alert]", text: "Unblocked!")
      |> refute_has("#circle_members", text: alice.profile.name)
    end
  end
end
