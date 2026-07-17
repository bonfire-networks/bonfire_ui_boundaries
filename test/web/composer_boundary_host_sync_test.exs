defmodule Bonfire.UI.Boundaries.ComposerBoundaryHostSyncTest do
  @moduledoc """
  Regression tests for the composer boundary being reset to "public" on page
  navigation (dashboard → /groups etc.) while the composer was open with a
  boundary selected.

  The composer (`SmartInputContainerLive`) is hosted in a LiveView — usually the
  sticky `PersistentLive` — whose template re-passes `to_boundaries`/`to_circles`
  props down on every re-render (eg. each page navigation re-renders it via the
  forwarded `selected_tab` etc). `Bonfire.Boundaries.LiveHandler.prepare_assigns/1`
  seeds the host's copy with the default boundary ("public") via
  `send_self_global`, so a boundary picked in the composer MUST be synced to the
  host the same way — otherwise the next host re-render pushes the stale
  "public" back into the composer, overwriting the user's selection (the
  container's `preserve_reply_state` only preserves when the incoming value is
  nil, and a stale non-nil prop wins).

  These tests call the event handlers directly and assert the host-sync message
  (`{:assign_global, ...}`, handled by `Bonfire.UI.Common.LiveHandlers`) is sent
  to the host LiveView process (`self()` here).
  """
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"

  alias Bonfire.Boundaries.LiveHandler

  defp blank_socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(assigns)
  end

  test "replace_boundary syncs the new selection to the host LiveView process" do
    {:noreply, _socket} =
      LiveHandler.handle_event(
        "replace_boundary",
        %{"id" => "acl_123", "name" => "My group"},
        blank_socket()
      )

    assert_receive {:assign_global, assigns}
    assert assigns[:to_boundaries] == [{"acl_123", "My group"}]
    # circles are reset alongside a boundary change
    assert assigns[:to_circles] == []
    assert assigns[:exclude_circles] == []
  end

  test "select_boundary syncs the new selection to the host LiveView process" do
    {:noreply, _socket} =
      LiveHandler.handle_event(
        "select_boundary",
        %{"id" => "acl_456", "name" => "Besties"},
        blank_socket(%{to_boundaries: [{"public", "Public"}]})
      )

    assert_receive {:assign_global, assigns}
    assert {"acl_456", "Besties"} in (assigns[:to_boundaries] || [])
    assert assigns[:to_circles] == []
  end

  test "circle selection syncs to the host LiveView process" do
    {:noreply, _socket} =
      LiveHandler.handle_event(
        "select",
        %{"to_circles" => [], "exclude_circles" => []},
        blank_socket(%{to_circles: [], exclude_circles: []})
      )

    assert_receive {:assign_global, assigns}
    assert Keyword.has_key?(assigns, :to_circles) or Map.has_key?(Map.new(assigns), :to_circles)
  end
end
