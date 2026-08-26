defmodule Bonfire.UI.Boundaries.CirclesManagerLiveHandlerTest do
  use Bonfire.UI.Boundaries.ConnCase, async: false

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Circles.LiveHandler
  alias Bonfire.Boundaries.Scaffold.Instance
  alias Phoenix.LiveView.Socket

  setup do
    account = fake_account!()
    me = fake_user!(account)

    %{account: account, me: me}
  end

  test "creates a private circle and returns to the overview", %{me: me} do
    socket = manager_socket(me)

    assert {:noreply, socket} =
             LiveHandler.handle_event(
               "manager_create",
               %{
                 "circle" => %{
                   "name" => "Mutual aid",
                   "description" => "Neighbours helping neighbours"
                 }
               },
               socket
             )

    assert socket.assigns.section == :overview
    assert socket.assigns.notice == "Created Mutual aid."
    assert [%{named: %{name: "Mutual aid"}}] = socket.assigns.circles
    assert socket.assigns.total_people == 0
  end

  test "creates a circle with a blank optional description", %{me: me} do
    socket = manager_socket(me)

    assert {:noreply, socket} =
             LiveHandler.handle_event(
               "manager_create",
               %{
                 "circle" => %{
                   "name" => "Minimal",
                   "description" => ""
                 }
               },
               socket
             )

    assert socket.assigns.section == :overview
    assert socket.assigns.notice == "Created Minimal."
    assert [%{named: %{name: "Minimal"}}] = socket.assigns.circles
  end

  test "keeps invalid create input in the form", %{me: me} do
    socket =
      me
      |> manager_socket()
      |> Phoenix.Component.assign(:section, :create)

    assert {:noreply, socket} =
             LiveHandler.handle_event(
               "manager_create",
               %{
                 "circle" => %{
                   "name" => "",
                   "description" => ""
                 }
               },
               socket
             )

    assert socket.assigns.section == :create
    assert socket.assigns.form[:name].errors != []
    assert socket.assigns.circles == []
  end

  test "edits a circle and keeps the detail view open", %{me: me} do
    {:ok, circle} = Circles.create(me, %{named: %{name: "Friends"}})

    socket = manager_socket(me)

    assert {:noreply, socket} =
             LiveHandler.handle_event(
               "manager_show_detail",
               %{"circle_id" => circle.id},
               socket
             )

    assert {:noreply, socket} =
             LiveHandler.handle_event(
               "manager_set_discoverability",
               %{"id" => "public"},
               socket
             )

    assert {:noreply, socket} =
             LiveHandler.handle_event(
               "manager_save",
               %{
                 "circle" => %{
                   "name" => "Close friends",
                   "description" => "People I know well"
                 }
               },
               socket
             )

    assert socket.assigns.section == :detail
    assert socket.assigns.notice == "Changes saved."
    assert socket.assigns.selected_circle.named.name == "Close friends"
    assert socket.assigns.selected_circle.extra_info.summary == "People I know well"
    assert {"public", _label} = socket.assigns.boundary_preset
  end

  test "opens directly on a requested circle", %{me: me} do
    {:ok, circle} = Circles.create(me, %{named: %{name: "Friends"}})

    socket = manager_socket(me, circle.id)

    assert socket.assigns.section == :detail
    assert socket.assigns.selected_circle.id == circle.id
    assert socket.assigns.form[:name].value == "Friends"
    assert {"private", _label} = socket.assigns.boundary_preset
    assert socket.assigns.circles == []
  end

  test "saves a blank description without crashing", %{me: me} do
    {:ok, circle} =
      Circles.create(me, %{named: %{name: "Friends"}, extra_info: %{summary: "Old summary"}})

    socket = manager_socket(me, circle.id)

    assert {:noreply, socket} =
             LiveHandler.handle_event(
               "manager_save",
               %{"circle" => %{"name" => "Friends", "description" => ""}},
               socket
             )

    assert socket.assigns.section == :detail
    assert socket.assigns.notice == "Changes saved."
  end

  test "returns from the delete confirmation to the direct editor", %{me: me} do
    {:ok, circle} = Circles.create(me, %{named: %{name: "Friends"}})

    socket = manager_socket(me, circle.id)

    assert {:noreply, socket} =
             LiveHandler.handle_event("manager_show_delete", %{}, socket)

    assert socket.assigns.section == :delete

    assert {:noreply, socket} =
             LiveHandler.handle_event(
               "manager_show_detail",
               %{"circle_id" => circle.id},
               socket
             )

    assert socket.assigns.section == :detail
    assert socket.assigns.selected_circle.id == circle.id
    assert {:ok, _circle} = Circles.get_for_caretaker(circle.id, me)
  end

  test "does not open a stereotype circle for management", %{me: me} do
    assert [stereotype_circle | _] = Circles.get_stereotype_circles(me, [:followed, :followers])

    socket = manager_socket(me, stereotype_circle.id)

    assert socket.assigns.section == :overview
    assert socket.assigns.circle_id == nil
    assert socket.assigns.error == "Could not find this circle."
    assert {:ok, _circle} = Circles.get_for_caretaker(stereotype_circle.id, me)
  end

  test "does not open another user's circle for management", %{me: me} do
    {:ok, circle} = Circles.create(me, %{named: %{name: "Private friends"}})
    other_user = fake_user!()

    socket = manager_socket(other_user, circle.id, other_user.account)

    assert socket.assigns.section == :overview
    assert socket.assigns.selected_circle == nil
    assert socket.assigns.error == "Could not find this circle."
  end

  test "opens and edits an instance circle for an administrator", %{account: account} do
    admin = fake_admin!(account)
    {:ok, circle} = Circles.create(Instance.admin_circle(), %{named: %{name: "Trusted people"}})

    socket = manager_socket(admin, circle.id, admin.account)

    assert socket.assigns.section == :detail
    assert socket.assigns.selected_circle.id == circle.id

    assert {:noreply, socket} =
             LiveHandler.handle_event(
               "manager_save",
               %{
                 "circle" => %{
                   "name" => "Trusted volunteers",
                   "description" => "People trusted by the instance"
                 }
               },
               socket
             )

    assert socket.assigns.selected_circle.named.name == "Trusted volunteers"
  end

  test "updates discoverability independently from circle details", %{me: me, account: account} do
    {:ok, circle} = Circles.create(me, %{named: %{name: "Project team"}})
    other_user = fake_user!(account)
    socket = manager_socket(me, circle.id)

    assert {:noreply, socket} =
             LiveHandler.handle_event(
               "manager_set_discoverability",
               %{"id" => "public"},
               socket
             )

    assert {"public", _label} = socket.assigns.boundary_preset
    assert socket.assigns.to_boundaries != []
    assert socket.assigns.notice == "Circle visibility updated."
    assert {:ok, _circle} = Circles.get(circle.id, current_user: other_user)

    assert {:noreply, socket} =
             LiveHandler.handle_event(
               "manager_set_discoverability",
               %{"id" => "private"},
               socket
             )

    assert {"private", _label} = socket.assigns.boundary_preset
    assert socket.assigns.to_boundaries == []
    assert {:error, _reason} = Circles.get(circle.id, current_user: other_user)
  end

  test "deletes only after reaching the confirmation state", %{me: me} do
    {:ok, circle} = Circles.create(me, %{named: %{name: "Temporary"}})

    socket = manager_socket(me)

    assert {:noreply, socket} =
             LiveHandler.handle_event(
               "manager_show_detail",
               %{"circle_id" => circle.id},
               socket
             )

    assert {:noreply, socket} = LiveHandler.handle_event("manager_delete", %{}, socket)
    assert socket.assigns.error == "Confirm deletion before deleting this circle."
    assert {:ok, _circle} = Circles.get_for_caretaker(circle.id, me)

    assert {:noreply, socket} =
             LiveHandler.handle_event("manager_show_delete", %{}, socket)

    assert socket.assigns.section == :delete
    assert {:ok, _circle} = Circles.get_for_caretaker(circle.id, me)

    assert {:noreply, socket} =
             LiveHandler.handle_event("manager_delete", %{}, socket)

    assert socket.assigns.circles == []
    assert {:error, _} = Circles.get_for_caretaker(circle.id, me)
  end

  test "returns a widget detail view to its overview", %{me: me} do
    {:ok, circle} = Circles.create(me, %{named: %{name: "Friends"}})
    socket = manager_socket(me)

    assert {:noreply, socket} =
             LiveHandler.handle_event(
               "manager_show_detail",
               %{"circle_id" => circle.id},
               socket
             )

    assert socket.assigns.section == :detail

    assert {:noreply, socket} =
             LiveHandler.handle_event("manager_show_overview", %{}, socket)

    assert socket.assigns.section == :overview
    assert socket.assigns.selected_circle == nil
  end

  defp manager_socket(me, circle_id \\ nil, account \\ nil) do
    %Socket{
      assigns: %{
        __changed__: %{},
        __context__: %{
          current_account: account,
          current_user: me,
          current_user_id: me.id
        },
        current_account: account,
        current_user: me,
        current_user_id: me.id,
        circle_id: circle_id,
        scope: me.id,
        widget_id: nil
      }
    }
    |> LiveHandler.load_manager(circle_id)
  end
end
