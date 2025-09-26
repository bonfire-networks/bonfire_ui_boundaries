defmodule Bonfire.UI.Boundaries.BrowserCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a full browser for boundaries UI testing.

  If the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Bonfire.UI.Boundaries.BrowserCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature

      import Bonfire.UI.Boundaries.BrowserCase
      alias Wallaby.Query
      alias Wallaby.Browser

      import Bonfire.UI.Common.Testing.Helpers
      import Bonfire.Social.Fake
      import Untangle
      import Ecto.Adapters.SQL.Sandbox

      import Bonfire.UI.Boundaries.Test.ConnHelpers
      import Bonfire.UI.Boundaries.Test.FakeHelpers

      alias Bonfire.UI.Boundaries.Fake
      import Bonfire.UI.Boundaries.Fake

      @moduletag :e2e

      @endpoint Application.compile_env!(:bonfire, :endpoint_module)

      setup tags do
        # Manually checkout sandbox since we're in :manual mode, handle already checked out case
        case Ecto.Adapters.SQL.Sandbox.checkout(Bonfire.Common.Repo) do
          :ok -> :ok
          {:already, :owner} -> :ok
        end

        # Set to shared mode so browser can access same transaction
        Ecto.Adapters.SQL.Sandbox.mode(Bonfire.Common.Repo, {:shared, self()})

        # Start Wallaby session with metadata
        metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Bonfire.Common.Repo, self())
        {:ok, session} = Wallaby.start_session(metadata: metadata)
        {:ok, session: session}
      end

      @cookie_key "_bonfire_key"
      def user_browser_session(session) do
        username = System.get_env("ADMIN_USER", "test_user")
        pw = System.get_env("ADMIN_PASSWORD", "for-testing-only")
        account = fake_account!(%{credential: %{password: pw}})

        user =
          fake_user!(account, %{
            username: username,
            name: username
          })

        # alice = fake_user!()
        # conn = conn(user: alice)
        # conn = Phoenix.ConnTest.get(conn, "/")
        # %{@cookie_key => %{value: token}} = conn.resp_cookies

        user_session =
          session
          |> visit("/login")
          |> fill_in(Query.fillable_field("login_fields[email_or_username]"),
            with: username
          )
          |> fill_in(Query.fillable_field("login_fields[password]"), with: pw)
          # |> Browser.send_keys([:enter])
          |> click(Query.button("Log in"))
          # Wait for login to complete and redirect
          |> Browser.assert_has(Query.css("body"))
          # Ensure we're redirected away from login page
          |> Browser.refute_has(Query.css("input[name='login_fields[email_or_username]']"))

        {user_session, user}
      end

      def create_circles_and_preset(user) do
        # Create circles
        {:ok, friends_circle} =
          Bonfire.Boundaries.Circles.create(user, %{named: %{name: "friends"}})

        {:ok, work_circle} = Bonfire.Boundaries.Circles.create(user, %{named: %{name: "work"}})

        # Create a preset with specific verb permissions
        {:ok, preset_acl} =
          Bonfire.Boundaries.Acls.create(%{named: %{name: "social"}}, current_user: user)

        [ok: _] =
          Bonfire.Boundaries.Grants.grant(friends_circle, preset_acl, :read, true,
            current_user: user
          )

        %{
          friends_circle: friends_circle,
          work_circle: work_circle,
          preset_acl: preset_acl
        }
      end

      def create_post_with_boundaries(session, circles, text \\ "Testing boundary assignment") do
        session
        |> Browser.visit("/feed")
        # Wait for composer to load
        # |> Browser.assert_has(Query.css("#smart_input_container"))
        # Click the boundary settings button
        |> Browser.take_screenshot()
        |> Browser.click(Query.css("main_smart_input_button"))
        |> Browser.assert_text("Public")
        # |> open_browser()
        # Wait for modal to open and select the preset
        |> Browser.assert_has(Query.css("[data-role='selected_preset']"))
        |> Browser.assert_text("social")
        # Customize verb permissions for the work circle
        |> Browser.assert_has(
          Query.css(
            "button[phx-value-role='#{circles.work_circle.id}'][phx-value-verb='read'][phx-value-status='1']"
          )
        )
        |> Browser.click(
          Query.css(
            "button[phx-value-role='#{circles.work_circle.id}'][phx-value-verb='read'][phx-value-status='1']"
          )
        )
        |> Browser.assert_has(
          Query.css(
            "button[phx-value-role='#{circles.work_circle.id}'][phx-value-verb='reply'][phx-value-status='1']"
          )
        )
        |> Browser.click(
          Query.css(
            "button[phx-value-role='#{circles.work_circle.id}'][phx-value-verb='reply'][phx-value-status='1']"
          )
        )
        |> Browser.assert_has(
          Query.css(
            "button[phx-value-role='#{circles.work_circle.id}'][phx-value-verb='boost'][phx-value-status='0']"
          )
        )
        # Explicitly deny
        |> Browser.click(
          Query.css(
            "button[phx-value-role='#{circles.work_circle.id}'][phx-value-verb='boost'][phx-value-status='0']"
          )
        )
        # Fill in post content and publish
        |> Browser.fill_in(Query.text_field("Share your thoughts"), with: text)
        |> Browser.assert_has(Query.button("Publish"))
        |> Browser.click(Query.button("Publish"))
        |> Browser.assert_has(Query.css("[data-role='success']"))
        |> Browser.assert_text("Published")
      end
    end
  end

  def enable_latency_sim(session, latency) do
    Application.put_env(:wallaby, :js_logger, nil)

    Wallaby.Browser.execute_script(
      session,
      "liveSocket.enableLatencySim(#{latency})"
    )
  end

  def disable_latency_sim(session) do
    Wallaby.Browser.execute_script(session, "liveSocket.disableLatencySim()")
  end
end
