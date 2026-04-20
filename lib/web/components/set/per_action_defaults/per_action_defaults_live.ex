defmodule Bonfire.UI.Boundaries.PerActionDefaultsLive do
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Utils

  prop state, :map, required: true
  prop parent_id, :string, default: "customize_boundary_live"
  prop read_only, :boolean, default: false

  @actions [
    %{key: "read", verbs: ["read", "see"], icon: "ph:eye-duotone"},
    %{key: "reply", verbs: ["reply"], icon: "ph:chat-circle-duotone"},
    %{key: "quote", verbs: ["quote"], icon: "ph:quotes-duotone"}
  ]

  def actions, do: @actions

  @doc """
  Builds the full render-ready per-action state in one pass so the template
  can do pure map lookups.
  """
  def build_states(verb_permissions, preset_boundary, my_circles) do
    circles = exception_circles(my_circles)
    locked? = preset_locks_action?(preset_boundary)

    action_states =
      Enum.map(@actions, fn action ->
        allowed? = action_allowed?(verb_permissions, preset_boundary, action)

        exception_checks =
          Map.new(circles, fn circle ->
            {uid(circle),
             action_exception_checked?(verb_permissions, preset_boundary, action, circle)}
          end)

        %{
          key: action.key,
          verbs: action.verbs,
          icon: action.icon,
          label: action_label(action.key),
          allowed?: allowed?,
          locked?: locked?,
          show_exceptions?:
            not allowed? and not locked? and circles != [] and
              (user_overrode_any_verb?(verb_permissions, action.verbs) or
                 Enum.any?(exception_checks, fn {_cid, checked?} -> checked? end)),
          exception_checks: exception_checks
        }
      end)

    %{action_states: action_states, exception_circles: circles, locked?: locked?}
  end

  def verbs_for(action_key) do
    case Enum.find(@actions, fn a -> a.key == action_key end) do
      %{verbs: verbs} -> verbs
      _ -> []
    end
  end

  def action_label("read"), do: l("Allow reading?")
  def action_label("reply"), do: l("Allow replies?")
  def action_label("quote"), do: l("Allow quote posts?")

  @doc """
  True when the action is allowed for the public audience. Explicit overrides
  in `verb_permissions` win. Otherwise data-driven: an action defaults ON only
  if the preset actually grants one of its verbs to some circle (keeps "Allow
  quote" honest under `public` — no standard preset grants `:quote`, so we
  don't pretend it's on). Falls back to legacy "ON unless explicitly OFF" for
  custom ACLs and unknown slugs, where we can't introspect the preset grants.
  """
  def action_allowed?(verb_permissions, preset_boundary, %{verbs: verbs}) do
    anyone_id = anyone_circle_id()

    case verbs_override_on_anyone(verb_permissions, verbs, anyone_id) do
      :can -> true
      :cannot -> false
      :none -> preset_action_default?(preset_boundary, verbs)
    end
  end

  @doc """
  True when the preset grants `:can` for at least one of the given verbs to
  some circle. Used to decide whether toggling an action ON should clear user
  overrides (preset already enables it) or write explicit `:can` grants for
  the audience (preset doesn't enable it — clearing alone wouldn't turn it on).
  """
  def preset_grants_any?(preset_boundary, verbs) do
    case preset_slug(preset_boundary) do
      slug when is_binary(slug) ->
        Enum.any?(verbs, fn verb ->
          Bonfire.UI.Boundaries.SetBoundariesLive.get_preset_verb_permissions(
            slug,
            maybe_to_atom(verb)
          )
          |> Enum.any?(fn {_cid, val} -> val == :can end)
        end)

      _ ->
        false
    end
  end

  @doc """
  True when the toggle for this action should be non-interactive under the
  current preset (because the preset's semantics lock the answer — e.g.
  "Mentions" / "Private" have no broader audience to grant to).
  """
  def preset_locks_action?(preset_boundary) do
    preset_slug(preset_boundary) in ["mentions", "private"]
  end

  @doc """
  Circles eligible to be listed as per-action exceptions: everything the user
  has access to, minus the "anyone/public" circle (the target being restricted)
  and a handful of infrastructure circles that don't make sense as per-post
  exceptions (moderators, suggested profiles, federation, block stereotypes).
  """
  def exception_circles(my_circles) do
    exclude = exclude_circle_ids()
    Enum.reject(my_circles || [], fn c -> uid(c) in exclude end)
  end

  @doc """
  True if the circle should render as "checked" under the action's Except list.
  Checked when the circle has `:can` grants in `verb_permissions` OR when the
  current preset's implicit defaults grant the action to that circle.
  """
  def action_exception_checked?(
        verb_permissions,
        preset_boundary,
        %{verbs: verbs} = action,
        circle
      ) do
    case uid(circle) do
      nil ->
        false

      circle_id ->
        Enum.all?(verbs, fn v -> verb_for(verb_permissions, v, circle_id) == :can end) or
          circle_matches_preset_default?(circle, preset_boundary, action)
    end
  end

  def anyone_circle_id, do: Bonfire.Boundaries.Circles.get_id(:guest)

  @doc """
  Circle IDs the preset grants `:can` for any of the given verbs — i.e. the
  circles that also need `:cannot` overrides when the user toggles the action
  OFF, otherwise the preset's implicit grants to other audiences (e.g. local
  users and the fediverse on a "public" post) keep the action allowed.

  Always includes the guest/anyone circle so toggling OFF at least blocks
  strangers even on custom or unknown presets.
  """
  def preset_block_circle_ids(preset_boundary, verbs) do
    [anyone_circle_id() | preset_granted_circle_ids(preset_boundary, verbs)]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc """
  The "general audience" of the preset — circles the preset grants `:read`/`:see`
  to. Used as the set of targets for toggling an action ON that the preset
  doesn't implicitly grant to anyone (e.g. quote under `public` writes `:can`
  for guest/local/activity_pub, matching who is already reading the activity).
  Empty for custom ACLs and presets without a discoverable audience (mentions,
  follows, private) — callers should handle the empty case.
  """
  def preset_audience_circle_ids(preset_boundary) do
    preset_granted_circle_ids(preset_boundary, ["read", "see"])
  end

  @doc """
  Display name for a circle — prefers its stereotype's localised label
  (so built-ins like `followers`/`local` render as "Your followers" / "Local users"),
  then falls back to the user-provided name.
  """
  def circle_name(circle) do
    stereo_name = e(circle, :stereotyped, :named, :name, nil)

    if is_binary(stereo_name) and stereo_name != "" do
      localise_dynamic(stereo_name, __MODULE__)
    else
      e(circle, :named, :name, nil) || e(circle, :name, nil) || l("Untitled circle")
    end
  end

  # True when `verb_permissions` (the sparse-override map) has any entry for
  # any of the given verbs — i.e. the user has actively shaped permissions for
  # this action, so the exceptions picker is relevant. Default-OFF actions with
  # an empty override map stay collapsed to avoid cluttering the UI.
  defp user_overrode_any_verb?(verb_permissions, verbs) do
    Enum.any?(verbs, fn v ->
      case Map.get(verb_permissions || %{}, v) do
        m when is_map(m) and map_size(m) > 0 -> true
        _ -> false
      end
    end)
  end

  defp verbs_override_on_anyone(verb_permissions, verbs, anyone_id) do
    verbs
    |> Enum.map(fn v -> verb_for(verb_permissions, v, anyone_id) end)
    |> Enum.reduce(:none, fn
      :cannot, _ -> :cannot
      :can, :none -> :can
      _, acc -> acc
    end)
  end

  defp preset_granted_circle_ids(preset_boundary, verbs) do
    case preset_slug(preset_boundary) do
      slug when is_binary(slug) ->
        Enum.flat_map(verbs, fn verb ->
          Bonfire.UI.Boundaries.SetBoundariesLive.get_preset_verb_permissions(
            slug,
            maybe_to_atom(verb)
          )
          |> Enum.filter(fn {_cid, val} -> val == :can end)
          |> Enum.map(fn {cid, _} -> cid end)
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      _ ->
        []
    end
  end

  defp preset_action_default?(preset_boundary, verbs) do
    slug = preset_slug(preset_boundary)

    cond do
      # Explicitly OFF presets don't grant to the anyone/public audience.
      not preset_default_allowed?(slug) -> false
      # Nil / unknown slug = custom ACL — no data to introspect, legacy ON.
      is_nil(slug) or not preset_in_acls_map?(slug) -> true
      # Known preset that's "ON by default" — only honest if it actually grants.
      true -> preset_grants_any?(preset_boundary, verbs)
    end
  end

  # "OFF-by-default" presets: mentions/follows/private have no broader audience
  # to grant the action to; "custom — start from scratch" starts empty.
  # Unknown slugs fall through to true so user-created custom ACLs keep the
  # legacy ON default (we can't introspect their grants via preset_acls).
  defp preset_default_allowed?("mentions"), do: false
  defp preset_default_allowed?("follows"), do: false
  defp preset_default_allowed?("private"), do: false
  defp preset_default_allowed?("custom"), do: false
  defp preset_default_allowed?(_), do: true

  defp preset_in_acls_map?(slug) when is_binary(slug) do
    Map.has_key?(Bonfire.Common.Config.get!(:preset_acls), slug)
  end

  defp preset_in_acls_map?(_), do: false

  defp circle_matches_preset_default?(circle, preset_boundary, _action) do
    case preset_default_stereotypes(preset_slug(preset_boundary)) do
      [] ->
        false

      stereotypes ->
        stereotype_id = e(circle, :stereotyped, :stereotype_id, nil)
        is_binary(stereotype_id) and stereotype_id in stereotype_ids(stereotypes)
    end
  end

  defp preset_default_stereotypes("follows"), do: [:followed]
  defp preset_default_stereotypes(_), do: []

  defp preset_slug({slug, _}) when is_binary(slug), do: slug
  defp preset_slug([{slug, _} | _]) when is_binary(slug), do: slug
  defp preset_slug(slug) when is_binary(slug), do: slug
  defp preset_slug(_), do: nil

  defp stereotype_ids(atoms) when is_list(atoms) do
    atoms
    |> Enum.map(&Bonfire.Boundaries.Circles.get_id/1)
    |> Enum.reject(&is_nil/1)
  end

  defp verb_for(verb_permissions, verb, circle_id) do
    verb_permissions
    |> Kernel.||(%{})
    |> Map.get(verb, %{})
    |> Map.get(circle_id)
  end

  # Exclude guest (the audience being restricted), the infrastructure circles
  # that don't make sense as per-post exceptions (admins/mods/suggested), and
  # the invisible block stereotypes. Keep `local` and `activity_pub` in — users
  # explicitly want to allow/disallow locals or the fediverse for an action.
  defp exclude_circle_ids do
    alias Bonfire.Boundaries.Scaffold.Instance

    [
      anyone_circle_id(),
      Instance.admin_circle(),
      Instance.mod_circle(),
      Instance.suggested_profiles_circle()
    ] ++ Bonfire.Boundaries.Circles.stereotypes(:block)
  end
end
