defmodule Bonfire.UI.Boundaries.ObjectAclEventsTest do
  @moduledoc "The `add_object_acl` and `remove_object_acl` events change who can see an object, so only someone who may configure that object can send them. They are delegated events, so a guest can reach them over `/LiveHandler` and any signed-in user over their own socket, with whatever params they like."
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  import Bonfire.Boundaries, only: [can?: 3]
  alias Bonfire.Posts
  alias Bonfire.Boundaries.{Acls, Grants}

  setup do
    owner = fake_user!(fake_account!())
    attacker_account = fake_account!()
    attacker = fake_user!(attacker_account)
    reader = fake_user!(fake_account!())

    {:ok, post} =
      Posts.publish(
        current_user: owner,
        post_attrs: %{post_content: %{html_body: "private archive card"}},
        boundary: "mentions"
      )

    {:ok,
     owner: owner,
     attacker: attacker,
     attacker_account: attacker_account,
     reader: reader,
     post: post}
  end

  defp as_attacker(attacker, account) do
    {:ok, view, _html} = live(conn(user: attacker, account: account), "/settings/boundaries")
    view
  end

  test "a guest cannot make a private object public", %{post: post} do
    refute can?(nil, :read, post), "control: the post is private to begin with"

    get(
      build_conn(),
      "/LiveHandler/Bonfire.Boundaries/add_object_acl?id=#{Acls.get_id!(:guests_may_see_read)}&object_id=#{post.id}"
    )

    refute can?(nil, :read, post)
  end

  test "a signed-in user who does not own the object cannot take away a reader's access",
       %{post: post, owner: owner, reader: reader, attacker: attacker, attacker_account: account} do
    {:ok, custom_acl} = Acls.get_or_create_object_custom_acl(post, owner)
    assert {:ok, _} = Grants.grant(reader.id, custom_acl, :read, true, current_user: owner)
    assert can?(reader, :read, post), "control: the reader can read the post to begin with"
    refute can?(attacker, :read, post), "control: the attacker cannot"

    {:ok, acl} = Acls.get_object_custom_acl(post)

    attacker
    |> as_attacker(account)
    |> render_hook("Bonfire.Boundaries:remove_object_acl", %{
      "object_id" => post.id,
      "acl_id" => acl.id
    })

    assert can?(reader, :read, post)
  end

  # a hide or lock someone else applied restricts everyone else, and is stored as a built-in ACL on the creator's object: detaching it is for `Blocks.unblock`, which applies the standing each one needs
  describe "block ACLs" do
    alias Bonfire.Boundaries.Blocks

    setup do
      creator_account = fake_account!()
      creator = fake_user!(creator_account)
      admin = fake_admin!(fake_account!())
      reader = fake_user!(fake_account!())

      {:ok, post} =
        Posts.publish(
          current_user: creator,
          post_attrs: %{post_content: %{html_body: "a public post to moderate"}},
          boundary: "public"
        )

      {:ok,
       creator: creator,
       creator_account: creator_account,
       admin: admin,
       reader: reader,
       post: post}
    end

    # a refused event may come back as an error flash or end the view: either way the state is what counts
    defp remove_acl_event(user, account, post, acl_id) do
      {:ok, view, _html} = live(conn(user: user, account: account), "/settings/boundaries")

      try do
        render_hook(view, "Bonfire.Boundaries:remove_object_acl", %{
          "object_id" => post.id,
          "acl_id" => acl_id
        })
      catch
        :exit, _ -> :ended
      end
    end

    defp in_feed?(post, viewer),
      do: Bonfire.Social.FeedLoader.feed_contains?(:local, post, current_user: viewer)

    test "the creator can't detach a moderator's instance-wide hide, and a moderator lifting it works",
         %{creator: creator, creator_account: account, admin: admin, reader: reader, post: post} do
      assert in_feed?(post, reader), "control: the post is in the feed to begin with"

      assert {:ok, _} = Blocks.block(post, :hide, current_user: admin, scope: :instance_wide)
      refute in_feed?(post, reader), "control: the moderator's hide applies"

      remove_acl_event(creator, account, post, Acls.get_id!(:hidden))

      refute in_feed?(post, reader), "the creator detached the moderator's hide"
      assert Blocks.is_blocked?(post, :hide, :instance_wide)

      assert {:ok, _} =
               Blocks.unblock(post, :hide, scope: :instance_wide, current_user: admin)

      assert in_feed?(post, reader), "control: the moderator's unhide applies"
    end

    test "the creator can't detach a moderator's lock", %{
      creator: creator,
      creator_account: account,
      admin: admin,
      post: post
    } do
      assert {:ok, _} = Blocks.lock(post, current_user: admin)
      assert Blocks.is_blocked?(post, :lock, :instance_wide), "control: the lock applies"

      remove_acl_event(creator, account, post, Acls.get_id!(:locked))

      assert Blocks.is_blocked?(post, :lock, :instance_wide), "the creator detached the lock"
    end

    test "the creator can't detach what someone hid for themselves", %{
      creator: creator,
      creator_account: account,
      reader: reader,
      post: post
    } do
      assert {:ok, _} = Blocks.block(post, :hide, current_user: reader)
      refute in_feed?(post, reader), "control: the reader's own hide applies"

      hidden_by_me =
        Bonfire.Boundaries.find_caretaker_stereotype(
          reader,
          [Acls.get_id!(:hidden_by_me)],
          Bonfire.Data.AccessControl.Acl
        )

      remove_acl_event(creator, account, post, hidden_by_me.id)

      refute in_feed?(post, reader), "the creator detached the reader's own hide"
    end
  end
end
