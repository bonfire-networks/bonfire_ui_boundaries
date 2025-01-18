defmodule Bonfire.UI.Boundaries.YourRoleLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop role_name, :string, required: true
  prop label, :string, default: nil
  prop role_permissions, :any, default: nil
  prop is_caretaker, :boolean, default: true
  prop scope, :any, default: nil

  #  FIXME: this should be in config where the verbs are defined
  @verb_order [
    :see,
    :read,
    :request,
    :like,
    :boost,
    :flag,
    :reply,
    :mention,
    :message,
    :tag,
    :label,
    :follow,
    :schedule,
    :pin,
    :create,
    :edit,
    :delete,
    :vote,
    :toggle,
    :describe,
    :grant,
    :assign,
    :invite,
    :mediate,
    :block,
    :configure
  ]

  @doc """
  Sorts a list of verbs according to the predefined @verb_order.
  """
  def sort_verbs(verbs) do
    # Convert @verb_order atoms to strings
    # lowercase all verbs
    verbs = Enum.map(verbs, &String.downcase/1)
    verb_order_strings = Enum.map(@verb_order, &Atom.to_string/1)
    debug(verb_order_strings, "verb_order_strings")
    # Keep only the verbs present in both verb_order_strings and verbs
    Enum.filter(verb_order_strings, fn verb -> verb in verbs end)
  end
end
