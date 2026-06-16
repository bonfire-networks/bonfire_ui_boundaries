defmodule Bonfire.UI.Boundaries.AclAudienceSummaryLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Common.Media

  prop acl_subject_verb_grants, :any, default: %{}
  prop show_heading, :boolean, default: true

  def audiences(subject_verb_grants) when is_map(subject_verb_grants) do
    order = verb_order_index()

    subject_verb_grants
    |> Map.values()
    |> Enum.map(fn entry ->
      subject = e(entry, :subject, nil)

      {allowed, blocked} =
        e(entry, :grants, %{})
        |> Map.to_list()
        |> Enum.reduce({[], []}, fn {verb_id, grant}, {allowed, blocked} ->
          case Bonfire.Boundaries.Verbs.get(verb_id) do
            nil ->
              {allowed, blocked}

            verb_config ->
              verb = Map.put(verb_config, :slug, Bonfire.Boundaries.Verbs.get_slug(verb_id))

              case e(grant, :value, nil) do
                true -> {[verb | allowed], blocked}
                false -> {allowed, [verb | blocked]}
                _ -> {allowed, blocked}
              end
          end
        end)

      %{
        subject: subject,
        is_user: is_user?(subject),
        name: subject_name(subject),
        icon: subject_icon(subject),
        allowed: sort_verbs(allowed, order),
        blocked: sort_verbs(blocked, order)
      }
    end)
    |> Enum.reject(fn %{allowed: allowed, blocked: blocked} ->
      allowed == [] and blocked == []
    end)
    |> Enum.sort_by(fn %{is_user: is_user, name: name} -> {is_user, name || ""} end)
  end

  def audiences(_), do: []

  def is_user?(subject), do: not is_nil(e(subject, :profile, nil))

  def subject_name(subject), do: Bonfire.Boundaries.LiveHandler.subject_name(subject)

  def subject_icon(subject), do: Bonfire.Boundaries.LiveHandler.subject_icon(subject)

  def verb_name(verb) do
    localise_dynamic(
      e(verb, :name, nil) || e(verb, :verb, "?") |> to_string() |> String.capitalize(),
      __MODULE__
    )
  end

  def verb_summary(verb), do: localise_dynamic(e(verb, :summary, nil), __MODULE__)

  defp sort_verbs(verbs, order) do
    Enum.sort_by(verbs, fn verb -> Map.get(order, e(verb, :slug, nil), 999) end)
  end

  defp verb_order_index do
    Bonfire.UI.Boundaries.CustomizeBoundaryLive.verb_order()
    |> Enum.with_index()
    |> Map.new()
  rescue
    _ -> %{}
  end
end
