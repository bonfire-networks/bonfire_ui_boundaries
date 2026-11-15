defmodule Bonfire.UI.Boundaries.BuiltInAclEventsTest do
  @moduledoc "A built-in boundary preset is shared by every object that uses it, so an ordinary user may open it to read it but not change or delete it. The page puts the opened preset in the socket, and the edit and delete events act on that preset, so each must check who is sending it."
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  import Ecto.Query

  alias Bonfire.Boundaries.{Acls, Verbs}
  alias Bonfire.Data.AccessControl.{Acl, Grant}

  setup do
    account = fake_account!()
    me = fake_user!(account)
    acl_id = Acls.get_id!(:guests_may_see_read)

    {:ok, view, _html} =
      live(conn(user: me, account: account), "/settings/boundaries/acl/#{acl_id}")

    render_async(view)

    {:ok, me: me, acl_id: acl_id, view: view}
  end

  defp repo, do: Bonfire.Common.Config.repo()

  defp name_of(acl_id) do
    case repo().get(Acl, acl_id) |> repo().maybe_preload(:named) do
      %{named: %{name: name}} -> name
      _ -> nil
    end
  end

  defp granted?(acl_id, subject_id, verb) do
    repo().exists?(
      from g in Grant,
        where:
          g.acl_id == ^acl_id and g.subject_id == ^subject_id and
            g.verb_id == ^Verbs.get!(verb)[:id]
    )
  end

  test "I cannot grant myself a verb on a built-in preset", %{me: me, acl_id: acl_id, view: view} do
    refute granted?(acl_id, me.id, :edit), "control: I have no grant on it to begin with"

    view
    |> with_target("#boundaries_acl_acl")
    |> render_click("edit_verb_value", %{
      "subject" => %{me.id => %{Verbs.get!(:edit)[:id] => "1"}}
    })

    refute granted?(acl_id, me.id, :edit)
  end

  test "I cannot rename a built-in preset", %{acl_id: acl_id, view: view} do
    refute name_of(acl_id) == "Hijacked", "control: it is not called that to begin with"

    render_hook(view, "Bonfire.Boundaries:edit_acl", %{"named" => %{"name" => "Hijacked"}})

    refute name_of(acl_id) == "Hijacked"
  end

  test "I cannot delete a built-in preset", %{acl_id: acl_id, view: view} do
    assert repo().get(Acl, acl_id), "control: it exists to begin with"

    render_hook(view, "Bonfire.Boundaries:acl_delete", %{})

    assert repo().get(Acl, acl_id)
  end
end
