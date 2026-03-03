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
end
