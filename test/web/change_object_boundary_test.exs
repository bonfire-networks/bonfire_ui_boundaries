defmodule Bonfire.UI.Boundaries.ChangeObjectBoundaryTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Posts
  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.{Acls, Controlleds}

  setup do
    account = fake_account!()
    me = fake_user!(account)

    Process.put(:feed_live_update_many_preload_mode, :inline)

    {:ok, account: account, me: me}
  end

  describe "change boundary preset on existing post via UI" do
    test "can change a public post to local via the boundary edit modal",
         %{account: account, me: me} do
      body = "public post for boundary edit #{System.unique_integer()}"
      post = publish_post(me, "public", body: body)

      initial_preset_acls = Controlleds.list_preset_acl_ids_on_object(post.id)
      assert MapSet.size(initial_preset_acls) > 0

      conn(user: me, account: account)
      |> visit("/post/#{post.id}")
      |> assert_has("article", text: body)
      # Open the advanced/boundary details modal
      # Open the Advanced modal (contains boundary details + edit section)
      |> click_button("Advanced")
      # Click the "Local" preset button (rendered in DOM, visually gated by Alpine)
      |> click_button("[data-scope=local_boundary]", "Local")
      |> assert_has("[role=alert]", text: "Boundary updated")

      # Verify the DB state changed
      updated_preset_acls = Controlleds.list_preset_acl_ids_on_object(post.id)

      local_acl_ids =
        Boundaries.acls_from_preset_boundary_names("local")
        |> Enum.map(&Acls.get_id!/1)
        |> MapSet.new()

      assert MapSet.subset?(local_acl_ids, updated_preset_acls),
             "Post should have local preset ACLs after boundary change"
    end

    test "changing to mentions via UI hides post from non-mentioned users",
         %{account: account, me: me} do
      alice = fake_user!(account)
      body = "mentions boundary test #{System.unique_integer()}"
      post = publish_post(me, "public", body: body)

      # Alice can see the public post
      conn(user: alice, account: account)
      |> visit("/post/#{post.id}")
      |> assert_has("article", text: body)

      # Author changes boundary to mentions
      conn(user: me, account: account)
      |> visit("/post/#{post.id}")
      |> click_button("Advanced")
      |> click_button("button[phx-value-id=mentions]", "Mentions")
      |> assert_has("[role=alert]", text: "Boundary updated")

      # Verify no preset ACLs remain
      assert MapSet.size(Controlleds.list_preset_acl_ids_on_object(post.id)) == 0

      # Alice can no longer see the post
      conn(user: alice, account: account)
      |> visit("/post/#{post.id}")
      |> refute_has("article", text: body)
    end

    test "changing preset preserves custom per-object ACLs", %{me: me} do
      alice = fake_user!(fake_account!())
      post = publish_post(me, "public", to_circles: %{alice.id => "read"})

      all_acls_before = Boundaries.list_object_boundaries(post.id)
      preset_count = MapSet.size(Controlleds.list_preset_acl_ids_on_object(post.id))
      non_preset_count = length(all_acls_before) - preset_count
      assert non_preset_count > 0, "Post should have non-preset ACLs (custom grants)"

      # Swap preset at data layer (invariant hard to verify via UI alone)
      Controlleds.list_preset_acl_ids_on_object(post.id)
      |> MapSet.to_list()
      |> then(&Controlleds.remove_acls(post.id, &1))

      new_acl_ids =
        Boundaries.acls_from_preset_boundary_names("local")
        |> Enum.map(&Acls.get_id!/1)

      if new_acl_ids != [], do: Controlleds.add_acls(post.id, new_acl_ids)

      all_acls_after = Boundaries.list_object_boundaries(post.id)

      assert length(all_acls_after) == non_preset_count + length(new_acl_ids),
             "Custom ACLs should be preserved after preset change"
    end
  end

  defp publish_post(user, boundary, opts \\ []) do
    {:ok, post} =
      Posts.publish(
        [
          current_user: user,
          post_attrs: %{post_content: %{html_body: opts[:body] || "test post"}},
          boundary: boundary
        ] ++ opts
      )

    post
  end
end
