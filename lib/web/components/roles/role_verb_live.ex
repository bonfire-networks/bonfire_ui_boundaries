defmodule Bonfire.UI.Boundaries.RoleVerbLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop verb, :any, required: true
  prop value, :boolean, default: nil
  prop read_only, :boolean, default: false
  prop mini, :boolean, default: false
  prop all_verbs, :list
  # prop exclude_activity_types, :list, default: []

  prop event_target, :any, default: nil
  prop name, :any, default: nil

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end
end
