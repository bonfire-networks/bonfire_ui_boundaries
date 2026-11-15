defmodule Bonfire.UI.Boundaries.MyAclsSectionAssignTest do
  @moduledoc "`assign_attrs/2` is how server-side code sets assigns on a component's socket (the client can't: its `assign` event is refused, see `client_assign_impersonation_test.exs`). This covers that function alone, not any button: `MyAclsLive` no longer has a row that sends it."
  use ExUnit.Case, async: true
  @moduletag :ui

  alias Bonfire.UI.Common.LiveHandlers

  # a bare socket like a mounted component's: it only sets assigns, so no database is needed
  defp socket do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, section: :acls}}
  end

  test "`assign_attrs/2` sets the given attributes on the socket" do
    assert socket().assigns.section == :acls, "control: starts on the preset list"

    socket = LiveHandlers.assign_attrs(socket(), %{"section" => "new"})

    assert socket.assigns.section in ["new", :new]
  end
end
