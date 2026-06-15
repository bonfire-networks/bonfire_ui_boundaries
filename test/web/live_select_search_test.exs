defmodule Bonfire.UI.Boundaries.LiveSelectSearchTest do
  @moduledoc """
  Covers every live_select user-search in boundaries UIs, end to end where the
  surface is routable (event targeting → handler → search → send_update →
  dropdown options) and at the handler level for composer-embedded components.
  """
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Boundaries.Circles

  setup do
    account = fake_account!()
    me = fake_user!(account, %{name: "Selfsearch Owner"})
    findable = fake_user!(account, %{name: "Findable Person"})
    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, me: me, findable: findable}
  end

  describe "block pages (CircleMembersLive)" do
    for path <- ["/silenced", "/ghosted", "/blocked"] do
      test "searching a user to add on #{path} shows matching options", %{
        conn: conn,
        findable: findable
      } do
        {:ok, view, _html} = live(conn, unquote(path))

        ls_id = live_select_simulate_search(view, "#circle_members", "findable")

        assert has_element?(view, "##{ls_id} li", findable.profile.name)
      end
    end

    test "I cannot find myself when searching who to silence", %{conn: conn, me: me} do
      {:ok, view, _html} = live(conn, "/silenced")

      ls_id = live_select_simulate_search(view, "#circle_members", "selfsearch")

      refute has_element?(view, "##{ls_id} li", me.profile.name)
    end

    test "selecting a user to silence renders immediately with its name (not Unknown)", %{
      conn: conn,
      findable: findable
    } do
      {:ok, view, _html} = live(conn, "/silenced")

      view
      |> with_target("#circle_members")
      |> render_hook("multi_select", %{
        "data" => %{
          "id" => findable.id,
          "name" => findable.profile.name,
          "username" => findable.character.username
        },
        "text" => ""
      })

      html = render(view)
      assert html =~ findable.profile.name
      refute html =~ "Unknown"
    end
  end

  describe "circle members page (CircleMembersLive)" do
    test "searching a user to add to my circle shows matching options", %{
      conn: conn,
      me: me,
      findable: findable
    } do
      {:ok, circle} = Circles.create(me, %{named: %{name: "besties"}})

      {:ok, view, _html} = live(conn, "/settings/boundaries/circle/#{circle.id}")

      ls_id = live_select_simulate_search(view, "#circle_members", "findable")

      assert has_element?(view, "##{ls_id} li", findable.profile.name)
    end
  end

  describe "ACL page (AclLive)" do
    test "searching a user to add to a boundary preset shows matching options", %{
      conn: conn,
      me: me,
      findable: findable
    } do
      {:ok, acl} =
        Bonfire.Boundaries.Acls.create(%{named: %{name: "my preset"}}, current_user: me)

      {:ok, view, _html} = live(conn, "/settings/boundaries/acl/#{acl.id}")

      ls_id = live_select_simulate_search(view, "#boundaries_acl", "findable")

      assert has_element?(view, "##{ls_id} li", findable.profile.name)
    end
  end

  describe "composer-embedded components (handler level)" do
    test "PreviewBoundariesLive returns user options via send_update", %{findable: findable} do
      assert {:noreply, _} =
               Bonfire.UI.Boundaries.PreviewBoundariesLive.handle_event(
                 "live_select_change",
                 %{"id" => "ls_preview", "text" => "findable"},
                 fake_socket()
               )

      assert_received {:phoenix, :send_update, {{LiveSelect.Component, "ls_preview"}, assigns}}
      assert option_ids(assigns.options) |> Enum.member?(findable.id)
    end

    test "CustomizeBoundaryLive returns user options via send_update", %{findable: findable} do
      assert {:noreply, _} =
               Bonfire.UI.Boundaries.CustomizeBoundaryLive.handle_event(
                 "live_select_change",
                 %{"id" => "ls_customize", "text" => "findable"},
                 fake_socket()
               )

      assert_received {:phoenix, :send_update, {{LiveSelect.Component, "ls_customize"}, assigns}}
      assert option_ids(assigns.options) |> Enum.member?(findable.id)
    end

    test "AclLive returns user options via send_update", %{findable: findable} do
      assert {:noreply, _} =
               Bonfire.UI.Boundaries.AclLive.handle_event(
                 "live_select_change",
                 %{"id" => "ls_acl", "text" => "findable"},
                 fake_socket()
               )

      assert_received {:phoenix, :send_update, {{LiveSelect.Component, "ls_acl"}, assigns}}
      assert option_ids(assigns.options) |> Enum.member?(findable.id)
    end

    test "Circles.LiveHandler returns user options via send_update", %{
      me: me,
      findable: findable
    } do
      assert {:noreply, _} =
               Bonfire.Boundaries.Circles.LiveHandler.handle_event(
                 "live_select_change",
                 %{"field" => "multi_select", "id" => "ls_circles", "text" => "findable"},
                 fake_socket(%{current_user: me})
               )

      assert_received {:phoenix, :send_update, {{LiveSelect.Component, "ls_circles"}, assigns}}

      assert Enum.any?(assigns.options, fn
               {_label, id} -> id == findable.id
               _ -> false
             end)
    end

    test "CircleMembersLive excludes the current user for blocking circle types", %{
      me: me,
      findable: _findable
    } do
      assert {:noreply, _} =
               Bonfire.UI.Boundaries.CircleMembersLive.handle_event(
                 "live_select_change",
                 %{"id" => "ls_members", "text" => "selfsearch"},
                 fake_socket(%{current_user: me, circle_type: :silence})
               )

      assert_received {:phoenix, :send_update, {{LiveSelect.Component, "ls_members"}, assigns}}
      refute option_ids(assigns.options) |> Enum.member?(me.id)
    end
  end

  defp fake_socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(:__context__, %{current_user: assigns[:current_user]})
    |> Phoenix.Component.assign(assigns)
  end

  defp option_ids(options) do
    Enum.map(options, fn
      {_label, %{id: id}} -> id
      {_label, id} when is_binary(id) -> id
      _ -> nil
    end)
  end
end
