defmodule Bonfire.UI.Boundaries.CustomizeBoundaryAvailableVerbsTest do
  @moduledoc """
  Covers the verb list that `CustomizeBoundaryLive.get_available_verbs/4` builds for the boundary editor.

  A verb configured without a `:summary` gets a generated sentence ("Who can %{verb} this"). The verb in it must be in the user's locale and lowercase, because it sits mid-sentence. The sentence must not name an object type, because the editor also edits presets and instance permissions.
  """
  use ExUnit.Case, async: true

  # bare `ExUnit.Case` skips the tag that the ConnCase applies
  @moduletag :ui

  alias Bonfire.Common.Localise.Gettext, as: Backend
  alias Bonfire.Boundaries.Verbs
  alias Bonfire.UI.Boundaries.CustomizeBoundaryLive

  @locale "fr"

  setup do
    previous = Gettext.get_locale(Backend)
    Gettext.put_locale(Backend, @locale)
    on_exit(fn -> Gettext.put_locale(Backend, previous) end)
    :ok
  end

  test "the locale under test is compiled and translates the verb" do
    # without this, the assertions below would pass against the untranslated English
    assert @locale in Gettext.known_locales(Backend)
    assert Verbs.verb_name(:like) == "Aimer"
  end

  test "a verb without a summary gets a generated one with the localised, lowercased verb" do
    # `Verbs.verbs/0` reads `Config.get!(:verbs, otp_app: :bonfire)`, which checks the process dict first in test env
    Process.put(
      [:bonfire, :verbs],
      Keyword.update!(Verbs.verbs(), :like, &Map.delete(&1, :summary))
    )

    assert [%{slug: :like, summary: summary}] =
             CustomizeBoundaryLive.get_available_verbs(nil, nil, [:like], nil)

    assert summary =~ "aimer"
    refute summary =~ "Like"
    refute summary =~ "post"
  end

  test "a verb with a configured summary keeps it" do
    assert [%{slug: :like, summary: summary}] =
             CustomizeBoundaryLive.get_available_verbs(nil, nil, [:like], nil)

    assert summary == Verbs.verbs()[:like][:summary]
  end

  test "the name stays the configured one, since the template builds element ids from it" do
    assert [%{slug: :like, name: name}] =
             CustomizeBoundaryLive.get_available_verbs(nil, nil, [:like], nil)

    assert name == Verbs.verbs()[:like][:verb]
  end
end
