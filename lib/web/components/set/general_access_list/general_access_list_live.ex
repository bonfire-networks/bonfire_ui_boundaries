defmodule Bonfire.UI.Boundaries.GeneralAccessListLive do
  use Bonfire.UI.Common.Web, :stateless_component

  # unique DOM id for the select Dropdown; override when more than one is rendered on a page
  prop id, :string, default: "general_access_list"
  prop hide_presets, :boolean, default: false
  # which preset slugs to offer; defaults to the configured `:preset_order`
  prop presets, :list, default: nil
  prop boundary_preset, :any, default: nil
  prop set_action, :string, default: nil
  prop set_opts, :map, default: %{}
  prop my_acls, :any, default: []
  prop to_boundaries, :any, default: nil
  prop hide_custom, :boolean, default: false
  prop hide_private, :boolean, default: true
  prop is_customizable, :boolean, default: false
  prop scope, :any, default: :user

  def matches?(to_boundaries, boundary_preset, acl_id),
    do: matches?(to_boundaries, acl_id) or matches?(boundary_preset, acl_id)

  def matches?({preset, _}, preset), do: true
  def matches?([{preset, _}], preset), do: true
  def matches?(preset, preset), do: true

  def matches?(acls, preset) when is_list(acls) do
    Enum.any?(acls, fn
      %{id: id} -> id == preset
      {p, _} -> p == preset
      p -> p == preset
    end)
  end

  def matches?(_, _), do: false

  @doc """
  Resolve the currently-selected audience to a `{label, icon}` tuple, for the select trigger.
  Mirrors the option sections in the template, using `matches?/2,3` to find the active one.
  """
  def selected_option(boundary_preset, to_boundaries, my_acls, presets) do
    presets =
      presets ||
        Bonfire.Common.Config.get(
          :preset_order,
          ["public", "local", "mentions"],
          :bonfire_boundaries
        )

    cond do
      matches?(boundary_preset, "custom") ->
        {l("Custom"), "ri:settings-4-line"}

      matches?(boundary_preset, "private") ->
        preset = Bonfire.Boundaries.Presets.for_preset("private")
        {e(preset, :label, l("Private")), e(preset, :icon, "heroicons-solid:eye-off")}

      slug = Enum.find(presets, &matches?(boundary_preset, &1)) ->
        preset = Bonfire.Boundaries.Presets.for_preset(slug)
        {e(preset, :label, slug), e(preset, :icon, "ph:gear-six-duotone")}

      acl =
          Enum.find_value(my_acls || [], fn {acl_id, acl} ->
            if matches?(to_boundaries, boundary_preset, acl_id), do: acl
          end) ->
        {e(acl, :name, nil), e(acl, :icon, "fluent:door-tag-20-filled")}

      true ->
        {l("Select audience"), "ph:gear-six-duotone"}
    end
  end
end
