defmodule Bonfire.UI.Boundaries.EmbedCircleLive do
  @moduledoc """
  Embeddable grid of a public circle's members, e.g. for a website's team section. Loaded by `circle_embed.js`.
  """

  use Bonfire.UI.Common.Web,
      {:surface_live_view_child, layout: {Bonfire.UI.Common.LayoutView, :iframe}}

  alias Bonfire.Boundaries.Circles

  # only the default plugs, which copy the controller's session `"params"` into `current_params`: no current user is loaded since the circle is always read as a guest
  on_mount {LivePlugs, []}

  def mount(raw_params, _session, socket) do
    params = socket.assigns[:current_params] || (is_map(raw_params) && raw_params) || %{}

    # loaded as a guest even when someone is signed in, so a caretaker previewing the embed sees what the public sees
    with {:ok, circle} <- Circles.get(e(params, "id", nil), current_user: nil) do
      members =
        circle
        |> Circles.list_members(limit: 48)
        |> e(:edges, [])
        |> Enum.map(&e(&1, :subject, nil))

      {:ok,
       socket
       |> Bonfire.UI.Common.ThemeHelper.setup_embed(e(params, "theme", nil), true)
       |> assign(
         members: members,
         variant: variant(e(params, "variant", nil)),
         page_title: e(circle, :named, :name, nil) || l("Circle")
       )}
    end
  end

  @doc """
  The card layout from `?variant=`: `:portrait` for avatar tiles, otherwise the default `:quiet` cards.

      iex> Bonfire.UI.Boundaries.EmbedCircleLive.variant("portrait")
      :portrait

      iex> Bonfire.UI.Boundaries.EmbedCircleLive.variant("carousel")
      :quiet
  """
  def variant("portrait"), do: :portrait
  def variant(_), do: :quiet
end
