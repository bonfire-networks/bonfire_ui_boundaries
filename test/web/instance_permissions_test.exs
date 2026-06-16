defmodule Bonfire.UI.Boundaries.InstancePermissionsTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Boundaries.Scaffold.Instance
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Grants
  alias Bonfire.Boundaries.Verbs

  setup do
    account = fake_account!()
    admin = fake_admin!(account)
    conn = conn(user: admin, account: account)
    {:ok, conn: conn, account: account, admin: admin}
  end

  describe "Instance permissions (capability checklist)" do
    test "opens read-first: capabilities shown, no toggles until Edit", %{conn: conn} do
      conn
      |> visit("/settings/instance/boundaries/acl")
      |> assert_has("h1, [data-role=acl_name], *", text: "Instance permissions")
      |> assert_has("li", text: "Configure the instance")
      |> assert_has("li", text: "Moderate")
      |> assert_has("li", text: "Grant roles & permissions")
      |> refute_has("*", text: "Boost an object")
      |> assert_has("[data-role=toggle_edit]")
      |> refute_has("[data-role=capability_toggle]")
    end

    test "Edit reveals capability toggles", %{conn: conn} do
      conn
      |> visit("/settings/instance/boundaries/acl")
      |> click_button("[data-role=toggle_edit]", "Edit")
      |> assert_has("[data-role=capability_toggle]")
    end

    test "default seeded roles produce no half-granted (partial) capabilities", %{conn: conn} do
      mod_circle = Instance.mod_circle()

      conn
      |> visit("/settings/instance/boundaries/acl")
      |> click_button("[data-role=toggle_edit]", "Edit")
      |> refute_has("[data-role=capability_toggle][data-state='partial']")
      |> assert_has(
        "button[phx-value-capability='configure'][phx-value-audience='#{mod_circle}'][data-state='off']"
      )
      |> assert_has(
        "button[phx-value-capability='curate'][phx-value-audience='#{mod_circle}'][data-state='on']"
      )
    end

    test "does not expose the rename/delete header button (can't delete instance ACL)",
         %{conn: conn} do
      conn
      |> visit("/settings/instance/boundaries/acl")
      |> refute_has("[data-role=edit_boundary]")
      |> refute_has("*", text: "Delete this boundary")
    end

    test "does not offer public audiences (guest / fediverse) as capability targets",
         %{conn: conn} do
      guest_circle = Circles.get_id(:guest)
      activity_pub_circle = Circles.get_id(:activity_pub)

      conn
      |> visit("/settings/instance/boundaries/acl")
      |> click_button("[data-role=toggle_edit]", "Edit")
      |> refute_has("button[data-role=capability_toggle][phx-value-audience='#{guest_circle}']")
      |> refute_has(
        "button[data-role=capability_toggle][phx-value-audience='#{activity_pub_circle}']"
      )
    end

    test "clicking an already-granted capability revokes it (never escalates)",
         %{conn: conn} do
      acl_id = Instance.instance_acl()
      mod_circle = Instance.mod_circle()
      mediate_verb = Verbs.get_id(:mediate)

      conn
      |> visit("/settings/instance/boundaries/acl")
      |> click_button("[data-role=toggle_edit]", "Edit")
      |> assert_has(
        "button[phx-value-capability='moderate'][phx-value-audience='#{mod_circle}'][data-state='on']"
      )
      |> click_button(
        "button[phx-value-capability='moderate'][phx-value-audience='#{mod_circle}']",
        "Instance Moderators"
      )
      |> refute_has(
        "button[phx-value-capability='moderate'][phx-value-audience='#{mod_circle}'][data-state='on']"
      )

      refute Bonfire.Common.Repo.get_by(Bonfire.Data.AccessControl.Grant,
               acl_id: acl_id,
               subject_id: mod_circle,
               verb_id: mediate_verb
             )
    end

    test "Moderate starts granted to Instance Moderators (reflects the scaffold)", %{conn: conn} do
      mod_circle = Instance.mod_circle()

      conn
      |> visit("/settings/instance/boundaries/acl")
      |> click_button("[data-role=toggle_edit]", "Edit")
      |> assert_has(
        "button[phx-value-capability='moderate'][phx-value-audience='#{mod_circle}'][data-state='on']"
      )
    end

    test "edit mode offers instance-defined circles as candidates", %{conn: conn} do
      {:ok, circle} =
        Circles.create(Instance.admin_circle(), %{named: %{name: "Trusted volunteers"}})

      conn
      |> visit("/settings/instance/boundaries/acl")
      |> click_button("[data-role=toggle_edit]", "Edit")
      |> assert_has(
        "button[data-role=capability_toggle][phx-value-audience='#{circle.id}']",
        text: "Trusted volunteers"
      )
    end

    test "granting a capability to a circle writes instance grants", %{conn: conn} do
      acl_id = Instance.instance_acl()
      local_circle = Circles.get_id(:local)
      mediate_verb = Verbs.get_id(:mediate)

      conn
      |> visit("/settings/instance/boundaries/acl")
      |> click_button("[data-role=toggle_edit]", "Edit")
      |> refute_has(
        "button[phx-value-capability='moderate'][phx-value-audience='#{local_circle}'][data-state='on']"
      )
      |> click_button(
        "button[phx-value-capability='moderate'][phx-value-audience='#{local_circle}']",
        "Local users"
      )
      |> assert_has("*", text: "Instance permissions updated")
      |> assert_has(
        "button[phx-value-capability='moderate'][phx-value-audience='#{local_circle}'][data-state='on']"
      )

      grant =
        Bonfire.Common.Repo.get_by(Bonfire.Data.AccessControl.Grant,
          acl_id: acl_id,
          subject_id: local_circle,
          verb_id: mediate_verb
        )

      assert grant && grant.value == true
    end
  end
end
