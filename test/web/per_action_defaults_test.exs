defmodule Bonfire.UI.Boundaries.PerActionDefaultsTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"

  alias Bonfire.UI.Boundaries.PerActionDefaultsLive
  alias Bonfire.Boundaries.Circles

  @guest_id Circles.get_id(:guest)
  @followed_id Circles.get_id(:followed)
  @followers_id Circles.get_id(:followers)

  describe "actions/0" do
    test "exposes read, reply and quote with verbs and icons" do
      assert [read, reply, quote_] = PerActionDefaultsLive.actions()
      assert %{key: "read", verbs: ["read", "see"], icon: "ph:eye-duotone"} = read
      assert %{key: "reply", verbs: ["reply"], icon: "ph:chat-circle-duotone"} = reply
      assert %{key: "quote", verbs: ["quote"], icon: "ph:quotes-duotone"} = quote_
    end
  end

  describe "preset_locks_action?/1" do
    test "locks only the presets with no broader audience" do
      for slug <- ~w(mentions private) do
        assert PerActionDefaultsLive.preset_locks_action?(slug),
               "preset #{slug} should lock per-action toggles"

        assert PerActionDefaultsLive.preset_locks_action?({slug, "Label"}),
               "tuple shape {#{slug}, _} should lock per-action toggles"

        assert PerActionDefaultsLive.preset_locks_action?([{slug, "Label"}, {:foo, :bar}]),
               "list shape starting with {#{slug}, _} should lock per-action toggles"
      end
    end

    test "does NOT lock presets that retain a broader audience" do
      for slug <- ~w(public local follows custom) do
        refute PerActionDefaultsLive.preset_locks_action?(slug),
               "preset #{slug} must remain editable"

        refute PerActionDefaultsLive.preset_locks_action?({slug, "Label"}),
               "tuple shape {#{slug}, _} must remain editable"
      end
    end

    test "nil preset is never locked (custom ACLs stay editable)" do
      refute PerActionDefaultsLive.preset_locks_action?(nil)
    end
  end

  describe "action_allowed?/3 — preset defaults (no explicit overrides)" do
    setup do
      %{action: hd(PerActionDefaultsLive.actions())}
    end

    test "Public preset → ON", %{action: action} do
      assert PerActionDefaultsLive.action_allowed?(%{}, {"public", "Public"}, action)
    end

    test "Local preset → ON", %{action: action} do
      assert PerActionDefaultsLive.action_allowed?(%{}, {"local", "Local"}, action)
    end

    test "Mentions preset → OFF", %{action: action} do
      refute PerActionDefaultsLive.action_allowed?(%{}, {"mentions", "Mentions"}, action)
    end

    test "Follows preset → OFF", %{action: action} do
      refute PerActionDefaultsLive.action_allowed?(%{}, {"follows", "Follows"}, action)
    end

    test "Private preset → OFF", %{action: action} do
      refute PerActionDefaultsLive.action_allowed?(%{}, {"private", "Private"}, action)
    end

    test "Custom (start from scratch) → OFF", %{action: action} do
      refute PerActionDefaultsLive.action_allowed?(%{}, {"custom", "Custom"}, action)
    end

    test "Unknown preset / nil → ON (legacy fallback for custom ACLs)", %{action: action} do
      assert PerActionDefaultsLive.action_allowed?(%{}, nil, action)
      assert PerActionDefaultsLive.action_allowed?(%{}, {"some_custom_acl", "My ACL"}, action)
    end

    test "read + reply default ON under public; quote defaults OFF (no preset grants :quote)" do
      actions_by_key = Map.new(PerActionDefaultsLive.actions(), &{&1.key, &1})

      assert PerActionDefaultsLive.action_allowed?(
               %{},
               {"public", "Public"},
               actions_by_key["read"]
             )

      assert PerActionDefaultsLive.action_allowed?(
               %{},
               {"public", "Public"},
               actions_by_key["reply"]
             )

      refute PerActionDefaultsLive.action_allowed?(
               %{},
               {"public", "Public"},
               actions_by_key["quote"]
             ),
             "quote isn't in any preset ACL — the toggle shouldn't pretend it's on"
    end

    test "quote defaults OFF under local too (participate role stops short of :quote)" do
      actions_by_key = Map.new(PerActionDefaultsLive.actions(), &{&1.key, &1})

      refute PerActionDefaultsLive.action_allowed?(
               %{},
               {"local", "Local"},
               actions_by_key["quote"]
             )
    end

    test "all three actions default OFF under mentions (including quote)" do
      for action <- PerActionDefaultsLive.actions() do
        refute PerActionDefaultsLive.action_allowed?(%{}, {"mentions", "Mentions"}, action),
               "#{action.key} should default OFF under mentions — no broader audience to grant to"
      end
    end

    test "all three actions default OFF under private (including quote)" do
      for action <- PerActionDefaultsLive.actions() do
        refute PerActionDefaultsLive.action_allowed?(%{}, {"private", "Private"}, action),
               "#{action.key} should default OFF under private"
      end
    end
  end

  describe "preset_grants_any?/2" do
    test "public grants read and reply, but not quote" do
      assert PerActionDefaultsLive.preset_grants_any?({"public", "Public"}, ["read", "see"])
      assert PerActionDefaultsLive.preset_grants_any?({"public", "Public"}, ["reply"])
      refute PerActionDefaultsLive.preset_grants_any?({"public", "Public"}, ["quote"])
    end

    test "local grants read and reply, but not quote" do
      assert PerActionDefaultsLive.preset_grants_any?({"local", "Local"}, ["read", "see"])
      assert PerActionDefaultsLive.preset_grants_any?({"local", "Local"}, ["reply"])
      refute PerActionDefaultsLive.preset_grants_any?({"local", "Local"}, ["quote"])
    end

    test "nil / unknown preset → false (can't introspect)" do
      refute PerActionDefaultsLive.preset_grants_any?(nil, ["reply"])
      refute PerActionDefaultsLive.preset_grants_any?({"made_up_slug", "x"}, ["reply"])
    end
  end

  describe "preset_audience_circle_ids/1" do
    test "public → guest, local, activity_pub" do
      audience = PerActionDefaultsLive.preset_audience_circle_ids({"public", "Public"})

      for slug <- [:guest, :local, :activity_pub] do
        assert Circles.get_id(slug) in audience,
               "#{slug} should be part of the public reading audience"
      end
    end

    test "local → local only (preset doesn't grant guest or fediverse)" do
      audience = PerActionDefaultsLive.preset_audience_circle_ids({"local", "Local"})
      assert Circles.get_id(:local) in audience
      refute Circles.get_id(:guest) in audience
      refute Circles.get_id(:activity_pub) in audience
    end

    test "custom / nil / private → empty (no discoverable audience)" do
      for preset <- [nil, {"custom", "Custom"}, {"private", "Private"}, {"mentions", "Mentions"}] do
        assert PerActionDefaultsLive.preset_audience_circle_ids(preset) == [],
               "expected empty audience for #{inspect(preset)}"
      end
    end
  end

  describe "action_allowed?/3 — explicit overrides win over preset defaults" do
    test "explicit :cannot on guest flips a public preset OFF" do
      action = %{verbs: ["reply"]}
      verb_perms = %{"reply" => %{@guest_id => :cannot}}

      refute PerActionDefaultsLive.action_allowed?(verb_perms, {"public", "Public"}, action)
    end

    test "explicit :can on guest flips a follows preset ON" do
      action = %{verbs: ["reply"]}
      verb_perms = %{"reply" => %{@guest_id => :can}}

      assert PerActionDefaultsLive.action_allowed?(verb_perms, {"follows", "Follows"}, action)
    end

    test "multi-verb action (read) — :cannot on ANY verb wins" do
      action = %{verbs: ["read", "see"]}
      verb_perms = %{"see" => %{@guest_id => :cannot}}

      refute PerActionDefaultsLive.action_allowed?(verb_perms, {"public", "Public"}, action)
    end

    test "multi-verb action (read) — :can on ONE verb promotes a follows OFF → ON" do
      action = %{verbs: ["read", "see"]}
      verb_perms = %{"read" => %{@guest_id => :can}}

      assert PerActionDefaultsLive.action_allowed?(verb_perms, {"follows", "Follows"}, action)
    end
  end

  describe "action_exception_checked?/4" do
    setup do
      action = %{verbs: ["reply"]}
      %{action: action}
    end

    test "nil circle id → false", %{action: action} do
      refute PerActionDefaultsLive.action_exception_checked?(%{}, nil, action, %{})
    end

    test "explicit :can on all verbs → true", %{action: action} do
      circle = %{id: @followed_id}
      perms = %{"reply" => %{@followed_id => :can}}

      assert PerActionDefaultsLive.action_exception_checked?(
               perms,
               {"public", "Public"},
               action,
               circle
             )
    end

    # NOTE: explicit :cannot does NOT suppress a preset default match — the check is
    # "explicit :can OR preset default" by design. Not user-reachable from the UI
    # (toggle_action_exception only writes :can/nil, never :cannot).
    test "preset default still wins when verb_permissions holds :cannot for the same circle",
         %{action: action} do
      circle = %{id: @followed_id, stereotyped: %{stereotype_id: @followed_id}}
      perms = %{"reply" => %{@followed_id => :cannot}}

      assert PerActionDefaultsLive.action_exception_checked?(
               perms,
               {"follows", "Follows"},
               action,
               circle
             )
    end

    test "follows preset pre-checks the :followed stereotype circle", %{action: action} do
      circle = %{id: @followed_id, stereotyped: %{stereotype_id: @followed_id}}

      assert PerActionDefaultsLive.action_exception_checked?(
               %{},
               {"follows", "Follows"},
               action,
               circle
             )
    end

    test ":followers circle is NOT pre-checked under follows preset (only :followed is)",
         %{action: action} do
      circle = %{id: @followers_id, stereotyped: %{stereotype_id: @followers_id}}

      refute PerActionDefaultsLive.action_exception_checked?(
               %{},
               {"follows", "Follows"},
               action,
               circle
             )
    end

    test "no preset default under public preset — circle with :followed stereotype is unchecked",
         %{action: action} do
      circle = %{id: @followed_id, stereotyped: %{stereotype_id: @followed_id}}

      refute PerActionDefaultsLive.action_exception_checked?(
               %{},
               {"public", "Public"},
               action,
               circle
             )
    end

    test "multi-verb action requires :can on ALL verbs to be checked" do
      action = %{verbs: ["read", "see"]}
      circle = %{id: @followed_id}

      partial = %{"read" => %{@followed_id => :can}}

      refute PerActionDefaultsLive.action_exception_checked?(partial, nil, action, circle),
             "only :can on :read is not enough — both verbs must be granted"

      full = %{"read" => %{@followed_id => :can}, "see" => %{@followed_id => :can}}

      assert PerActionDefaultsLive.action_exception_checked?(full, nil, action, circle)
    end
  end

  describe "exception_circles/1" do
    test "nil or empty input returns []" do
      assert PerActionDefaultsLive.exception_circles(nil) == []
      assert PerActionDefaultsLive.exception_circles([]) == []
    end

    test "excludes guest, admin, mod, suggested, and block stereotypes — keeps local + activity_pub + user circles" do
      alias Bonfire.Boundaries.Scaffold.Instance

      circles = [
        %{id: Circles.get_id(:guest), named: %{name: "Anyone"}},
        %{id: Circles.get_id(:local), named: %{name: "Local users"}},
        %{id: Circles.get_id(:activity_pub), named: %{name: "Anyone in the fediverse"}},
        %{id: Instance.admin_circle(), named: %{name: "Admins"}},
        %{id: Instance.mod_circle(), named: %{name: "Mods"}},
        %{id: Instance.suggested_profiles_circle(), named: %{name: "Suggested"}},
        %{id: "01JZABCD0MYCUSTOMCIRCLE0123", named: %{name: "Besties"}}
      ]

      result_ids = Enum.map(PerActionDefaultsLive.exception_circles(circles), & &1.id)

      refute Circles.get_id(:guest) in result_ids,
             "guest is the target being restricted — must be excluded"

      for excluded <- [
            Instance.admin_circle(),
            Instance.mod_circle(),
            Instance.suggested_profiles_circle()
          ] do
        refute excluded in result_ids,
               "infrastructure circles don't make sense as per-post exceptions"
      end

      assert Circles.get_id(:local) in result_ids,
             "local users must be selectable as an exception"

      assert Circles.get_id(:activity_pub) in result_ids,
             "fediverse users must be selectable as an exception"

      assert "01JZABCD0MYCUSTOMCIRCLE0123" in result_ids,
             "user-defined circles must pass through"
    end
  end

  describe "apply_action_toggle/4" do
    alias Bonfire.UI.Boundaries.CustomizeBoundaryLive

    test "reply OFF under public writes :cannot for guest + local + activity_pub" do
      {updated, grants} =
        CustomizeBoundaryLive.apply_action_toggle(false, {"public", "Public"}, ["reply"], %{})

      reply_map = updated["reply"]

      for slug <- [:guest, :local, :activity_pub] do
        assert reply_map[Circles.get_id(slug)] == :cannot,
               "#{slug} must be blocked — preset grants reply to the full audience"

        assert {Circles.get_id(slug), "reply", :cannot} in grants,
               "grants list must mirror the map for #{slug}"
      end
    end

    test "read OFF under public writes :cannot across both verbs for the full audience" do
      {updated, _} =
        CustomizeBoundaryLive.apply_action_toggle(
          false,
          {"public", "Public"},
          ["read", "see"],
          %{}
        )

      for v <- ["read", "see"], slug <- [:guest, :local, :activity_pub] do
        assert updated[v][Circles.get_id(slug)] == :cannot,
               "#{v} must be :cannot for #{slug}"
      end
    end

    test "quote ON under public ('grant' mode — preset doesn't grant :quote) writes :can for the reading audience" do
      {updated, _} =
        CustomizeBoundaryLive.apply_action_toggle(true, {"public", "Public"}, ["quote"], %{})

      quote_map = updated["quote"]

      for slug <- [:guest, :local, :activity_pub] do
        assert quote_map[Circles.get_id(slug)] == :can,
               "#{slug} should receive :can when lifting quote under public"
      end
    end

    test "reply ON under public ('same' mode — preset already grants) clears all overrides" do
      current = %{
        "reply" => %{
          Circles.get_id(:guest) => :cannot,
          Circles.get_id(:local) => :cannot
        }
      }

      {updated, grants} =
        CustomizeBoundaryLive.apply_action_toggle(true, {"public", "Public"}, ["reply"], current)

      refute Map.has_key?(updated, "reply"),
             "the reply override map should be dropped so the preset default re-applies"

      for {cid, _} <- current["reply"] do
        assert {cid, "reply", nil} in grants,
               "each previously-set circle should be cleared"
      end
    end

    test "reply OFF under mentions blocks guest (mentions preset grants nothing to override)" do
      {updated, _} =
        CustomizeBoundaryLive.apply_action_toggle(false, {"mentions", "Mentions"}, ["reply"], %{})

      assert updated["reply"][Circles.get_id(:guest)] == :cannot
    end

    test "OFF on unknown / nil preset defaults to guest-only block" do
      {updated, _} = CustomizeBoundaryLive.apply_action_toggle(false, nil, ["reply"], %{})

      assert updated["reply"][Circles.get_id(:guest)] == :cannot

      refute Map.has_key?(updated["reply"], Circles.get_id(:local)),
             "nothing to override on an unknown preset — only guest gets blocked"
    end
  end

  describe "build_states/3 (render-path materialisation)" do
    test "materialised allowed? matches action_allowed?/3 per action and per preset" do
      for preset <- [{"public", "Public"}, {"local", "Local"}, {"mentions", "Mentions"}, nil] do
        %{action_states: states} = PerActionDefaultsLive.build_states(%{}, preset, [])

        for action_state <- states do
          action = Enum.find(PerActionDefaultsLive.actions(), &(&1.key == action_state.key))

          assert action_state.allowed? ==
                   PerActionDefaultsLive.action_allowed?(%{}, preset, action),
                 "build_states drifted from action_allowed? for #{action_state.key} under #{inspect(preset)}"
        end
      end
    end

    test "locked? reflects preset_locks_action?/1" do
      assert %{locked?: true} = PerActionDefaultsLive.build_states(%{}, {"mentions", "x"}, [])
      assert %{locked?: true} = PerActionDefaultsLive.build_states(%{}, {"private", "x"}, [])
      assert %{locked?: false} = PerActionDefaultsLive.build_states(%{}, {"public", "x"}, [])
      assert %{locked?: false} = PerActionDefaultsLive.build_states(%{}, nil, [])
    end

    test "show_exceptions? stays false when quote is OFF-by-default under public (no user input, no preset pre-checks)" do
      my_circle = %{id: "01JZABCD0MYCUSTOMCIRCLE0123", named: %{name: "besties"}}

      %{action_states: states} =
        PerActionDefaultsLive.build_states(%{}, {"public", "Public"}, [my_circle])

      quote_state = Enum.find(states, &(&1.key == "quote"))

      refute quote_state.allowed?, "precondition: quote defaults OFF under public"

      refute quote_state.show_exceptions?,
             "exceptions picker should stay collapsed until the user shapes quote permissions"
    end

    test "show_exceptions? becomes true once the user writes any override on the action's verbs" do
      my_circle = %{id: "01JZABCD0MYCUSTOMCIRCLE0123", named: %{name: "besties"}}

      # User just toggled reply OFF → :cannot override exists → picker opens.
      verb_perms = %{"reply" => %{Circles.get_id(:guest) => :cannot}}

      %{action_states: states} =
        PerActionDefaultsLive.build_states(verb_perms, {"public", "Public"}, [my_circle])

      reply_state = Enum.find(states, &(&1.key == "reply"))

      refute reply_state.allowed?
      assert reply_state.show_exceptions?
    end

    test "show_exceptions? is true under follows preset when a circle is preset-pre-checked" do
      # Under `follows`, the :followed stereotype is pre-checked even with no user input.
      followed_circle = %{
        id: Circles.get_id(:followed),
        stereotyped: %{stereotype_id: Circles.get_id(:followed)}
      }

      %{action_states: states} =
        PerActionDefaultsLive.build_states(%{}, {"follows", "Follows"}, [followed_circle])

      reply_state = Enum.find(states, &(&1.key == "reply"))

      refute reply_state.allowed?, "follows preset leaves reply OFF for the general audience"

      assert reply_state.show_exceptions?,
             "preset pre-checks :followed — exceptions row must stay visible for transparency"
    end
  end

  describe "preset_block_circle_ids/2" do
    test "public preset + reply → blocks guest, local and activity_pub" do
      result = PerActionDefaultsLive.preset_block_circle_ids({"public", "Public"}, ["reply"])

      assert Circles.get_id(:guest) in result,
             "guest must be blocked — it's the baseline"

      assert Circles.get_id(:local) in result,
             "local users have :participate under public — must also be blocked"

      assert Circles.get_id(:activity_pub) in result,
             "fediverse users have :participate under public — must also be blocked"
    end

    test "public preset + read → blocks guest, local and activity_pub (everyone_may_see_read)" do
      result =
        PerActionDefaultsLive.preset_block_circle_ids({"public", "Public"}, ["read", "see"])

      for slug <- [:guest, :local, :activity_pub] do
        assert Circles.get_id(slug) in result,
               "#{slug} must be blocked when disabling read/see under public"
      end
    end

    test "local preset + reply → blocks guest and local (locals_may_reply)" do
      result = PerActionDefaultsLive.preset_block_circle_ids({"local", "Local"}, ["reply"])

      assert Circles.get_id(:guest) in result
      assert Circles.get_id(:local) in result

      refute Circles.get_id(:activity_pub) in result,
             "local preset doesn't grant fediverse — nothing to override there"
    end

    test "custom / unknown / nil preset → only blocks guest" do
      for preset <- [nil, "custom", {"custom", "Custom"}, {"unknown_slug", "x"}] do
        assert PerActionDefaultsLive.preset_block_circle_ids(preset, ["reply"]) == [
                 PerActionDefaultsLive.anyone_circle_id()
               ],
               "expected only guest for preset #{inspect(preset)}"
      end
    end

    test "result is unique even when multiple verbs grant to the same circle" do
      result =
        PerActionDefaultsLive.preset_block_circle_ids({"public", "Public"}, ["read", "see"])

      assert result == Enum.uniq(result)
    end

    test "accepts tuple, list-of-tuple, and bare string preset shapes" do
      a = PerActionDefaultsLive.preset_block_circle_ids("public", ["reply"])
      b = PerActionDefaultsLive.preset_block_circle_ids({"public", "Public"}, ["reply"])
      c = PerActionDefaultsLive.preset_block_circle_ids([{"public", "Public"}], ["reply"])

      assert Enum.sort(a) == Enum.sort(b)
      assert Enum.sort(b) == Enum.sort(c)
    end
  end
end
