defmodule Bonfire.UI.Boundaries.BlocksLive do
  use Bonfire.UI.Common.Web, :stateful_component
  # alias Bonfire.Boundaries.Integration

  prop selected_tab, :any
  prop name, :string, default: nil
  prop title, :string, default: nil
  prop description, :string, default: nil
  prop blocks, :list, default: []
  prop page_info, :any
  prop scope, :any, default: nil

  def update(assigns, socket) do
    context = assigns[:__context__] || assigns(socket)[:__context__]
    current_user = current_user(context)
    tab = e(assigns, :selected_tab, nil)

    scope = e(assigns, :scope, nil)
    # |> debug("scope")

    read_only =
      (scope == :instance_wide and
         Bonfire.Boundaries.can?(context, :block, :instance) != true)
      |> debug("read_only?")

    block_type = if tab == "ghosted", do: :ghost, else: :silence

    circle =
      if scope == :instance_wide do
        Bonfire.Boundaries.Blocks.instance_wide_circles(block_type)
      else
        Bonfire.Boundaries.Blocks.user_block_circles(scope || current_user, block_type)
      end
      |> List.first()

    # |> debug("ccircle")

    # circle = Bonfire.Boundaries.Blocks.list(block_type, scope || current_user)

    # blocks = e(circle, :encircles, [])

    # |> debug

    # blocks = for block <- blocks, do: %{activity:
    #   block
    #   |> Map.put(:verb, %{verb: block_type})
    #   |> Map.put(:object, e(block, :subject, nil))
    #   |> Map.put(:subject, e(block, :caretaker, nil))
    # } #|> debug

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       # user or instance-wide?
       scope: scope,
       page: tab,
       selected_tab: tab,
       read_only: read_only,
       block_type: block_type,
       # Keep title so it can be passed to child components
       title: e(assigns, :title, nil),
       #  current_user: current_user,
       circle: if(is_map(circle), do: circle),
       circle_id: id(circle)
       #  circle: circle
       #  blocks: blocks

       # page_info: e(q, :page_info, [])
     )}
  end
end
