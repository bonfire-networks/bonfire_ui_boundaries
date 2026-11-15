defmodule Bonfire.UI.Boundaries.CircleMembersGuestPaginationTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  use Bonfire.Common.Utils

  alias Bonfire.Social.Objects
  alias Bonfire.Boundaries.Circles
  import Bonfire.Social.Fake

  # A guest (no LiveView socket) pages through a circle's members at `/circle/:id/members` with the
  # `a[data-id=next_page]` link on the static render (`get_conn_render`), whose href holds the
  # flattened `?Bonfire.Boundaries.Circles[after]=…` cursor. `CircleMembersLive` renders
  # `LoadMoreLive` with its guest fallback link (no `hide_guest_fallback`), and reads that cursor
  # from the request params in the socket's context (not in the component's `assigns`).
  # @tag :skip
  describe "guest pagination on a circle's members list (without JavaScript)" do
    setup do
      limit = Bonfire.Common.Config.get(:default_pagination_limit, 2)

      me = fake_user!("circle members owner")

      {:ok, circle} = Circles.create(me, %{named: %{name: "members paginated"}})
      # Make the circle publicly visible to guests
      Objects.publish(me, :boost, circle, to_boundaries: "public")

      # Enough members to need more than one page (and to get past the
      # small preview short-circuit). Listing is reverse chronological.
      total = limit * 3

      for n <- 1..total do
        member = fake_user!("member #{n}")
        {:ok, _} = Circles.add_to_circles(member, circle, skip_boundary_check: true)
      end

      %{circle: circle, limit: limit, total: total}
    end

    test "clicking 'Next page' as a guest shows the next members, not a blank page", %{
      circle: circle,
      limit: limit,
      total: total
    } do
      # a guest has no LiveView socket, so the page they get is the static render, which `visit` does not give (it connects a LiveView)
      # conn()
      # |> visit("/circle/#{circle.id}/members")
      # # The first page lists the newest members
      # |> assert_has("[data-id=profile_name]", text: "member #{total}")
      # # The no-JS guest fallback link must be present
      # |> assert_has("a[data-id=next_page]", text: "Next page")
      # # Following it must show the NEXT members, not a blank page nor the same ones
      # |> click_link("a[data-id=next_page]", "Next page")
      # |> refute_has("[data-id=profile_name]", text: "member #{total}")
      # |> assert_has("[data-id=profile_name]", text: "member #{total - limit}")

      first_page =
        conn()
        |> get_conn_render("/circle/#{circle.id}/members")
        # The first page lists the newest members
        |> assert_has("[data-id=profile_name]", text: "member #{total}")
        # The no-JS guest fallback link is on the static render
        |> assert_has("a[data-id=next_page]", text: "Next page")

      # Following it must show the NEXT members, not a blank page nor the same ones
      conn()
      |> get_conn_render(static_href(first_page, "a[data-id=next_page]"))
      |> refute_has("[data-id=profile_name]", text: "member #{total}")
      |> assert_has("[data-id=profile_name]", text: "member #{total - limit}")
    end
  end
end
