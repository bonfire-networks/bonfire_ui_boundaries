defmodule Bonfire.UI.Boundaries.FeedsCirclesFilterTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  use Bonfire.Common.Utils

  alias Bonfire.Social.Objects
  alias Bonfire.Boundaries.Circles

  alias Bonfire.Me.Users
  alias Bonfire.Me.Fake
  import Bonfire.Social.Fake
  import Bonfire.Posts.Fake, except: [fake_remote_user!: 0]

  describe "circle inclusion and exclusion filters" do
    setup do
      # Create users
      me = fake_user!("main me")
      alice = fake_user!("alice")
      bob = fake_user!("bob")
      carl = fake_user!("carl")

      # Create a circle and add alice to it
      {:ok, circle} = Circles.create(me, %{named: %{name: "friends"}})
      {:ok, _} = Circles.add_to_circles(alice, circle)

      # share the circle
      Objects.publish(me, :boost, circle, to_boundaries: "local")

      # Create posts by different users
      post_by_alice = fake_post!(alice, "public", %{post_content: %{name: "post by alice"}})
      post_by_bob = fake_post!(bob, "public", %{post_content: %{name: "post by bob"}})
      post_by_carl = fake_post!(carl, "public", %{post_content: %{name: "post by carl"}})

      %{
        me: me,
        circle: circle,
        alice: alice,
        bob: bob,
        carl: carl,
        post_by_alice: post_by_alice,
        post_by_bob: post_by_bob,
        post_by_carl: post_by_carl
      }
    end

    test "viewing a circle feed only includes posts from members of that circle", %{
      me: me,
      circle: circle,
      post_by_alice: post_by_alice,
      post_by_carl: post_by_carl
    } do
      conn = conn(user: me)

      # Visit the specific circle's feed page
      conn
      |> visit("/circle/#{circle.id}")
      # Assert posts by Alice (member of the circle) are included
      |> assert_has("article", text: "post by alice")
      # Assert posts by Carl (not in the circle) are excluded
      |> refute_has("article", text: "post by carl")
    end
  end

  describe "guest pagination on a circle feed (without JavaScript)" do
    setup do
      # Disable deferred joins because they make pagination counts unpredictable
      original_config = Config.get([Bonfire.Social.Feeds, :query_with_deferred_join])
      Config.put([Bonfire.Social.Feeds, :query_with_deferred_join], false)

      on_exit(fn ->
        Config.put([Bonfire.Social.Feeds, :query_with_deferred_join], original_config)
      end)

      limit = Bonfire.Common.Config.get(:default_pagination_limit, 2)

      me = fake_user!("circle owner")
      alice = fake_user!("alice")

      # Create a publicly-visible circle with alice as a member
      {:ok, circle} = Circles.create(me, %{named: %{name: "paginated friends"}})
      {:ok, _} = Circles.add_to_circles(alice, circle)
      Objects.publish(me, :boost, circle, to_boundaries: "public")

      # Two full pages worth of public posts authored by a circle member,
      # numbered so we can tell pages apart (newest = highest number).
      total = limit * 2

      for n <- 1..total do
        fake_post!(alice, "public", %{post_content: %{name: "circle paginated post #{n}"}})
      end

      %{circle: circle, limit: limit, total: total}
    end

    test "clicking 'Next page' as a guest shows the next activities, not the same ones", %{
      circle: circle,
      limit: limit,
      total: total
    } do
      # Guest (no logged-in user)
      conn()
      |> visit("/circle/#{circle.id}")
      # The first page shows the newest posts
      |> assert_has("[data-id=feed] article", count: limit)
      |> assert_has("article", text: "circle paginated post #{total}")
      # Follow the no-JS pagination link
      |> click_link("a[data-id=next_page]", "Next page")
      # The second page must NOT repeat the newest post (this is the bug)
      |> refute_has("article", text: "circle paginated post #{total}")
      # ...and should show an older post instead
      |> assert_has("article", text: "circle paginated post 1")
    end
  end
end
