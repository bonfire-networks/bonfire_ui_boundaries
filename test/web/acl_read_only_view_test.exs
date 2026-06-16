defmodule Bonfire.UI.Boundaries.AclReadOnlyViewTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Boundaries.Acls

  setup do
    account = fake_account!()
    me = fake_user!(account)
    conn = conn(user: me, account: account)
    {:ok, conn: conn, account: account, me: me}
  end

  describe "Built-in / system presets are read-only" do
    test "viewing a built-in preset shows the read-only notice and no editable toggles", %{
      conn: conn
    } do
      built_in_id = Acls.get_id!(:guests_may_see_read)

      conn
      |> visit("/settings/boundaries/acl/#{built_in_id}")
      |> assert_has("[data-role=read_only_notice]")
      |> assert_has("[data-role=acl_view_name]", text: "Publicly discoverable and readable")
      |> refute_has("button[phx-value-verb][phx-value-status]")
      |> refute_has("[data-role=toggle_advanced_permissions]")
    end

    test "the ACLs list shows system presets with inline expandable summaries", %{conn: conn} do
      conn
      |> visit("/settings/boundaries/acls")
      |> assert_has("li", text: "System presets")
      |> assert_has("[data-role=toggle_preset]")
      |> assert_has("button[data-role=toggle_preset]", text: "Publicly discoverable and readable")
      |> refute_has("li", text: "This preset doesn't grant any permissions")
      |> assert_has("li", text: "Anyone on the internet")
    end
  end
end
