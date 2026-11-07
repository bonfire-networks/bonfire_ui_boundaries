defmodule Bonfire.UI.Boundaries.CheckObjectBoundaryVerbsTest do
  @moduledoc "`maybe_check_boundaries` checks each card for the verbs it asks for in `check_object_boundary` (`true` meaning the call's verbs, `[:read]` by default), in one batch, keeping the cards' order."
  use Bonfire.UI.Boundaries.ConnCase, async: true
  @moduletag :ui

  import Bonfire.Common.Enums, only: [id: 1]
  alias Bonfire.Posts
  alias Bonfire.Boundaries.Blocks

  setup do
    me = fake_user!(fake_account!())
    silenced = fake_user!(fake_account!())
    other = fake_user!(fake_account!())

    {:ok, silenced_post} =
      Posts.publish(
        current_user: silenced,
        post_attrs: %{post_content: %{html_body: "by someone I silenced"}},
        boundary: "public"
      )

    {:ok, other_post} =
      Posts.publish(
        current_user: other,
        post_attrs: %{post_content: %{html_body: "by someone else"}},
        boundary: "public"
      )

    Blocks.block(silenced, :silence, current_user: me)

    {:ok, me: me, silenced_post: silenced_post, other_post: other_post}
  end

  defp card(object, check, user) do
    assigns = %{object: object, check_object_boundary: check, __context__: %{current_user: user}}
    {assigns, %{assigns: assigns}}
  end

  defp check(cards) do
    cards
    |> Bonfire.Boundaries.LiveHandler.maybe_check_boundaries()
    |> Enum.map(fn {assigns, _socket} -> assigns end)
  end

  test "a card asking for :see is dropped when I silenced its author, while one asking for :read only is kept, in the same batch",
       %{me: me, silenced_post: silenced_post, other_post: other_post} do
    [see_silenced, read_silenced, see_other] =
      check([
        card(silenced_post, [:see, :read], me),
        card(silenced_post, true, me),
        card(other_post, [:see, :read], me)
      ])

    # the positive first: a :see check on someone I didn't silence keeps the card
    refute is_nil(see_other[:object])
    assert id(see_other[:object]) == id(other_post)

    # silence denies only :see, so the :read-only check keeps it
    refute is_nil(read_silenced[:object])

    assert is_nil(see_silenced[:object])
    assert see_silenced[:object_boundary] == :not_visible
  end
end
