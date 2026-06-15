defmodule Bonfire.UI.Boundaries.CustomizeBoundaryPersistenceTest do
  @moduledoc """
  Verifies that boundaries configured through `CustomizeBoundaryLive` are
  actually persisted to the database — not just reflected in the UI.

  - Creating a named preset (ACL) via the settings UI and toggling verb
    permissions must write the corresponding `Grant` rows to that ACL.
  - Creating a custom per-object boundary must write the expected grant rows
    onto the object's (non-preset) ACL.

  Complements `boundary_ui_management_test.exs` (asserts UI state only) and
  `boundaries_on_post.exs` (asserts visibility only).
  """
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  use Bonfire.Common.Utils
  @moduletag :ui

  alias Bonfire.Posts
  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.{Circles, Acls, Controlleds}
  alias Bonfire.Common.Repo

  setup do
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)

    Process.put(:feed_live_update_many_preload_mode, :inline)

    conn = conn(user: me, account: account)
    {:ok, conn: conn, account: account, me: me, alice: alice, bob: bob}
  end

  describe "creating a boundary preset persists grants to the DB" do
    test "toggling a verb to 'Can' in the preset editor writes a positive grant",
         %{conn: conn, me: me, alice: alice} do
      {:ok, friends} = Circles.create(me, %{named: %{name: "friends"}})
      {:ok, _} = Circles.add_to_circles(alice, friends)

      conn
      |> visit("/settings/boundaries/acls")
      |> click_button("New preset")
      |> fill_in("Enter a name for the boundary preset", with: "close friends")
      |> click_button("Create")
      |> assert_has("[data-role=acl_name]", text: "close friends")
      |> click_button(
        "button[phx-value-role='#{friends.id}'][phx-value-verb='read'][phx-value-status='1']",
        "Can"
      )
      |> assert_has(
        "[phx-value-role='#{friends.id}'][phx-value-verb='read'][phx-value-status='1'].bg-success"
      )

      # the real check: the grant must exist in the DB
      grants = acl_grants(me, "close friends")

      assert grant_present?(grants, friends.id, "Read", true),
             "expected a positive Read grant for the friends circle on the saved preset"
    end

    test "toggling 'Can' and 'Cannot' on different verbs persists both states",
         %{conn: conn, me: me, alice: alice} do
      {:ok, circle} = Circles.create(me, %{named: %{name: "bestie"}})
      {:ok, _} = Circles.add_to_circles(alice, circle)

      conn
      |> visit("/settings/boundaries/acls")
      |> click_button("New preset")
      |> fill_in("Enter a name for the boundary preset", with: "mixed perms")
      |> click_button("Create")
      |> assert_has("[data-role=acl_name]", text: "mixed perms")
      # allow reading
      |> click_button(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1']",
        "Can"
      )
      # explicitly deny boosting
      |> click_button(
        "button[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0']",
        "Cannot"
      )
      |> assert_has(
        "[phx-value-role='#{circle.id}'][phx-value-verb='read'][phx-value-status='1'].bg-success"
      )
      |> assert_has(
        "[phx-value-role='#{circle.id}'][phx-value-verb='boost'][phx-value-status='0'].bg-error"
      )

      grants = acl_grants(me, "mixed perms")

      assert grant_present?(grants, circle.id, "Read", true),
             "expected positive Read grant to persist"

      assert grant_present?(grants, circle.id, "Boost", false),
             "expected negative Boost grant to persist"
    end

    test "the saved preset survives a reload (grants are durable, not just in-memory)",
         %{conn: conn, me: me, alice: alice} do
      {:ok, friends} = Circles.create(me, %{named: %{name: "reload friends"}})
      {:ok, _} = Circles.add_to_circles(alice, friends)

      conn
      |> visit("/settings/boundaries/acls")
      |> click_button("New preset")
      |> fill_in("Enter a name for the boundary preset", with: "durable preset")
      |> click_button("Create")
      |> assert_has("[data-role=acl_name]", text: "durable preset")
      |> click_button(
        "button[phx-value-role='#{friends.id}'][phx-value-verb='reply'][phx-value-status='1']",
        "Can"
      )
      |> assert_has(
        "[phx-value-role='#{friends.id}'][phx-value-verb='reply'][phx-value-status='1'].bg-success"
      )

      # a freshly loaded query (new process) must still see the grant
      grants = acl_grants(me, "durable preset")
      assert grant_present?(grants, friends.id, "Reply", true)
    end
  end

  describe "creating a custom per-object boundary persists grants to the DB" do
    test "publishing with a custom boundary writes the granted verb to the object's ACL",
         %{me: me, alice: alice} do
      {:ok, family} = Circles.create(me, %{named: %{name: "family"}})
      {:ok, _} = Circles.add_to_circles(alice, family)

      {:ok, post} =
        Posts.publish(
          current_user: me,
          post_attrs: %{post_content: %{html_body: "custom boundary post"}},
          boundary: "custom",
          to_circles: %{family.id => "read"}
        )

      # a non-preset (custom) ACL should be attached to the object
      all_acls = Boundaries.list_object_boundaries(post.id)
      preset_count = MapSet.size(Controlleds.list_preset_acl_ids_on_object(post.id))

      assert length(all_acls) - preset_count > 0,
             "expected a custom (non-preset) ACL on the object"

      # and the actual grant for the circle must be persisted on one of them
      grants =
        all_acls
        |> Repo.maybe_preload(grants: [:verb, :subject])
        |> Enum.flat_map(&e(&1, :grants, []))

      assert Enum.any?(grants, fn g ->
               g.subject_id == family.id and verb_name(g) in ["Read", "See"]
             end),
             "expected a Read/See grant for the family circle on the object's custom boundary"
    end
  end

  # Loads the grants on the caller's named preset ACL, preloaded for assertion.
  defp acl_grants(user, acl_name) do
    acl =
      Acls.list_my(user, paginate?: false)
      |> Repo.maybe_preload(:named)
      |> Enum.find(fn a -> e(a, :named, :name, nil) == acl_name end)

    assert acl, "preset #{inspect(acl_name)} was not found among the user's ACLs"

    {:ok, acl} =
      Acls.get_for_caretaker(acl.id, user)
      |> Repo.maybe_preload(
        grants: [:verb, subject: [:named, :profile, :character, stereotyped: [:named]]]
      )

    e(acl, :grants, [])
  end

  defp grant_present?(grants, subject_id, verb_name, value) do
    Enum.any?(grants, fn g ->
      g.subject_id == subject_id and verb_name(g) == verb_name and g.value == value
    end)
  end

  defp verb_name(grant),
    do: e(grant, :verb, :verb, nil) || e(grant, :verb, nil)
end
