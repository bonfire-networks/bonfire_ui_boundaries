defmodule Bonfire.UI.Boundaries.BlockButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component
  import Bonfire.Boundaries.Integration

  # TODO: make stateful and preload block status?

  prop object, :any
  prop is_local_user, :any, default: nil

  prop scope, :any, default: nil
  prop type, :atom, default: :block
  prop my_block, :any, default: nil

  prop only_admin, :boolean, default: false
  prop only_user, :boolean, default: false

  # for a `:lock`, the group the thread is in, so locking it in a group hosted elsewhere offers to apply it here at once
  prop group, :any, default: nil

  # visual
  prop parent_id, :any, default: nil
  prop with_icon, :boolean, default: false
  prop icon_class, :css_class, default: nil
  prop hide_text, :boolean, default: false
  prop class, :css_class
  prop label, :string, default: nil
  prop open_btn_label, :string, default: nil
  prop title, :string, default: nil

  @doc """
  Whether to offer the group's own ghost, silence or block ("In the group") of this `type`: to someone who may moderate the group. A silence or block by a moderator here of a group hosted elsewhere is a request to its instance, which reads it as a ban, so it is offered. A ghost is not, for now: that instance would read it as a silence too (the group federation plan, "Group bans and removals", ⑦). The moderator's own ghost, silence and block are unaffected.
  """
  def group_block_offered?(scope, _context, _type) when scope in [nil, :instance], do: false

  def group_block_offered?(scope, context, type) do
    Bonfire.Boundaries.can?(context, :mediate, scope) == true and
      not (type == :ghost and hosted_elsewhere?(scope))
  end

  defp hosted_elsewhere?(scope) do
    group =
      if is_binary(scope) do
        case Bonfire.Common.Needles.get(scope, skip_boundary_check: true) do
          {:ok, group} -> group
          _ -> nil
        end
      else
        scope
      end

    not is_nil(group) and is_local?(group, preload_if_needed: true) != true
  end

  def render(assigns) do
    assigns
    # Whether to offer `also_unfollow_and_notify`. Only for a remote PERSON, matching the same two conditions `Blocks.maybe_federate_block/3` applies, so the checkbox never promises something the context will decline to do:
    #
    # not local, because both halves exist to reach the case our own boundaries cannot, which is their server's shared inbox still delivering a post it received for someone else on that host. For a local person the boundary already stops it and there is nobody to notify.
    #
    # not an instance, because a follow is between people and a `Block` names an actor. Blocking a host is local policy with nothing to sever and nobody to tell.
    |> assign_new(:offer_unfollow_and_notify?, fn ->
      remote? =
        if is_nil(assigns[:is_local_user]),
          do: is_local?(assigns[:object], preload_if_needed: false) != true,
          else: assigns[:is_local_user] != true

      remote? and Types.object_type(assigns[:object]) != Bonfire.Data.ActivityPub.Peer
    end)
    |> assign_new(:type_display, fn ->
      case assigns[:type] do
        :block -> l("Block")
        :silence -> l("Silence")
        :ghost -> l("Ghost")
        :hide -> l("Hide")
        :lock -> l("Lock or unlock")
        type -> type
      end
    end)
    |> assign_new(:action_label, fn ->
      # Use a full-phrase msgid per action type (verb baked in) so translators can
      # reorder verb and name — e.g. German "%{user_or_instance_name} ghosten".
      # Composing a separately-translated verb into "%{type} %{name}" can't be reordered.
      name = assigns[:label]

      case assigns[:type] do
        :block -> l("Block %{user_or_instance_name}", user_or_instance_name: name)
        :silence -> l("Silence %{user_or_instance_name}", user_or_instance_name: name)
        :ghost -> l("Ghost %{user_or_instance_name}", user_or_instance_name: name)
        :hide -> l("Hide %{user_or_instance_name}", user_or_instance_name: name)
        :lock -> l("Lock or unlock discussion")
        _ -> name
      end
    end)
    |> assign(
      :can_instance_wide?,
      # TODO: optimise so it doesn't make a query every time
      Bonfire.Boundaries.can?(assigns[:__context__], :block, :instance_wide)
    )
    |> render_sface()
  end
end
