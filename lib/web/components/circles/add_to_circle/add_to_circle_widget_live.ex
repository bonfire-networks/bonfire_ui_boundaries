defmodule Bonfire.UI.Boundaries.AddToCircleWidgetLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.LiveHandler

  prop circles, :list, default: []
  prop user_id, :any, default: nil
  prop name, :any, default: nil

  def update(%{circles: circles_passed_down} = assigns, socket) when circles_passed_down != [] do
    debug("use circles passed down by parent component")
    # current_user = current_user(assigns) || current_user(socket)

    circles_passed_down =
      Circles.list_subject_in_circles(e(assigns, :user_id, nil), circles_passed_down)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(circles: circles_passed_down)}
  end

  def update(assigns, %{assigns: %{circles: circles_already_loaded}} = socket)
      when circles_already_loaded != [] do
    debug("use circles already loaded (but load membership)")
    # current_user = current_user(assigns) || current_user(socket)

    circles_already_loaded =
      Circles.list_subject_in_circles(e(assigns, :user_id, nil), circles_already_loaded)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(circles: circles_already_loaded)}
  end

  def update(assigns, socket) do
    debug("load circles")
    context = assigns[:__context__] || assigns(socket)[:__context__]
    current_user = current_user(context)

    %{page_info: page_info, edges: circles} =
      Bonfire.Boundaries.Circles.LiveHandler.my_circles_paginated(current_user)

    circles =
      Circles.list_subject_in_circles(e(assigns, :user_id, nil), circles)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(page_info: page_info)
     |> assign(circles: circles)}
  end

  def handle_event("circle_create_from_modal", %{"name" => name} = attrs, socket) do
    circle_create_from_modal(Map.merge(attrs, %{named: %{name: name}}), socket)
  end

  def handle_event("circle_create_from_modal", attrs, socket) do
    circle_create_from_modal(attrs, socket)
  end

  def handle_event("add", %{"id" => user_id, "circle" => circle}, socket) do
    # TODO: check permission
    # current_user = current_user(socket)
    with {:ok, _} <- Circles.add_to_circles(user_id, circle) do
      {:noreply,
       socket
       |> update(
         :circles,
         &Circles.list_subject_in_circles(user_id, &1,
           reload_circle_id: Enums.id(circle),
           inc_reload_count: 1
         )
       )
       |> assign_flash(:info, l("Added to circle!"))}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not add to circle"))}
    end
  end

  def handle_event("remove", %{"id" => user_id, "circle" => circle}, socket) do
    # TODO: check permission
    # current_user = current_user(socket)
    with {1, _} <- Circles.remove_from_circles(user_id, circle) do
      {:noreply,
       socket
       |> update(
         :circles,
         &Circles.list_subject_in_circles(user_id, &1,
           reload_circle_id: Enums.id(circle),
           inc_reload_count: -1
         )
       )
       |> assign_flash(:info, l("removed from circle!"))}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not remove to circle"))}
    end
  end

  def circle_create_from_modal(attrs, socket) do
    current_user = current_user_required!(socket)

    with {:ok, %{id: _id} = circle} <-
           Circles.create(
             e(assigns(socket), :scope, nil) || current_user,
             attrs
           ) do
      # Bonfire.UI.Common.OpenModalLive.close()
      # JS.toggle(to: "#new_circle_from_modal")
      # JS.toggle(to: "#circles_list")
      {:noreply,
       socket
       |> update(:circles, &[circle | &1])
       |> assign_flash(:info, "Circle created!")}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, "Could not create circle")}
    end
  end
end
