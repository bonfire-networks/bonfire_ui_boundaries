defmodule Bonfire.UI.Boundaries.ScopeAuthorizationTest do
  @moduledoc "The instance-wide block lists and allowlist are changed only by someone acting who may: a missing user is never treated as the system, since a guest has no user either, and only an explicit `skip_boundary_check: true` is."
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Boundaries.Allowlist
  alias Bonfire.Boundaries.Blocks

  # `can?(_, _, :instance)` memoises per process, so each acting user is asked about once
  setup do
    %{
      me: fake_user!(fake_account!()),
      admin: fake_admin!(fake_account!()),
      target: fake_user!(fake_account!())
    }
  end

  describe "Circles membership" do
    alias Bonfire.Boundaries.Acls
    alias Bonfire.Boundaries.Circles
    alias Bonfire.Boundaries.Grants

    defp circle_with_grants(owner, user, grants) do
      {:ok, circle} = Circles.create(owner, %{named: %{name: "shared #{Ecto.UUID.generate()}"}})
      {:ok, acl} = Acls.get_or_create_object_custom_acl(circle, owner)

      Enum.each(grants, fn {verb, value} ->
        Grants.grant(user.id, acl.id, verb, value, skip_boundary_check: true)
      end)

      circle
    end

    test "someone who may configure a circle they may read changes its members, but not when read is denied",
         %{me: me, target: target} do
      owner = fake_user!(fake_account!())

      readable = circle_with_grants(owner, me, [{:see, true}, {:read, true}, {:configure, true}])
      assert {:ok, _} = Circles.add_to_circles(target, readable, current_user: me)

      assert Circles.is_encircled_by?(target, readable),
             "control: configuring a readable circle works"

      unreadable =
        circle_with_grants(owner, me, [{:see, true}, {:read, false}, {:configure, true}])

      assert {:error, _} = Circles.add_to_circles(target, unreadable, current_user: me)
      refute Circles.is_encircled_by?(target, unreadable)
    end
  end

  describe "an instance admin whose account's admin flag isn't loaded" do
    alias Bonfire.Boundaries.Acls
    alias Bonfire.Boundaries.Circles
    alias Bonfire.Data.Identity.Account

    # each acting user with their account loaded, as `current_account(opts)` finds it on them; the admin both with and without its `instance_admin` (an admin action must not silently refuse the second, it is an error in tests)
    setup do
      repo = Bonfire.Common.Config.repo()
      admin_account = fake_account!()
      admin = fake_admin!(admin_account)
      user_account = fake_account!()
      user = fake_user!(user_account)

      unloaded = repo.get!(Account, admin_account.id)
      assert %Ecto.Association.NotLoaded{} = unloaded.instance_admin

      %{
        loaded_admin: Map.put(admin, :account, repo.preload(unloaded, :instance_admin)),
        unloaded_admin: Map.put(admin, :account, unloaded),
        non_admin:
          Map.put(
            user,
            :account,
            repo.preload(repo.get!(Account, user_account.id), :instance_admin)
          )
      }
    end

    test "changes who is in Suggested Profiles, which the admin circle takes care of", %{
      loaded_admin: loaded_admin,
      unloaded_admin: unloaded_admin,
      non_admin: non_admin,
      target: target
    } do
      circle = Bonfire.Boundaries.Scaffold.Instance.suggested_profiles_circle()

      assert {:ok, _} = Circles.add_to_circles(target, circle, current_user: loaded_admin)
      assert Circles.is_encircled_by?(target, circle), "control: an admin adds to it"
      Circles.remove_from_circles(target, circle, current_user: loaded_admin)
      refute Circles.is_encircled_by?(target, circle), "control: an admin removes from it"

      assert_raise RuntimeError, ~r/preload instance_admin/, fn ->
        Circles.add_to_circles(target, circle, current_user: unloaded_admin)
      end

      assert_raise RuntimeError, ~r/preload instance_admin/, fn ->
        Circles.remove_from_circles(target, circle, current_user: unloaded_admin)
      end

      assert {:error, _} =
               Circles.add_to_circles(target, circle, current_user: non_admin)

      refute Circles.is_encircled_by?(target, circle)
    end

    test "gets a circle and a preset the admin circle takes care of", %{
      loaded_admin: loaded_admin,
      unloaded_admin: unloaded_admin,
      non_admin: non_admin
    } do
      {:ok, circle} = Circles.create(:instance, %{named: %{name: "an instance circle"}})
      {:ok, acl} = Acls.create(%{named: %{name: "an instance preset"}}, current_user: :instance)

      for {name, get} <- [
            circle: &Circles.get_for_caretaker(circle.id, &1, current_user: &1),
            preset: &Acls.get_for_caretaker(acl.id, &1, current_user: &1)
          ] do
        assert {:ok, _} = get.(loaded_admin), "control: an admin gets the #{name}"

        assert_raise RuntimeError, ~r/preload instance_admin/, fn -> get.(unloaded_admin) end

        assert {:error, :not_found} = get.(non_admin), "a non-admin doesn't get the #{name}"
      end
    end

    test "can? on the instance fetches the admin flag only when asked to", %{
      loaded_admin: loaded_admin,
      unloaded_admin: unloaded_admin
    } do
      assert Bonfire.Boundaries.can?(loaded_admin.account, :assign, :instance), "control"

      refute Bonfire.Boundaries.can?(unloaded_admin.account, :assign, :instance),
             "without the option, the flag isn't fetched"

      assert_raise RuntimeError, ~r/preload instance_admin/, fn ->
        Bonfire.Boundaries.can?(unloaded_admin.account, :assign, :instance,
          ensure_admin_check: true
        )
      end

      refute Bonfire.Boundaries.can?(nil, :assign, :instance, ensure_admin_check: true)
    end
  end

  describe "Built-in circles" do
    alias Bonfire.Boundaries.Circles
    alias Bonfire.Boundaries.Scaffold.Instance

    setup do
      {:ok, moderator} =
        Bonfire.Me.Users.make_moderator(fake_user!(fake_account!()), skip_boundary_check: true)

      %{moderator: moderator}
    end

    # what a built-in's config entry says about who may change its members, for this test process only
    defp encircle_requires(circle_name, rule) do
      circles =
        Keyword.update!(Circles.circles(), circle_name, &Map.put(&1, :encircle_requires, rule))

      Process.put([:bonfire_boundaries, :circles], circles)
    end

    test "nobody changes who is a guest, a local user, a remote user or an admin through a plain add, not even an admin",
         %{admin: admin, target: target} do
      for name <- [:guest, :local, :activity_pub, :admin] do
        id = Circles.circles()[name][:id]
        # a local user is already in Local users, so what matters is that the add changes nothing
        was_member? = Circles.is_encircled_by?(target, id)

        assert {:error, _} = Circles.add_to_circles(target, id, current_user: admin),
               "an admin added someone to the #{name} circle"

        assert Circles.is_encircled_by?(target, id) == was_member?
      end
    end

    test "admins and moderators change who is in Suggested Profiles, as its config says", %{
      admin: admin,
      moderator: moderator,
      me: me,
      target: target
    } do
      circle = Instance.suggested_profiles_circle()

      assert {:ok, _} = Circles.add_to_circles(target, circle, current_user: admin)
      assert Circles.is_encircled_by?(target, circle)
      Circles.remove_from_circles(target, circle, current_user: moderator)
      refute Circles.is_encircled_by?(target, circle), "a moderator removes from it"
      assert {:ok, _} = Circles.add_to_circles(target, circle, current_user: moderator)

      assert {:error, _} = Circles.add_to_circles(me, circle, current_user: me)
      refute Circles.is_encircled_by?(me, circle)
    end

    test "a built-in's config decides who changes its members: a verb on the instance, on the circle, or nobody",
         %{admin: admin, moderator: moderator, target: target} do
      circle = Instance.suggested_profiles_circle()

      encircle_requires(:suggested_profiles, false)

      assert {:error, _} = Circles.add_to_circles(target, circle, current_user: admin),
             "`false` lets nobody, admins included"

      # its own ACL, `mods_may_manage`, gives admins every verb and moderators no `:assign`
      encircle_requires(:suggested_profiles, {:assign, :circle})

      assert {:error, _} =
               Circles.add_to_circles(target, circle, current_user: moderator)

      assert {:ok, _} = Circles.add_to_circles(target, circle, current_user: admin)
      assert Circles.is_encircled_by?(target, circle)
    end

    test "admins make someone a moderator through the moderators circle, and moderators don't", %{
      admin: admin,
      moderator: moderator,
      target: target
    } do
      circle = Instance.mod_circle()

      assert {:error, _} =
               Circles.add_to_circles(target, circle, current_user: moderator)

      assert {:ok, _} = Circles.add_to_circles(target, circle, current_user: admin)
      assert Circles.is_encircled_by?(target, circle)
    end
  end

  describe "Blocks, instance-wide" do
    test "nobody acting, and no skip, is refused for a bare scope or a keyword one", %{
      target: target
    } do
      assert {:error, _} = Blocks.block(target, :ghost, :instance_wide)
      assert {:error, _} = Blocks.block(target, :ghost, scope: :instance_wide)
      assert {:error, _} = Blocks.instance_wide_block(target, :ghost, [])

      refute Blocks.is_blocked?(target, :ghost, :instance_wide)
    end

    test "someone who may not block on the instance is refused, an admin is not", %{
      me: me,
      admin: admin,
      target: target
    } do
      refute Bonfire.Boundaries.can?(me, :block, :instance),
             "control: I may not block on the instance"

      assert {:error, _} = Blocks.block(target, :ghost, current_user: me, scope: :instance_wide)
      refute Blocks.is_blocked?(target, :ghost, :instance_wide)

      assert {:ok, _} = Blocks.block(target, :ghost, current_user: admin, scope: :instance_wide)
      assert Blocks.is_blocked?(target, :ghost, :instance_wide)
    end

    test "lifting needs the same standing, and a system path names itself with the skip", %{
      me: me,
      admin: admin,
      target: target
    } do
      {:ok, _} = Blocks.block(target, :ghost, current_user: admin, scope: :instance_wide)
      assert Blocks.is_blocked?(target, :ghost, :instance_wide), "control: they are blocked"

      assert {:error, _} = Blocks.unblock(target, :ghost, :instance_wide)
      assert {:error, _} = Blocks.unblock(target, :ghost, current_user: me, scope: :instance_wide)
      assert Blocks.is_blocked?(target, :ghost, :instance_wide)

      assert {:ok, _} =
               Blocks.unblock(target, :ghost, scope: :instance_wide, skip_boundary_check: true)

      refute Blocks.is_blocked?(target, :ghost, :instance_wide)
    end

    test "blocking for myself needs no standing on the instance", %{me: me, target: target} do
      assert {:ok, _} = Blocks.block(target, :ghost, current_user: me)
      assert Blocks.is_blocked?(target, :ghost, current_user: me)
      refute Blocks.is_blocked?(target, :ghost, :instance_wide)
    end
  end

  describe "Allowlist" do
    test "nobody acting, and no skip, is refused", %{target: target} do
      assert {:error, _} = Allowlist.allow(target)
      assert {:error, _} = Allowlist.allow(target, :instance_wide)
      assert {:error, _} = Allowlist.allow(target, scope: :instance_wide)

      refute Allowlist.is_allowlisted?(target, :instance_wide)
    end

    test "someone who may not configure the instance cannot change its allowlist, an admin can",
         %{me: me, admin: admin, target: target} do
      refute Bonfire.Boundaries.can?(me, :configure, :instance),
             "control: I may not configure the instance"

      assert {:error, _} = Allowlist.allow(target, current_user: me, scope: :instance_wide)
      refute Allowlist.is_allowlisted?(target, :instance_wide)

      assert {:ok, _} = Allowlist.allow(target, current_user: admin, scope: :instance_wide)
      assert Allowlist.is_allowlisted?(target, :instance_wide)

      assert {:error, _} = Allowlist.unallow(target, current_user: me, scope: :instance_wide)
      assert Allowlist.is_allowlisted?(target, :instance_wide)

      assert {:ok, _} = Allowlist.unallow(target, current_user: admin, scope: :instance_wide)
      refute Allowlist.is_allowlisted?(target, :instance_wide)
    end

    test "my own allowlist is mine to change, and a system path names itself with the skip", %{
      me: me,
      target: target
    } do
      assert {:ok, _} = Allowlist.allow(target, current_user: me)
      assert Allowlist.is_allowlisted?(target, current_user: me)
      refute Allowlist.is_allowlisted?(target, :instance_wide)

      assert {:ok, _} = Allowlist.allow(target, scope: :instance_wide, skip_boundary_check: true)
      assert Allowlist.is_allowlisted?(target, :instance_wide)
    end
  end
end
