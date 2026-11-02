defmodule Bonfire.UI.Boundaries.LockEventStandingTest do
  @moduledoc """
  Locking a thread is for its author, whoever may change its boundary, and a moderator of the group it is in. The lock buttons send `Bonfire.Boundaries.Locking:lock` and `:unlock`, which check that, but the generic `Bonfire.Boundaries:block` and `:unblock` events take their `block_type` from the client, and nothing in the UI sends them with `lock`: they can only be sent by hand, as a crafted request would. These tests send them, as a stranger and as a logged-out visitor.
  """
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Boundaries.Blocks

  setup do
    author_account = fake_account!()
    author = fake_user!(author_account)
    stranger_account = fake_account!()
    stranger = fake_user!(stranger_account)

    assert {:ok, post} =
             Bonfire.Posts.publish(
               current_user: author,
               post_attrs: %{post_content: %{html_body: "<p>a thread</p>"}},
               boundary: "public"
             )

    {:ok,
     author: author,
     author_account: author_account,
     stranger: stranger,
     stranger_account: stranger_account,
     post: post}
  end

  # a refused event may come back as an error flash or end the view: either way the state is what counts
  defp send_event(conn, post, event, params \\ %{}) do
    {:ok, view, _html} = live(conn, "/post/#{post.id}")

    try do
      render_hook(view, event, Map.put(params, "id", post.id))
    catch
      :exit, _ -> :ended
    end
  end

  defp locked?(post), do: Blocks.is_blocked?(post, :lock, :instance_wide)

  test "control: the author locks and unlocks through the lock buttons' events", %{
    author: author,
    author_account: author_account,
    post: post
  } do
    conn = conn(user: author, account: author_account)

    send_event(conn, post, "Bonfire.Boundaries.Locking:lock")
    assert locked?(post)

    send_event(conn, post, "Bonfire.Boundaries.Locking:unlock")
    refute locked?(post)
  end

  test "a stranger can't lock someone else's post with a crafted block event", %{
    stranger: stranger,
    stranger_account: stranger_account,
    post: post
  } do
    send_event(
      conn(user: stranger, account: stranger_account),
      post,
      "Bonfire.Boundaries:block",
      %{
        "block_type" => "lock"
      }
    )

    refute locked?(post), "a stranger locked someone else's thread"
  end

  test "a stranger can't unlock a locked post with a crafted unblock event", %{
    author: author,
    stranger: stranger,
    stranger_account: stranger_account,
    post: post
  } do
    assert {:ok, _} = Blocks.lock(post, current_user: author)
    assert locked?(post), "control: locked by its author"

    send_event(
      conn(user: stranger, account: stranger_account),
      post,
      "Bonfire.Boundaries:unblock",
      %{"block_type" => "lock"}
    )

    assert locked?(post), "a stranger reopened a locked thread"
  end

  test "a logged-out visitor can't lock a post with a crafted block event", %{post: post} do
    send_event(conn(), post, "Bonfire.Boundaries:block", %{"block_type" => "lock"})

    refute locked?(post), "a visitor locked someone's thread"
  end

  test "a logged-out visitor can't unlock a locked post with a crafted unblock event", %{
    author: author,
    post: post
  } do
    assert {:ok, _} = Blocks.lock(post, current_user: author)

    send_event(conn(), post, "Bonfire.Boundaries:unblock", %{"block_type" => "lock"})

    assert locked?(post), "a visitor reopened a locked thread"
  end

  # the instance-wide scope in the same handler is for admins only, so someone else asking for it hides the post from themselves at most
  test "a stranger asking for an instance-wide hide doesn't hide the post for everyone", %{
    stranger: stranger,
    stranger_account: stranger_account,
    post: post
  } do
    send_event(
      conn(user: stranger, account: stranger_account),
      post,
      "Bonfire.Boundaries:block",
      %{
        "block_type" => "hide",
        "scope" => "instance_wide"
      }
    )

    refute Blocks.is_blocked?(post, :hide, :instance_wide)
  end

  describe "the hide events" do
    test "a stranger's instance-wide hide hides nothing for everyone, and an admin's does", %{
      stranger: stranger,
      stranger_account: stranger_account,
      post: post
    } do
      send_event(
        conn(user: stranger, account: stranger_account),
        post,
        "Bonfire.Boundaries.Blocks:hide_instance_wide"
      )

      refute Blocks.is_blocked?(post, :hide, :instance_wide),
             "a stranger hid someone's post for everyone"

      admin_account = fake_account!()
      admin = fake_admin!(admin_account)

      send_event(
        conn(user: admin, account: admin_account),
        post,
        "Bonfire.Boundaries.Blocks:hide_instance_wide"
      )

      assert Blocks.is_blocked?(post, :hide, :instance_wide),
             "control: the admin's hide applies to everyone"
    end

    test "a stranger's own hide hides the post for them only", %{
      author: author,
      stranger: stranger,
      stranger_account: stranger_account,
      post: post
    } do
      send_event(
        conn(user: stranger, account: stranger_account),
        post,
        "Bonfire.Boundaries.Blocks:hide"
      )

      assert Blocks.is_blocked?(post, :hide, current_user: stranger),
             "control: the hide applied for the stranger"

      refute Blocks.is_blocked?(post, :hide, current_user: author),
             "a hide by someone else reached the author"

      refute Blocks.is_blocked?(post, :hide, :instance_wide)
    end
  end
end
