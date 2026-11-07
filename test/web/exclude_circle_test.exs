defmodule Bonfire.UI.Boundaries.ExcludeCircleTest do
  @moduledoc """
  Someone excluded from a post's audience in the composer may not read the post.

  The composer keeps exclusions in `exclude_circles`, beside the audience in `to_circles`, whether picked directly or brought in by customising a boundary from a preset (`custom_from_preset_template`, which puts the preset's `cannot_*` grants there). The post is published from the composer form's fields (`PostsLiveHandler.publish_post/2`), so the form has to send the exclusions too, or they are lost.
  """
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  use Surface.LiveViewTest
  @moduletag :ui

  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.{Acls, Grants, Circles}
  alias Bonfire.Posts.LiveHandler, as: PostsLiveHandler

  setup do
    {:ok, author: fake_user!(), excluded: fake_user!(), other: fake_user!()}
  end

  test "a public post with someone excluded in the composer can't be read by them", %{
    author: author,
    excluded: excluded,
    other: other
  } do
    {:noreply, socket} =
      Bonfire.Boundaries.LiveHandler.handle_event(
        "select",
        %{"exclude_circles" => %{excluded.id => "cannot_read"}},
        socket(author, to_boundaries: [{"public", "Public"}], exclude_circles: [])
      )

    post = publish_from_form!(author, socket.assigns)

    # the positive first: the post is public
    assert Boundaries.can?(other, :read, post), "someone not excluded can't read a public post"

    refute Boundaries.can?(excluded, :read, post), "the excluded person can read the post"
  end

  describe "customising a boundary from a preset that excludes someone" do
    setup %{author: author, excluded: excluded} do
      # a preset where local users may read, except the excluded person
      {:ok, acl} = Acls.simple_create(author, "everyone here but one")
      Grants.grant_role(Circles.get_id!(:local), acl.id, "read", current_user: author)
      Grants.grant_role(excluded.id, acl.id, "cannot_read", current_user: author)

      {:noreply, socket} =
        Bonfire.Boundaries.LiveHandler.handle_event(
          "custom_from_preset_template",
          %{"boundary" => acl.id, "name" => "everyone here but one"},
          socket(author)
        )

      {:ok, composer: socket.assigns}
    end

    test "keeps the exclusion in the composer", %{composer: composer, excluded: excluded} do
      assert excluded.id in Enum.map(composer.exclude_circles, fn {circle, _role} ->
               Bonfire.Common.Enums.id(circle)
             end),
             "the preset's exclusion didn't reach the composer"
    end

    test "publishes a post the excluded person can't read", %{
      author: author,
      excluded: excluded,
      other: other,
      composer: composer
    } do
      post = publish_from_form!(author, composer)

      # the positive first: the preset's grant reached the post
      assert Boundaries.can?(other, :read, post), "someone the preset lets read can't"

      refute Boundaries.can?(excluded, :read, post), "the excluded person can read the post"
    end
  end

  defp socket(user, assigns \\ []) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(
          %{__changed__: %{}, current_user: user, __context__: %{current_user: user}},
          Map.new(assigns)
        )
    }
  end

  # the composer's own fields, rendered from its state, submitted as the browser would
  defp publish_from_form!(author, composer) do
    assigns = %{
      to_boundaries: composer[:to_boundaries],
      to_circles: composer[:to_circles] || [],
      exclude_circles: composer[:exclude_circles] || []
    }

    html =
      render_surface do
        ~F"""
        <form>
          <Bonfire.UI.Common.InputControlsLive
            uploads={false}
            to_boundaries={@to_boundaries}
            to_circles={@to_circles}
            exclude_circles={@exclude_circles}
          />
        </form>
        """
      end

    params =
      html
      |> Floki.parse_fragment!()
      |> Floki.find("input[type=hidden][name]")
      |> Enum.map_join("&", fn input ->
        [name] = Floki.attribute(input, "name")
        value = List.first(Floki.attribute(input, "value")) || ""
        URI.encode_www_form(name) <> "=" <> URI.encode_www_form(value)
      end)
      |> Plug.Conn.Query.decode()
      |> Map.put("post", %{"post_content" => %{"html_body" => "a post"}})

    {:ok, post} = PostsLiveHandler.publish_post(params, socket(author))
    post
  end
end
