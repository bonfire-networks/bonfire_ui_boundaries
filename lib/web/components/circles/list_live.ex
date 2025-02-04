defmodule Bonfire.UI.Boundaries.ListLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias Bonfire.Boundaries.Circles

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(params, _session, socket) do
    with {:ok, data} <-
           load_circle(
             e(params, "id", nil),
             current_user: current_user(socket)
           ) do
      {:ok,
       socket
       |> assign(:page_title, e(data, :name, nil))
       |> assign(:nav_items, Bonfire.Common.ExtensionModule.default_nav())
       |> assign(:circle, e(data, :circle, nil))
       |> assign(:members, e(data, :members, []))
       |> assign(:loaded, true)}
    else
      _ ->
        {:ok,
         socket
         |> assign(:page_title, "Shared circle")
         |> assign(:nav_items, Bonfire.Common.ExtensionModule.default_nav())
         |> assign(:circle, nil)
         |> assign(:members, [])
         |> assign(:loaded, false)}
    end
  end

  def load_circle(id, opts) do
    with %{id: id} = circle <-
           Circles.get(id, opts)
           |> repo().maybe_preload(encircles: [subject: [:profile, :character]])
           |> repo().maybe_preload(encircles: [subject: [:named]])
           |> repo().maybe_preload(caretaker: [caretaker: [:profile, :character]])
           |> repo().maybe_preload(:extra_info)
           |> ok_unwrap() do
      creator_name =
        e(circle, :caretaker, :caretaker, :profile, :name, nil) ||
          e(circle, :caretaker, :caretaker, :character, :username, "Unknown")

      creator_username = e(circle, :caretaker, :caretaker, :character, :username, "Unknown")

      members =
        e(circle, :encircles, [])
        |> Enum.map(& &1.subject)
        |> debug("members")

      {:ok,
       %{
         circle:
           circle
           |> Map.drop([:encircles, :caretaker])
           |> Map.put(:creator_name, creator_name)
           |> Map.put(:creator_username, creator_username),
         members: members || [],
         name: e(circle, :named, :name, nil),
         loaded: true
       }}
    end
  end
end
