defmodule Bonfire.UI.Boundaries.VerbPermissionsHelper do
  @moduledoc """
  Helper functions for managing verb-level permissions in boundary UI components.
  """

  use Bonfire.Common.Utils

  @doc """
  Transforms the internal verb permissions format to direct verb grants, bypassing the role system.

  Takes a map like:
  %{"like" => %{"circle_id_1" => :can, "circle_id_2" => :cannot}, "boost" => %{"circle_id_1" => :can}}

  Returns:
  {to_circles, verb_grants}

  to_circles contains just the circles without roles: [{circle, nil}]
  verb_grants contains direct verb permissions: [{circle_id, verb, value}]

  Example output:
  {[{%{id: "circle_1"}, nil}, {%{id: "circle_2"}, nil}], [{"circle_1", :like, true}, {"circle_1", :boost, true}, {"circle_2", :like, false}, {"circle_2", :boost, false}]}
  """
  def transform_to_verb_grants_format(verb_permissions) do
    # Collect all unique circles
    all_circles =
      verb_permissions
      |> Enum.flat_map(fn {_verb, circle_perms} -> Map.keys(circle_perms) end)
      |> Enum.uniq()

    # Create to_circles without roles (just circles)
    to_circles =
      all_circles
      |> Enum.map(fn circle_id -> {%{id: circle_id}, nil} end)

    # Create verb_grants for direct processing
    verb_grants =
      verb_permissions
      |> Enum.flat_map(fn {verb, circle_perms} ->
        verb_atom = maybe_to_atom(verb)

        Enum.flat_map(circle_perms, fn {circle_id, permission} ->
          value =
            case permission do
              :can -> true
              "can" -> true
              :cannot -> false
              "cannot" -> false
              # nil -> nil
              _ -> nil
            end

          # Only include non-nil values in verb_grants
          if value != nil do
            [{circle_id, verb_atom, value}]
          else
            []
          end
        end)
      end)

    {to_circles, verb_grants}
  end

  @doc """
  Updates a single verb permission for a specific circle.
  """
  def update_verb_permission(current_permissions, circle_id, verb, verb_value) do
    current_permissions
    |> Map.put(verb, Map.put(Map.get(current_permissions, verb, %{}), circle_id, verb_value))
  end

  @doc """
  Transforms ACL subject verb grants to verb permissions format for display.

  Takes ACL grants structure:
  %{subject_id => %{subject: subject, grants: %{verb_id => grant}}}

  Returns:
  {verb_permissions, to_circles}
  """
  def transform_acl_to_verb_format(acl_subject_verb_grants) do
    debug(acl_subject_verb_grants, "Input to transform_acl_to_verb_format")

    # Transform grants to verb permissions
    verb_permissions =
      Enum.reduce(acl_subject_verb_grants, %{}, fn {subject_id, %{grants: grants}}, acc ->
        debug({subject_id, Map.keys(grants || %{})}, "Processing subject grants")

        Enum.reduce(grants || %{}, acc, fn {verb_id, grant}, verb_acc ->
          # Get the actual verb name from the verb struct
          raw_verb_name = e(grant, :verb, :verb, nil)
          debug({verb_id, raw_verb_name, grant}, "Verb debugging info")

          verb_name =
            case raw_verb_name do
              verb_name when is_binary(verb_name) -> String.downcase(verb_name)
              # fallback to verb_id
              _ -> to_string(verb_id)
            end

          value =
            case e(grant, :value, nil) do
              true -> :can
              false -> :cannot
              nil -> nil
            end

          debug({verb_name, value, subject_id}, "Creating verb permission with name")

          current_verb_map = Map.get(verb_acc, verb_name, %{})
          Map.put(verb_acc, verb_name, Map.put(current_verb_map, subject_id, value))
        end)
      end)

    debug(verb_permissions, "Final verb_permissions from transform")

    # Extract circles for UI display
    to_circles =
      Enum.map(acl_subject_verb_grants, fn {_id, %{subject: subject}} ->
        # Verbs determined from verb_permissions
        {subject, nil}
      end)

    {verb_permissions, to_circles}
  end

  @doc """
  Reconstructs verb_permissions map from to_circles and exclude_circles lists.

  This is the reverse of transform_to_circles_format/1, used to restore state
  when components are recreated (e.g., modal reopening).
  """
  def reconstruct_verb_permissions(to_circles, exclude_circles) do
    verb_permissions = %{}

    # Process to_circles (both positive and negative permissions)
    verb_permissions =
      Enum.reduce(to_circles || [], verb_permissions, fn {circle, verbs}, acc ->
        circle_id = id(circle)

        # Parse verbs (handle both string and list formats)
        verb_list =
          case verbs do
            verbs_string when is_binary(verbs_string) ->
              if verbs_string == "", do: [], else: String.split(verbs_string, ",")

            verb_list when is_list(verb_list) ->
              Enum.map(verb_list, &to_string/1)

            single_verb ->
              [to_string(single_verb)]
          end

        # Process each verb, handling both positive and negative permissions
        # Note: Negative permissions come as individual "cannot_verb" entries, not comma-separated
        Enum.reduce(verb_list, acc, fn verb, verb_acc ->
          verb_string = to_string(verb)

          # Check if this is a negative permission (starts with "cannot_")
          if String.starts_with?(verb_string, "cannot_") do
            # Extract the actual verb name by removing "cannot_" prefix
            actual_verb = String.replace_prefix(verb_string, "cannot_", "")
            current_verb_map = Map.get(verb_acc, actual_verb, %{})
            Map.put(verb_acc, actual_verb, Map.put(current_verb_map, circle_id, :cannot))
          else
            # Positive permission (can be comma-separated for efficiency)
            current_verb_map = Map.get(verb_acc, verb_string, %{})
            Map.put(verb_acc, verb_string, Map.put(current_verb_map, circle_id, :can))
          end
        end)
      end)

    # Note: exclude_circles processing is now handled above in the to_circles processing
    # since we encode negative permissions as "cannot_verb" in to_circles

    verb_permissions
  end
end
