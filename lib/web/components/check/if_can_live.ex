defmodule Bonfire.UI.Boundaries.IfCan do
  use Bonfire.UI.Common.Web, :stateful_component

  @moduledoc "Shows its content only if the viewer may do `check_object_boundary`'s verbs on `object`, checked in one batch for every `IfCan` on the page (`Bonfire.Boundaries.LiveHandler.maybe_check_boundaries/2`). Otherwise it shows `if_not` or `if_not_say`, or with neither renders an empty `hidden` root."

  prop object, :any
  # never read: the verbs are now `check_object_boundary`'s
  # prop verbs, :any, default: nil
  prop if_not_say, :string, default: nil

  @doc "The verbs to check, eg. `[:see]`, or `true` for `:read`. Falsy means no check, eg. when there's no viewer to check for, and the content shows."
  prop check_object_boundary, :any, default: true

  # internal use only:
  prop boundary_can, :boolean, default: false

  slot default
  slot if_not

  def update_many(assigns_sockets) do
    assigns_sockets
    |> Bonfire.Boundaries.LiveHandler.maybe_check_boundaries(caller_module: __MODULE__)
    # LiveView wants the sockets back, with the checked assigns on them
    |> Enum.map(fn
      {assigns, socket} -> Phoenix.Component.assign(socket, assigns)
      socket -> socket
    end)
  end
end
