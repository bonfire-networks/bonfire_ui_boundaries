defmodule Bonfire.UI.Boundaries.BlockUnfollowNotifyLive do
  @moduledoc """
  The `also_unfollow_and_notify` checkbox, shown inside the block/ghost/silence forms.

  One control governing two things that move together: it severs the follow, and it tells the other server about the block. Both reach past our own instance, and both are noticeable, which is why they are a single choice rather than two settings.

  Its own component because the same checkbox belongs in all three forms, and because the copy has to differ per type: ghosting severs THEIR follow of me, silencing severs MINE of them, and blocking does both.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop type, :atom, required: true

  # not `label/1`: `Bonfire.UI.Common.CoreComponents` imports one, and a local of the same name shadows it for the whole module
  @doc "Why someone would want this, as the checkbox label. Answers the question the checkbox raises rather than naming the mechanism."
  def offer(:ghost), do: l("Do more to stop them seeing your posts")
  def offer(:silence), do: l("Do more to keep their posts away from you")
  def offer(_), do: l("Do more to enforce the block")

  @doc "What it actually does, including the part that only their server can carry out."
  def what(:ghost),
    do:
      l(
        "Removes them from your followers and also asks their server to enforce the block, so it can stop showing them any of your posts. Without this they may still see some of them."
      )

  # No mention of their server, because silencing tells it nothing: it is a MUTE, which does not federate anywhere, and their server cannot help with what I see in my own feed. Only the ghost half asks anything of anyone else.
  def what(:silence),
    do: l("Unfollows them, so their posts stop being sent to your feed.")

  def what(_),
    do:
      l(
        "Removes any follow between you, in both directions, and also asks their server to enforce the block. Without this you may still see some of each other's posts."
      )

  @doc """
  What it costs, as its own line rather than a trailing clause.

  Two different kinds of cost. Being noticed is a probability: they may work it out from the follow going, or their server may tell them outright. Not being able to take it back is a certainty, and it is the half nobody can walk back, so it says who would have to act to restore things.
  """
  def risk(:ghost),
    do:
      l(
        "They may notice: they disappear from your followers, and their server is told about the block. Unghosting does not undo it, they would have to follow you again themselves."
      )

  def risk(:silence),
    do:
      l(
        "They may notice that they lost you as a follower. Unsilencing does not undo it, you would have to follow them again."
      )

  def risk(_),
    do:
      l(
        "They may notice: any follows disappear in both directions, and their server is told about the block. Unblocking does not undo it, you would each have to follow the other again."
      )
end
