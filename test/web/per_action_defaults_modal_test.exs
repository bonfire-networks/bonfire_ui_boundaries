defmodule Bonfire.UI.Boundaries.PerActionDefaultsModalTest do
  @moduledoc """
  End-to-end UI tests for the per-action defaults panel inside the
  "Define the activity boundary" modal. Verifies that the reply/quote/read
  toggles react to the post's general preset as intended.

  Note: the "Advanced" flow on an existing post renders the toggles in a
  read-only viewer, so every toggle has `disabled`. The check we care about
  here is `checked` vs not-checked — that's the preset-reactivity behaviour.
  """
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Posts

  setup do
    account = fake_account!()
    me = fake_user!(account)

    Process.put(:feed_live_update_many_preload_mode, :inline)

    {:ok, account: account, me: me}
  end

  describe "per-action toggle state follows the post's general preset" do
    test "public post → read/reply render checked; quote unchecked (no preset grants :quote)",
         %{account: account, me: me} do
      post = publish_post(me, "public")

      session =
        conn(user: me, account: account)
        |> visit("/post/#{post.id}")
        |> click_button("Advanced")

      session
      |> assert_has("[data-role=action_toggle_read][checked]")
      |> assert_has("[data-role=action_toggle_reply][checked]")
      # quote isn't granted by any preset ACL — toggle must reflect that
      |> refute_has("[data-role=action_toggle_quote][checked]")
    end

    test "mentions post → read/reply/quote toggles all render unchecked and disabled (locked)",
         %{account: account, me: me} do
      post = publish_post(me, "mentions")

      session =
        conn(user: me, account: account)
        |> visit("/post/#{post.id}")
        |> click_button("Advanced")

      # Under mentions, preset_locks_action? → true (disabled) and preset grants
      # none of these verbs to the anyone/public audience (unchecked).
      for action <- ~w(read reply quote) do
        session
        |> assert_has("[data-role=action_toggle_#{action}][disabled]")
        |> refute_has("[data-role=action_toggle_#{action}][checked]")
      end
    end

    test "local post → reply toggle renders checked",
         %{account: account, me: me} do
      post = publish_post(me, "local")

      conn(user: me, account: account)
      |> visit("/post/#{post.id}")
      |> click_button("Advanced")
      |> assert_has("[data-role=action_toggle_reply][checked]")
    end

    test "all three per-action toggles are rendered in the modal",
         %{account: account, me: me} do
      post = publish_post(me, "public")

      conn(user: me, account: account)
      |> visit("/post/#{post.id}")
      |> click_button("Advanced")
      |> assert_has("[data-role=action_toggle_read]")
      |> assert_has("[data-role=action_toggle_reply]")
      |> assert_has("[data-role=action_toggle_quote]")
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
