defmodule Bonfire.Boundaries.Blocks.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler
  # import Untangle
  # import Bonfire.UI.Common

  def handle_event("unblock", %{"id" => id} = _params, socket) do
    current_user = current_user_required!(assigns(socket))

    with {:ok, _} <-
           Bonfire.Boundaries.Blocks.unblock(id, :ghost, current_user: current_user),
         {:ok, _} <-
           Bonfire.Boundaries.Blocks.unblock(id, :silence, current_user: current_user) do
      Bonfire.UI.Common.OpenModalLive.close()
      refresh_block_status(id)

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [ghosted?: false, silenced?: false, skip_preload: true],
      #   socket
      # )

      {:noreply, assign_flash(socket, :info, l("You have successfully unblocked this user"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        error(error, "Error")
        {:noreply, assign_flash(socket, :error, l("Could not unblock"))}
    end
  end

  def handle_event("block", %{"id" => id} = params, socket) do
    current_user = current_user_required!(assigns(socket))

    # both halves, so blocking severs the follow in BOTH directions when asked: ghosting stops my posts reaching them, silencing stops theirs reaching me
    opts = [
      current_user: current_user,
      also_unfollow_and_notify: Types.maybe_to_boolean(params["also_unfollow_and_notify"])
    ]

    # one call for both, so one action leaves one `block` record (two calls left a `ghost` and a `silence` one)
    with {:ok, _} <- Bonfire.Boundaries.Blocks.block(id, :block, opts) do
      Bonfire.UI.Common.OpenModalLive.close()
      refresh_block_status(id)

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [ghosted?: true, silenced?: true, skip_preload: true],
      #   socket
      # )

      {:noreply, assign_flash(socket, :info, l("You have successfully blocked this user"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        error(error, "Error")
        {:noreply, assign_flash(socket, :error, l("Could not block"))}
    end
  end

  # Blocking someone on behalf of the group the object is in (its moderators only, which `Blocks.block/3` checks with `on_behalf_of:`), of the type the button was for, as for one's own blocks: a silence keeps them from taking part, a ghost from seeing it too, a block both
  def handle_event("block_scoped", %{"id" => id, "scope" => scoped_id} = params, socket) do
    type = scoped_block_type(params["type"])

    with {:ok, _} <-
           Bonfire.Boundaries.Blocks.block(id, type,
             current_user: current_user_required!(assigns(socket)),
             on_behalf_of: scoped_id,
             also_unfollow_and_notify: Types.maybe_to_boolean(params["also_unfollow_and_notify"]),
             # only offered for a group hosted elsewhere, and `nil` where it wasn't, for which `Moderations.apply_now?/1` reads config
             apply_now: Types.maybe_to_boolean(params["apply_now"])
           ) do
      Bonfire.UI.Common.OpenModalLive.close()
      refresh_block_status(id)

      {:noreply, assign_flash(socket, :info, l("Blocked from the group"))}
    else
      error ->
        error(error, "Could not block from the group")
        {:noreply, assign_flash(socket, :error, l("Could not block from the group"))}
    end
  end

  # Lifting the type of block the button was for, made on behalf of the group (a block: both, succeeding if either was there)
  def handle_event("unblock_scoped", %{"id" => id, "scope" => scoped_id} = params, socket) do
    with {:ok, _} <-
           Bonfire.Boundaries.Blocks.unblock(id, scoped_block_type(params["type"]),
             current_user: current_user_required!(assigns(socket)),
             on_behalf_of: scoped_id
           ) do
      Bonfire.UI.Common.OpenModalLive.close()
      refresh_block_status(id)

      {:noreply, assign_flash(socket, :info, l("Unblocked from the group"))}
    else
      error ->
        error(error, "Could not unblock from the group")
        {:noreply, assign_flash(socket, :error, l("Could not unblock from the group"))}
    end
  end

  def handle_event("block_instance_wide", %{"id" => id} = _params, socket) do
    with true <- Bonfire.Boundaries.can?(assigns(socket)[:__context__], :block, :instance_wide),
         # one call for both, naming the admin, so one `block` record says who made it
         {:ok, _} <-
           Bonfire.Boundaries.Blocks.block(id, :block,
             current_user: current_user(assigns(socket)),
             scope: :instance_wide
           ) do
      # Force-logout all sessions for the blocked user's account
      with %{account_id: account_id} <-
             Bonfire.Common.Repo.get_by(Bonfire.Data.Identity.Accounted, id: id) do
        Bonfire.Me.Users.LiveHandler.force_logout_account(account_id)
      end

      Bonfire.UI.Common.OpenModalLive.close()

      refresh_block_status(id)

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [ghosted_instance_wide?: true, silenced_instance_wide?: true, skip_preload: true],
      #   socket
      # )

      {:noreply,
       assign_flash(socket, :info, l("You have successfully blocked instance-wide this user"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        error(error, "Error")
        {:noreply, assign_flash(socket, :error, l("Could not block instance-wide"))}
    end
  end

  def handle_event("unblock_instance_wide", %{"id" => id} = _params, socket) do
    with true <- Bonfire.Boundaries.can?(assigns(socket)[:__context__], :block, :instance_wide),
         {:ok, _} <- Bonfire.Boundaries.Blocks.unblock(id, :ghost, :instance_wide),
         {:ok, _} <- Bonfire.Boundaries.Blocks.unblock(id, :silence, :instance_wide) do
      Bonfire.UI.Common.OpenModalLive.close()
      refresh_block_status(id)

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [ghosted_instance_wide?: false, silenced_instance_wide?: false, skip_preload: true],
      #   socket
      # )

      {:noreply,
       assign_flash(socket, :info, l("You have successfully unblocked instance-wide this user"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        error(error, "Error")
        {:noreply, assign_flash(socket, :error, l("Could not unblock instance-wide"))}
    end
  end

  def handle_event("unghost", %{"id" => id} = _params, socket) do
    with {:ok, _} <-
           Bonfire.Boundaries.Blocks.unblock(id, :ghost,
             current_user: current_user_required!(assigns(socket))
           ) do
      Bonfire.UI.Common.OpenModalLive.close()
      refresh_block_status(id)

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [ghosted?: false, skip_preload: true],
      #   socket
      # )

      {:noreply, assign_flash(socket, :info, l("You have successfully unghosted this user"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        error(error, "Error")
        {:noreply, assign_flash(socket, :error, l("Could not unghost"))}
    end
  end

  def handle_event("ghost", %{"id" => id} = params, socket) do
    with {:ok, _} <-
           Bonfire.Boundaries.Blocks.block(id, :ghost,
             current_user: current_user_required!(assigns(socket)),
             # an unticked checkbox sends nothing at all, which `maybe_to_boolean/1` reads as `nil`, and `Blocks.block/3` defaults it to false
             also_unfollow_and_notify: Types.maybe_to_boolean(params["also_unfollow_and_notify"])
           ) do
      Bonfire.UI.Common.OpenModalLive.close()
      refresh_block_status(id)

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [ghosted?: true, skip_preload: true],
      #   socket
      # )

      {:noreply, assign_flash(socket, :info, l("You have successfully ghosted this user"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        error(error, "Error")
        {:noreply, assign_flash(socket, :error, l("Could not ghost"))}
    end
  end

  def handle_event("ghost_instance_wide", %{"id" => id} = _params, socket) do
    with true <- Bonfire.Boundaries.can?(assigns(socket)[:__context__], :block, :instance_wide),
         {:ok, _} <-
           Bonfire.Boundaries.Blocks.block(id, :ghost,
             current_user: current_user(assigns(socket)),
             scope: :instance_wide
           ) do
      Bonfire.UI.Common.OpenModalLive.close()
      refresh_block_status(id)

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [ghosted_instance_wide?: true, skip_preload: true],
      #   socket
      # )

      {:noreply,
       assign_flash(socket, :info, l("You have successfully ghosted instance-wide this user"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        error(error, "Error")
        {:noreply, assign_flash(socket, :error, l("Could not ghost instance-wide"))}
    end
  end

  def handle_event("unghost_instance_wide", %{"id" => id} = _params, socket) do
    with true <- Bonfire.Boundaries.can?(assigns(socket)[:__context__], :block, :instance_wide),
         {:ok, _} <- Bonfire.Boundaries.Blocks.unblock(id, :ghost, :instance_wide) do
      Bonfire.UI.Common.OpenModalLive.close()
      refresh_block_status(id)

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [ghosted_instance_wide?: false, skip_preload: true],
      #   socket
      # )

      {:noreply,
       assign_flash(socket, :info, l("You have successfully unghosted instance-wide this user"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        error(error, "Error")
        {:noreply, assign_flash(socket, :error, l("Could not unghost instance-wide"))}
    end
  end

  def handle_event("silence", %{"id" => id} = params, socket) do
    with {:ok, _} <-
           Bonfire.Boundaries.Blocks.block(id, :silence,
             current_user: current_user_required!(assigns(socket)),
             # an unticked checkbox sends nothing at all, which `maybe_to_boolean/1` reads as `nil`, and `Blocks.block/3` defaults it to false
             also_unfollow_and_notify: Types.maybe_to_boolean(params["also_unfollow_and_notify"])
           ) do
      Bonfire.UI.Common.OpenModalLive.close()
      refresh_block_status(id)

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [silenced?: true, skip_preload: true],
      #   socket
      # )

      {:noreply, assign_flash(socket, :info, l("You have successfully silenced this user"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        {:noreply, assign_flash(socket, :error, l("Could not silence"))}
    end
  end

  def handle_event("unsilence", %{"id" => id} = _params, socket) do
    with {:ok, _} <-
           Bonfire.Boundaries.Blocks.unblock(id, :silence,
             current_user: current_user_required!(assigns(socket))
           ) do
      Bonfire.UI.Common.OpenModalLive.close()
      refresh_block_status(id)

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [silenced?: false, skip_preload: true],
      #   socket
      # )

      {:noreply, assign_flash(socket, :info, l("You have successfully unsilenced this user"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        {:noreply, assign_flash(socket, :error, l("Could not unsilence"))}
    end
  end

  def handle_event("silence_instance_wide", %{"id" => id} = _params, socket) do
    with true <- Bonfire.Boundaries.can?(assigns(socket)[:__context__], :block, :instance_wide),
         {:ok, _} <-
           Bonfire.Boundaries.Blocks.block(id, :silence,
             current_user: current_user(assigns(socket)),
             scope: :instance_wide
           ) do
      Bonfire.UI.Common.OpenModalLive.close()
      refresh_block_status(id)

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [silenced_instance_wide?: true, skip_preload: true],
      #   socket
      # )

      {:noreply,
       assign_flash(socket, :info, l("You have successfully silenced instance-wide this user"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        {:noreply, assign_flash(socket, :error, l("Could not silence instance-wide"))}
    end
  end

  def handle_event("unsilence_instance_wide", %{"id" => id} = _params, socket) do
    with true <- Bonfire.Boundaries.can?(assigns(socket)[:__context__], :block, :instance_wide),
         {:ok, _} <- Bonfire.Boundaries.Blocks.unblock(id, :silence, :instance_wide) do
      Bonfire.UI.Common.OpenModalLive.close()
      refresh_block_status(id)

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [silenced_instance_wide?: false, skip_preload: true],
      #   socket
      # )

      {:noreply,
       assign_flash(socket, :info, l("You have successfully unsilenced instance-wide this user"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        {:noreply, assign_flash(socket, :error, l("Could not unsilence instance-wide"))}
    end
  end

  def handle_event("hide", %{"id" => id} = _params, socket) do
    with {:ok, _} <-
           Bonfire.Boundaries.Blocks.block(id, :hide,
             current_user: current_user_required!(assigns(socket))
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [silenced?: true, skip_preload: true],
      #   socket
      # )

      {:noreply, assign_flash(socket, :info, l("You have successfully hidden this"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        {:noreply, assign_flash(socket, :error, l("Could not hide"))}
    end
  end

  def handle_event("unhide", %{"id" => id} = _params, socket) do
    with {:ok, _} <-
           Bonfire.Boundaries.Blocks.unblock(id, :hide,
             current_user: current_user_required!(assigns(socket))
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [silenced?: true, skip_preload: true],
      #   socket
      # )

      {:noreply, assign_flash(socket, :info, l("You have successfully unhidden this"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        {:noreply, assign_flash(socket, :error, l("Could not unhide"))}
    end
  end

  def handle_event("hide_instance_wide", %{"id" => id} = _params, socket) do
    with true <- Bonfire.Boundaries.can?(assigns(socket)[:__context__], :block, :instance_wide),
         {:ok, _} <-
           Bonfire.Boundaries.Blocks.block(id, :hide,
             current_user: current_user(assigns(socket)),
             scope: :instance_wide
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [silenced_instance_wide?: true, skip_preload: true],
      #   socket
      # )

      {:noreply,
       assign_flash(socket, :info, l("You have successfully hidden this instance-wide"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        {:noreply, assign_flash(socket, :error, l("Could not hide this instance-wide"))}
    end
  end

  def handle_event("unhide_instance_wide", %{"id" => id} = _params, socket) do
    with true <- Bonfire.Boundaries.can?(assigns(socket)[:__context__], :block, :instance_wide),
         {:ok, _} <- Bonfire.Boundaries.Blocks.unblock(id, :hide, :instance_wide) do
      Bonfire.UI.Common.OpenModalLive.close()

      # ComponentID.send_assigns(
      #   Bonfire.UI.Common.BlockButtonLive,
      #   id,
      #   [silenced_instance_wide?: false, skip_preload: true],
      #   socket
      # )

      {:noreply,
       assign_flash(socket, :info, l("You have successfully unhidden this instance-wide"))}
    else
      # This block will be executed if either of the unblock operations fails
      # You can handle errors here
      error ->
        {:noreply, assign_flash(socket, :error, l("Could not unhide this instance-wide"))}
    end
  end

  # the event may land in a component socket (eg. the modal), so ask the view process to re-check, see `handle_info/2`
  # the type a group block button was for; a block (or none) is both halves
  defp scoped_block_type("silence"), do: :silence
  defp scoped_block_type("ghost"), do: :ghost
  defp scoped_block_type(_), do: nil

  defp refresh_block_status(id) do
    send(self(), {{Bonfire.Boundaries.Blocks, :block_status_changed}, id})
  end

  # only refresh when the view is the profile of the (un)blocked user, so blocking someone from a feed doesn't flag the profile being viewed
  def handle_info({:block_status_changed, id}, socket) do
    user = e(assigns(socket), :user, nil)

    if id && uid(user) == id do
      block_status = preload_one(user, current_user(socket))

      # the stateful hero used on character pages caches its own block status
      if socket.view == Bonfire.UI.Me.CharacterLive,
        do:
          maybe_send_update(Bonfire.UI.Me.ProfileHeroFullLive, "profile_character", block_status)

      {:noreply, assign(socket, block_status)}
    else
      {:noreply, socket}
    end
  end

  # def update_many(assigns_sockets, opts \\ []) do
  #   update_many_async(assigns_sockets, update_many_opts(opts))
  # end

  # def update_many_opts(opts \\ []) do
  #   opts ++
  #     [
  #       assigns_to_params_fn: &assigns_to_params/1,
  #       preload_fn: &do_preload/3
  #     ]
  # end

  # defp assigns_to_params(assigns) do
  #   object = e(assigns, :object, nil)

  #   %{
  #     component_id: assigns.id,
  #     object: object,
  #     object_id: e(assigns, :object_id, nil) || uid(object)
  #   }
  # end

  # defp do_preload(list_of_components, list_of_ids, current_user) do
  # FIXME: this shouldn't be doing List.first()
  #   # Here we're checking if the user is ghosted / silenced by user or instance
  #   ghosted? =
  #     Bonfire.Boundaries.Blocks.is_blocked?(List.first(list_of_ids), :ghost,
  #       current_user: current_user
  #     )

  #   ghosted_instance_wide? =
  #     Bonfire.Boundaries.Blocks.is_blocked?(List.first(list_of_ids), :ghost, :instance_wide)

  #   silenced? =
  #     Bonfire.Boundaries.Blocks.is_blocked?(List.first(list_of_ids), :silence,
  #       current_user: current_user
  #     )

  #   silenced_instance_wide? =
  #     Bonfire.Boundaries.Blocks.is_blocked?(List.first(list_of_ids), :silence, :instance_wide)

  #   list_of_components
  #   |> Map.new(fn component ->
  #     {component.component_id,
  #      %{
  #        ghosted?: ghosted?,
  #        ghosted_instance_wide?: ghosted_instance_wide?,
  #        silenced?: silenced?,
  #        silenced_instance_wide?: silenced_instance_wide?
  #      }}
  #   end)

  # end

  def preload_one(object, opts) do
    current_user = current_user(opts)

    # Here we're checking if the user is ghosted / silenced by user or instance
    ghosted? =
      Bonfire.Boundaries.Blocks.is_blocked?(object, :ghost, current_user: current_user)

    ghosted_instance_wide? =
      Bonfire.Boundaries.Blocks.is_blocked?(object, :ghost, :instance_wide)

    silenced? =
      Bonfire.Boundaries.Blocks.is_blocked?(object, :silence, current_user: current_user)

    silenced_instance_wide? =
      Bonfire.Boundaries.Blocks.is_blocked?(object, :silence, :instance_wide)

    [
      ghosted?: ghosted?,
      ghosted_instance_wide?: ghosted_instance_wide?,
      silenced?: silenced?,
      silenced_instance_wide?: silenced_instance_wide?
    ]
    |> debug()
  end
end
