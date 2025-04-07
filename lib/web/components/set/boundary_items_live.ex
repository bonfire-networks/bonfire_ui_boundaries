defmodule Bonfire.UI.Boundaries.BoundaryItemsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop to_boundaries, :any, default: nil
  prop circles, :any, default: []
  prop roles_for_dropdown, :any, default: nil
  prop field, :atom, default: :to_circles
  prop read_only, :boolean, default: false
  prop my_circles, :any, default: []
  slot default, required: false

  def acls_from_role(role) do
    {:ok, permissions, []} = Bonfire.Boundaries.Roles.verbs_for_role(maybe_to_atom(role), %{})
    permissions
  end

  def name(data, my_circles) when is_binary(data) and is_list(my_circles) do
    debug(data, "Circle ID")

    # First try to find the circle in the provided my_circles list
    case Enum.find(my_circles, fn circle -> e(circle, :id, "") == data end) do
      nil ->
        # If not found in my_circles, try built-in circles
        circle = Bonfire.Boundaries.Circles.get_tuple(data)
        debug(circle, "built-in circle check")

        case circle do
          {name, _id} when is_binary(name) ->
            name

          {slug, %{name: name}} when is_atom(slug) and is_binary(name) ->
            name

          # Check for special stereotypes
          _ ->
            if Bonfire.Boundaries.Circles.is_stereotype?(data) do
              circle_map =
                Enum.find(Bonfire.Boundaries.Circles.circles() |> Map.values(), fn c ->
                  c.id == data
                end)

              debug(circle_map, "stereotype circle map")
              e(circle_map, :name, data)
            else
              # Handle invalid IDs (like those prefixed with "_unused_")
              if String.starts_with?(data, "_unused_") do
                # Just return the ID without the prefix for display purposes
                String.replace(data, "_unused_", "")
              else
                # If all else fails, fetch directly as a last resort
                # Use a safe try-rescue block to catch any ID validation errors
                try do
                  with {:ok, circle} <-
                         Bonfire.Boundaries.Circles.get(data,
                           exclude_stereotypes: false,
                           exclude_block_stereotypes: false,
                           exclude_built_ins: false
                         ) do
                    name =
                      e(circle, :named, :name, nil) ||
                        e(circle, :stereotyped, :named, :name, nil) ||
                        e(circle, :stereotype_named, :name, nil)

                    name || data
                  else
                    _ -> data
                  end
                rescue
                  _ -> data
                end
              end
            end
        end

      circle ->
        # Found in my_circles, extract the name
        name =
          e(circle, :name, nil) || e(circle, "name", nil) ||
            e(circle, :profile, :name, nil) ||
            e(circle, :named, :name, nil) ||
            e(circle, :stereotyped, :named, :name, nil)

        debug(name, "circle name from my_circles")
        name || data
    end
  end

  # Fallback when my_circles is not provided
  def name(data, _my_circles) when is_binary(data), do: name(data)

  # Handle original functionality when no my_circles are passed
  def name(data) when is_binary(data) do
    debug(data, "Circle ID (no my_circles)")

    # Handle invalid IDs with _unused_ prefix before attempting to query
    if String.starts_with?(data, "_unused_") do
      # Just return the ID without the prefix for display purposes
      String.replace(data, "_unused_", "")
    else
      # Try to get the circle directly - ensuring we include all circle types
      with {:ok, circle} <-
             Bonfire.Boundaries.Circles.get(data,
               exclude_stereotypes: false,
               exclude_block_stereotypes: false,
               exclude_built_ins: false
             ) do
        debug(circle, "circle fetched")

        # Get name from multiple possible sources
        name =
          e(circle, :named, :name, nil) ||
            e(circle, :stereotyped, :named, :name, nil) ||
            e(circle, :stereotype_named, :name, nil)

        debug(name, "circle name")
        name || data
      else
        _ ->
          # Try to get a built-in circle by ID (for system circles)
          circle = Bonfire.Boundaries.Circles.get_tuple(data)
          debug(circle, "built-in circle check")

          case circle do
            {name, _id} when is_binary(name) ->
              name

            {slug, %{name: name}} when is_atom(slug) and is_binary(name) ->
              name

            # Check for special stereotypes (based on the constants in circles.ex)
            _ ->
              if Bonfire.Boundaries.Circles.is_stereotype?(data) do
                circle_map =
                  Enum.find(Bonfire.Boundaries.Circles.circles() |> Map.values(), fn c ->
                    c.id == data
                  end)

                debug(circle_map, "stereotype circle map")
                e(circle_map, :name, data)
              else
                data
              end
          end
      end
    end
  end

  def name(data) when is_tuple(data), do: elem(data, 1)

  def name(data) when is_map(data) do
    e(data, :name, nil) || e(data, "name", nil) || e(data, :profile, :name, nil) ||
      e(data, :named, :name, nil) ||
      e(data, :stereotyped, :named, :name, nil)
  end

  def name(data) do
    warn(data, "Dunno how to display")
    nil
  end
end
