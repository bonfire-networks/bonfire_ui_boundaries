defmodule Bonfire.UI.Boundaries.Web.BoundaryIconLive do
  use Bonfire.UI.Common.Web, :stateful_component

  # Tip: use this component if you want to auto-preload boundaries (async), otherwise use `BoundaryIconStatelessLive` if a parent component can provide the `object_boundary` data

  prop object, :any, required: true

  # can also provide it manually
  prop object_boundary, :any, default: nil
  prop boundary_preset, :any, default: nil
  prop object_type, :any, default: nil

  prop scope, :any, default: nil

  prop with_icon, :boolean, default: false
  prop with_label, :boolean, default: false

  prop class, :css_class, default: nil

  def update_many(assigns_sockets) do
    (Bonfire.Boundaries.LiveHandler.update_many(assigns_sockets,
       caller_module: __MODULE__
     ) || assigns_sockets)
    |> Enum.map(fn
      {assigns, socket} ->
        socket
        |> Phoenix.Component.assign(assigns)

      socket ->
        socket
    end)
  end
end
