defmodule Bonfire.UI.Boundaries.RemoveFromAclChecksOnceTest do
  @moduledoc "Removing someone from a boundary preset (`AclLive.remove_from_acl/2`, which the group permissions editor's remove button calls) checks that the person may edit it once, and the removal goes through the unchecked write. Counted by call tracing while it runs."
  use Bonfire.UI.Boundaries.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Boundaries.{Acls, Grants}
  alias Bonfire.UI.Boundaries.AclLive

  defp socket(acl, user) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        acl: acl,
        read_only: false,
        __context__: %{current_user: user, current_user_id: user.id}
      }
    }
  end

  defp stored(acl, me),
    do: Grants.list_for_acl(acl.id, current_user: me, skip_boundary_check: true)

  # the refresh of the editor after the removal needs a mounted component, which a bare socket isn't: only the removal is of interest
  defp remove(subject, socket) do
    AclLive.remove_from_acl(subject, socket)
  rescue
    _ -> :refresh_needs_a_mounted_component
  end

  test "removing someone checks the preset once" do
    me = fake_user!(fake_account!())
    someone = fake_user!(fake_account!())
    stranger = fake_user!(fake_account!())
    {:ok, acl} = Acls.simple_create(me, "a preset")
    Grants.grant_role(someone.id, acl.id, "read", current_user: me)
    assert stored(acl, me) != [], "control: they are in the preset to begin with"

    check = {Bonfire.Boundaries.Acls, :may_edit?, 2}
    Code.ensure_loaded!(Bonfire.Boundaries.Acls)
    tracer = spawn_link(fn -> count_calls(0) end)
    :erlang.trace(self(), true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern(check, true, [:local])

    try do
      remove(someone.id, socket(acl, me))
    after
      :erlang.trace(self(), false, [:call])
      :erlang.trace_pattern(check, false, [:local])
    end

    send(tracer, {:done, self()})
    assert_receive {:count, 1}, 5000

    assert stored(acl, me) == [], "they were removed"

    # and someone who may not edit it can't
    Grants.grant_role(someone.id, acl.id, "read", current_user: me)
    remove(someone.id, socket(acl, stranger))
    assert stored(acl, me) != []
  end

  defp count_calls(acc) do
    receive do
      {:trace, _pid, :call, {Bonfire.Boundaries.Acls, :may_edit?, _args}} -> count_calls(acc + 1)
      {:done, from} -> send(from, {:count, acc})
    end
  end
end
