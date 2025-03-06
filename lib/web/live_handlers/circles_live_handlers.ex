defmodule Bonfire.Boundaries.Circles.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler
  alias Bonfire.Boundaries.{Circles, Blocks}

  def handle_event("multi_select", %{"data" => data, "text" => text}, socket) do
    debug(data, "multi_select_circle_live")
    add_member(input_to_atoms(data), socket)
  end

  def handle_event("multi_select", %{"id" => id, "name" => _name}, socket) do
    debug(id, "multi_select_circle_live")
    add_member(input_to_atoms(e(assigns(socket), :suggestions, %{})[id]) || id, socket)
  end

  def handle_event(
        "multi_select",
        %{"_target" => ["multi_select", module_name], "multi_select" => multi_select_data} =
          params,
        socket
      ) do
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "live_select_change",
        %{"field" => _field, "id" => live_select_id, "text" => search},
        socket
      ) do
    current_user = current_user(socket)

    results =
      Bonfire.Me.Users.search(search,
        current_user: current_user,
        paginate: false
      )
      |> do_results_for_multiselect()
      |> maybe_filter_current_user(socket)

    maybe_send_update(LiveSelect.Component, live_select_id, options: results)

    {:noreply, socket}
  end

  defp maybe_filter_current_user(results, %{assigns: %{circle_type: circle_type}} = socket)
       when circle_type in [:silence, :ghost] do
    current_user_id = current_user_id(socket)
    Enum.reject(results, fn {_name, id} -> id == current_user_id end)
  end

  defp maybe_filter_current_user(results, _), do: results

  defp do_results_for_multiselect({:ok, results}) do
    results
    |> Enum.map(fn user ->
      name = e(user, :profile, :name, nil) || e(user, :character, :username, nil)
      {name, uid(user)}
    end)
  end

  defp do_results_for_multiselect(_), do: []

  def add_member(subject, %{assigns: %{scope: scope, circle_type: circle_type}} = socket)
      when circle_type in [:silence, :ghost] do
    with id when is_binary(id) <- uid(subject),
         current_user_id when not is_nil(current_user_id) <- current_user_id(socket),
         false <- id == current_user_id,
         {:ok, _} <- Blocks.block(id, circle_type, scope || current_user(assigns(socket))) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Blocked!"))
       |> assign(
         members:
           Map.merge(
             %{id => subject},
             e(assigns(socket), :members, %{})
           )
           |> debug()
       )}
    else
      true ->
        {:noreply, assign_flash(socket, :error, l("Cannot block yourself."))}

      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not block"))}
    end
  end

  def add_member(subject, socket) do
    with id when is_binary(id) <- uid(subject),
         current_user_id when not is_nil(current_user_id) <- current_user_id(socket),
         false <- id == current_user_id,
         {:ok, _} <- Circles.add_to_circles(id, e(assigns(socket), :circle, nil)) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Added to circle!"))
       |> assign(
         members:
           Map.merge(
             %{id => subject},
             e(assigns(socket), :members, %{})
           )
       )}
    else
      true ->
        {:noreply, assign_flash(socket, :error, l("Cannot add yourself to the circle."))}

      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not add to circle"))}
    end
  end

  def handle_event("toggle_circles_nav_visibility", _params, socket) do
    debug("toggle_circles_nav_visibility")

    with {:ok, settings} <-
           Bonfire.Common.Settings.set(
             %{
               Bonfire.UI.Boundaries.MyCirclesLive => %{
                 show_circles_nav_open:
                   !Bonfire.Common.Settings.get(
                     [Bonfire.UI.Boundaries.MyCirclesLive, :show_circles_nav_open],
                     true,
                     socket
                   )
               }
             },
             current_user: current_user(socket)
           ) do
      {
        :noreply,
        socket |> maybe_assign_context(settings)
      }
    end
  end
end
