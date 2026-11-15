# delegated events ("Module:event", sent from any page through `mod_delegate`) must check who sends them: each test asserts the safe outcome
defmodule Bonfire.UI.Boundaries.DelegatedEventsAuthzTest do
  use ExUnit.Case, async: false
  @moduletag :ui
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bonfire.UI.Common.Testing.Helpers

  @endpoint Application.compile_env!(:bonfire, :endpoint_module)

  alias Bonfire.Me.Fake

  setup tags do
    Bonfire.Common.Test.Interactive.setup_test_repo(tags)
    owner_account = Fake.fake_account!()
    owner = Fake.fake_user!(owner_account)

    # a post guests may NOT read (local users only)
    {:ok, post} =
      Bonfire.Posts.publish(
        current_user: owner,
        post_attrs: %{post_content: %{html_body: "not for guests"}},
        boundary: "local"
      )

    %{owner: owner, owner_account: owner_account, post: post}
  end

  # any LiveView page will do; a profile page is served to guests too (with a LiveView session)
  defp send_event(conn, page_user, name, params) do
    {:ok, view, _} = live(conn, "/@" <> page_user.character.username)

    try do
      render_hook(view, name, params)
    rescue
      _ -> :error
    catch
      _, _ -> :error
    end
  end

  defp guest_reads?(object), do: Bonfire.Boundaries.can?(nil, :read, object) == true
  defp public_acl, do: Bonfire.Boundaries.Acls.get_id!(:guests_may_see_read)

  defp stranger do
    account = Fake.fake_account!()
    {Fake.fake_user!(account), account}
  end

  # Bonfire.Boundaries:add_object_acl / remove_object_acl

  test "sanity: a guest cannot read the post to begin with", %{post: post} do
    refute guest_reads?(post)
  end

  test "add_object_acl: a GUEST cannot attach a public ACL to someone else's post", %{
    owner: owner,
    post: post
  } do
    send_event(build_conn(), owner, "Bonfire.Boundaries:add_object_acl", %{
      "id" => public_acl(),
      "object_id" => post.id
    })

    refute guest_reads?(post)
  end

  test "add_object_acl: a logged-in stranger cannot either", %{owner: owner, post: post} do
    {s, account} = stranger()

    send_event(conn(user: s, account: account), owner, "Bonfire.Boundaries:add_object_acl", %{
      "id" => public_acl(),
      "object_id" => post.id
    })

    refute guest_reads?(post)
  end

  # in this form (a post and its custom ACL) it may stay green: it was seen red on records whose custom ACL carries the shares, so the setup may need to match that
  test "remove_object_acl: a stranger (or a guest) cannot detach the post's custom ACL, so a grant on it stays",
       %{owner: owner, post: post} do
    reader = Fake.fake_user!()
    {:ok, acl} = Bonfire.Boundaries.Acls.get_or_create_object_custom_acl(post, owner)

    Bonfire.Boundaries.Grants.grant(reader.id, acl.id, [:see, :read], true,
      skip_boundary_check: true
    )

    assert Bonfire.Boundaries.can?(reader, :read, post)

    {s, account} = stranger()

    send_event(conn(user: s, account: account), owner, "Bonfire.Boundaries:remove_object_acl", %{
      "object_id" => post.id,
      "acl_id" => acl.id
    })

    send_event(build_conn(), owner, "Bonfire.Boundaries:remove_object_acl", %{
      "object_id" => post.id,
      "acl_id" => acl.id
    })

    assert Bonfire.Boundaries.can?(reader, :read, post)
  end

  test "control: the owner still can (must stay green after the fix)", %{
    owner: owner,
    owner_account: account,
    post: post
  } do
    send_event(conn(user: owner, account: account), owner, "Bonfire.Boundaries:add_object_acl", %{
      "id" => public_acl(),
      "object_id" => post.id
    })

    assert guest_reads?(post)
  end
end
