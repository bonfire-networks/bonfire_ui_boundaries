defmodule Bonfire.UI.Boundaries.ProfileBlockedIndicatorLive do
  use Bonfire.UI.Common.Web, :stateful_component
  # import Bonfire.UI.Me
  # import Bonfire.Common.Media

  prop user, :map
  prop boundary_preset, :any, default: nil

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
    user_id = uid(user)

    # Only re-run block-status queries when the user prop changes — parent
    # re-renders otherwise trigger an n+1.
    socket =
      if user_id && e(assigns(socket), :__preloaded_blocks_for, nil) == user_id do
        socket
      else
        socket
        |> assign(
          Bonfire.Boundaries.Blocks.LiveHandler.preload_one(
            user,
            current_user(socket)
          )
          |> debug("any_block?")
        )
        |> assign(:__preloaded_blocks_for, user_id)
      end

    {:ok, socket}
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
