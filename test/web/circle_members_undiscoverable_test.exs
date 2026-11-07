defmodule Bonfire.UI.Boundaries.CircleMembersUndiscoverableTest do
  @moduledoc """
  Someone who chose to be undiscoverable is left out of public user listings, and a shared circle's member list is one too: guests (on its page or its embed) see only the members who allow being seen, while its owner, who added them, sees everyone, as do local users, who can see everyone on their instance.
  """
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Social.Objects
  alias Bonfire.Boundaries.Circles

  setup do
    account = fake_account!()
    owner = fake_user!(account)
    discoverable = fake_user!("discoverable member")
    undiscoverable = fake_user!("hidden member", %{}, undiscoverable: true)

    {:ok, circle} = Circles.create(owner, %{named: %{name: "shared list"}})
    # shared with everyone, as a public list: what the circle manager's visibility picker does
    {:ok, _} = Objects.reset_preset_boundary(owner, circle, nil, to_boundaries: "public")

    for member <- [discoverable, undiscoverable] do
      {:ok, _} = Circles.add_to_circles(member, circle)
    end

    {:ok,
     account: account,
     owner: owner,
     circle: circle,
     discoverable: discoverable,
     undiscoverable: undiscoverable}
  end

  test "the owner sees every member of their circle", %{
    account: account,
    owner: owner,
    circle: circle
  } do
    conn(user: owner, account: account)
    |> visit("/circle/#{circle.id}/members")
    |> assert_has("[data-id=profile_name]", text: "discoverable member")
    |> assert_has("[data-id=profile_name]", text: "hidden member")
  end

  test "a guest viewing the shared circle doesn't see an undiscoverable member", %{
    circle: circle
  } do
    conn()
    |> visit("/circle/#{circle.id}/members")
    |> assert_has("[data-id=profile_name]", text: "discoverable member")
    |> refute_has("[data-id=profile_name]", text: "hidden member")
  end

  # undiscoverable keeps someone out of public listings, the fediverse and search, not out of sight of the people on their own instance (every user lets local users see them), so a local user is shown them like anyone else
  test "a local user viewing the shared circle sees an undiscoverable member", %{circle: circle} do
    conn(user: fake_user!())
    |> visit("/circle/#{circle.id}/members")
    |> assert_has("[data-id=profile_name]", text: "discoverable member")
    |> assert_has("[data-id=profile_name]", text: "hidden member")
  end

  test "the embed of a shared circle doesn't show an undiscoverable member", %{circle: circle} do
    session = conn() |> visit("/circle/#{circle.id}/embed")

    session
    |> assert_has("[data-role=user_preview_name]", text: "discoverable member")
    |> refute_has("[data-role=user_preview_name]", text: "hidden member")
  end
end
