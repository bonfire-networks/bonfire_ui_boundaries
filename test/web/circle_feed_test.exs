defmodule Bonfire.UI.Boundaries.FeedsCirclesFilterTest do
  use Bonfire.UI.Boundaries.ConnCase, async: true
  use Bonfire.Common.Utils

  import Bonfire.Files.Simulation
  alias Bonfire.Files
  alias Bonfire.Files.ImageUploader

  alias Bonfire.Social.FeedActivities
  alias Bonfire.Social.Feeds
  alias Bonfire.Posts
  alias Bonfire.Messages
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
      Objects.publish(me, :boost, circle,
        to_boundaries: "local"
        #  to_circles: 
      )

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

    #   test "viewing a feed excluding a circle filters out posts from members of that circle", %{
    #     me: me,
    #     circle: circle,
    #     post_by_alice: post_by_alice,
    #     post_by_carl: post_by_carl
    #   } do
    #     conn = conn(user: me)

    #     # Visit the feed page with circle exclusion filter
    #     conn
    #     |> visit("/feed/custom?exclude_circle=#{circle.id}")
    #     # Assert posts by Alice (member of the circle) are excluded
    #     |> refute_has("article", text: "post by alice")
    #     # Assert posts by Carl (not in the circle) are included
    #     |> assert_has("article", text: "post by carl")
    #   end

    #   test "combined circle inclusion and exclusion prioritizes exclusions", %{
    #     me: me,
    #     carl: carl,
    #     circle: circle,
    #     post_by_alice: post_by_alice,
    #     post_by_bob: post_by_bob,
    #     post_by_carl: post_by_carl
    #   } do
    #     # Add Carl to the first circle
    #     {:ok, _} = Circles.add_to_circles(carl, circle)

    #     # Create another circle and add Carl to it
    #     {:ok, second_circle} = Circles.create(me, %{named: %{name: "coworkers"}})
    #     {:ok, _} = Circles.add_to_circles(carl, second_circle)

    #     conn = conn(user: me)

    #     # Visit the feed with both inclusion and exclusion parameters
    #     conn
    #     |> visit("/feed/custom?circle=#{circle.id}&exclude_circle=#{second_circle.id}")
    #     # Assert posts by Alice (member of "friends" circle) are included
    #     |> assert_has("article", text: "post by alice")
    #     # Assert Carl's post is excluded because he is in "coworkers" circle
    #     |> refute_has("article", text: "post by carl") 
    #     # Assert posts by Bob are excluded because they are not in the included circle
    #     |> refute_has("article", text: "post by bob")
    #   end
    # end
  end
end
