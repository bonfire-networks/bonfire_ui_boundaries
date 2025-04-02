defmodule Bonfire.Boundaries.Locking.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler
  # import Untangle
  # import Bonfire.UI.Common

  def handle_event("lock", %{"id" => id} = _params, socket) do
    with {:ok, _} <-
           Bonfire.Boundaries.Blocks.block(id, :lock,
             current_user: current_user_required!(assigns(socket))
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [silenced?: true, skip_preload: true],
      #   socket
      # )

      {:noreply, assign_flash(socket, :info, l("You have locked this discussion"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        {:noreply, assign_flash(socket, :error, l("Could not lock"))}
    end
  end

  def handle_event("unlock", %{"id" => id} = _params, socket) do
    with {:ok, _} <-
           Bonfire.Boundaries.Blocks.unblock(id, :lock,
             current_user: current_user_required!(assigns(socket))
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [silenced?: true, skip_preload: true],
      #   socket
      # )

      {:noreply, assign_flash(socket, :info, l("You have successfully unlocked this discussion"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        {:noreply, assign_flash(socket, :error, l("Could not unlock"))}
    end
  end
end
