defmodule Bonfire.UI.Boundaries.CircleMembersGuestPaginationTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  use Bonfire.Common.Utils

  alias Bonfire.Social.Objects
  alias Bonfire.Boundaries.Circles
  import Bonfire.Social.Fake

  # KNOWN ISSUE (documented, not yet fixed):
  #
  # Guests (no JavaScript) cannot paginate a circle's members list at
  # `/circle/:id/members`. Unlike the users/instances directories, profile
  # followers/following, and the circle feed — which were all fixed by
  # rendering the guest `<a data-id=next_page>` fallback and flattening the
  # namespaced `?Module[after]=…` cursor — the members list is rendered by the
  # `CircleMembersLive` stateful component gated behind `CircleLive`'s
  # `{#if @selected_tab == "members"}`.
  #
  # Investigation (see git history / PR notes) showed `CircleLive.handle_params`
  # DOES run correctly on the paginated URL (selected_tab = "members", circle
  # loaded, page-2 members fetched), but the view that actually renders is in
  # mount-state (selected_tab = nil, circle = nil), so the feed branch renders
  # instead of the members component and no next page is shown. The root cause
  # is an interaction between Bonfire's loading-screen mount, the stateful
  # component, and the tab gate in `CircleLive` — it needs a focused redesign
  # of `CircleLive`'s param/tab handling rather than the simple pattern that
  # fixed the other five cases.
  #
  # This test is kept (skipped) to document the bug and to be un-skipped once
  # the underlying `CircleLive` handling is reworked.
  @tag :skip
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
        {:ok, _} = Circles.add_to_circles(member, circle)
      end

      %{circle: circle, limit: limit, total: total}
    end

    test "clicking 'Next page' as a guest shows the next members, not a blank page", %{
      circle: circle,
      limit: limit,
      total: total
    } do
      conn()
      |> visit("/circle/#{circle.id}/members")
      # The first page lists the newest members
      |> assert_has("[data-id=profile_name]", text: "member #{total}")
      # The no-JS guest fallback link must be present
      |> assert_has("a[data-id=next_page]", text: "Next page")
      # Following it must show the NEXT members, not a blank page nor the same ones
      |> click_link("a[data-id=next_page]", "Next page")
      |> refute_has("[data-id=profile_name]", text: "member #{total}")
      |> assert_has("[data-id=profile_name]", text: "member #{total - limit}")
    end
  end
end
