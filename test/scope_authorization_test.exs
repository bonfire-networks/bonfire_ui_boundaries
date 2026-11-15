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
