defmodule Bonfire.UI.Boundaries.ProfileBlockedIndicatorLive do
  use Bonfire.UI.Common.Web, :stateful_component
  # import Bonfire.UI.Me
  # import Bonfire.Common.Media

  prop user, :map
  prop boundary_preset, :any, default: nil

  prop skip_preload, :boolean, default: false
  prop ghosted?, :boolean, default: nil
  prop ghosted_instance_wide?, :boolean, default: nil
  prop silenced?, :boolean, default: nil
  prop silenced_instance_wide?, :boolean, default: nil

  prop is_local?, :boolean, default: false
  # prop block_status, :any, default: nil

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)

    user = e(assigns(socket), :user, nil)

    {:ok,
     socket
     |> assign(
       Bonfire.Boundaries.Blocks.LiveHandler.preload_one(
         user,
         current_user(socket)
       )
       |> debug("any_block?")
     )}
  end

  # TODO: to avoid n+1
  # def update_many([{%{skip_preload: true}, _}] = assigns_sockets) do
  #   assigns_sockets
  # end
  # def update_many(assigns_sockets) do
  #   Bonfire.Boundaries.Blocks.LiveHandler.update_many(assigns_sockets, caller_module: __MODULE__)
  #   |> debug("any_blocks?")
  # end
end
