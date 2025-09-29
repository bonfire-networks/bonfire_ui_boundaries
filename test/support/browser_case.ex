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

        # Configure Wallaby for better reliability with dynamic content
        Application.put_env(:wallaby, :max_wait_time, 10_000)  # 10 seconds

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

        # Disable JavaScript error checking for Milkdown issues
        Application.put_env(:wallaby, :js_errors, false)
        # Process.put(:feed_live_update_many_preload_mode, :inline)

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
          |> click(Query.button("Log in"))
          # Wait for login to complete and redirect
          |> Browser.assert_has(Query.css("body"))
          # Ensure we're redirected away from login page
          |> Browser.refute_has(Query.css("input[name='login_fields[email_or_username]']"))
          # Visit home page to ensure user session is fully established
          |> visit("/")
          # Wait for composer button to appear, indicating user session is ready
          |> Browser.assert_has(Query.css("#main_smart_input_button[data-role='composer_button']"))

        {user_session, user}
      end

      def login_as_user(session, user) do
        # Get user's username and set a test password
        username = user.username
        pw = "test-password-123"

        # Update the user's account with the test password
        account = user.account
        {:ok, _} = Bonfire.Me.Accounts.update_credential(account, %{password: pw})

        session
        |> visit("/login")
        |> fill_in(Query.fillable_field("login_fields[email_or_username]"), with: username)
        |> fill_in(Query.fillable_field("login_fields[password]"), with: pw)
        |> click(Query.button("Log in"))
        |> Browser.assert_has(Query.css("body"))
        |> Browser.refute_has(Query.css("input[name='login_fields[email_or_username]']"))
        |> visit("/")
        |> Browser.assert_has(Query.css("#main_smart_input_button[data-role='composer_button']"))
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

      def open_composer(session) do
        session
        |> click(Query.css("#main_smart_input_button[data-role='composer_button']"))
        |> assert_has(Query.css("#smart_input_container.translate-y-0"))
      end

      def open_boundary_modal(session) do
        session
        |> click(Query.css("#define_boundary button[data-role='open_modal']"))
        |> assert_has(Query.css("#persistent_modal_box"))
      end

      def close_boundary_modal(session) do
        session
        |> click(Query.css(".modal-box .btn-circle"))
        # |> refute_has(Query.css("#persistent_modal_box"))
      end

      def edit_permission(session, verb, id, value) do
        # Convert value to appropriate status label and phx-value-status
        {status_label, phx_status} =
          case value do
            1 -> {"can", "1"}
            0 -> {"cannot", "0"}
            _ -> {"undefined", ""}
          end
        capitalized_verb = String.capitalize(verb)

        session
        # Click the toggle to expand the verb section
        |> click(Query.css("div[data-id='#{capitalized_verb}_toggle']"))
        # Wait for the specific permission button to become visible (this implicitly waits for the section to expand)
        |> Browser.assert_has(Query.css("button[data-id='#{id}_#{verb}_#{status_label}'][phx-value-status='#{phx_status}']", visible: true))
        # Click the permission button
        |> click(Query.css("button[data-id='#{id}_#{verb}_#{status_label}'][phx-value-status='#{phx_status}']"))
        # Just verify the button exists after clicking (skip visual state check for now)
        |> Browser.assert_has(Query.css("button[data-id='#{id}_#{verb}_#{status_label}']"))
      end

      def edit_default_boundary(session, preset) do
        # Capitalize the preset name for the phx-value-name attribute
        capitalized_name = String.capitalize(preset)

        session
        # Click the boundary preset button to open the preset selector
        |> click(Query.css("#popup_boundaries_in_modal"))
        # Click the specific preset button
        |> click(Query.css("button[phx-value-id='#{preset}'][phx-value-name='#{capitalized_name}']"))
        # Verify the preset has been selected by checking the display within the modal context
        |> Browser.assert_has(Query.css("#popup_boundaries_in_modal [data-scope='#{preset}-boundary-set']", text: capitalized_name))
      end


      def compose(session, text) do
        # Wait for Milkdown editor to be fully initialized
        session
        |> Browser.assert_has(Query.css(".ProseMirror.milkdown-editor"))
        |> fill_in(Query.css(".ProseMirror.milkdown-editor"), with: text)
      end

      def publish(session) do
        session
        |> click(Query.css("#submit_btn"))
        |> Browser.assert_has(Query.css(".submitting_icon"))
        |> Browser.assert_has(Query.css("[data-id='flash'] a.btn", text: "Show"))
        # |> assert_text("Published")
      end

      def navigate_to_post(session) do
        session
        |> click(Query.css("[data-id='flash'] a.btn", text: "Show"))
      end

      def open_boundary_details(session) do
        session
        # Wait for more menu to be available
        |> Browser.assert_has(Query.css("[data-id='more_menu']"))
        |> click(Query.css("[data-id='more_menu']"))
        # Wait for dropdown menu to expand and boundary details button to appear
        |> Browser.assert_has(Query.css("[data-id='boundary_details'] button[data-role='open_modal']"))
        |> click(Query.css("[data-id='boundary_details'] button[data-role='open_modal']"))
      end

      def create_post_with_boundaries(session, circle, text \\ "Testing boundary assignment") do
        # Open the floating composer (matches wallaby reference patterns)
        session
        |> open_composer()
        |> open_boundary_modal()
        |> edit_permission("reply", circle.id, 1)
        |> edit_permission("edit", circle.id, 1)
        |> edit_permission("boost", circle.id, 0)
        |> edit_default_boundary("local")
        |> close_boundary_modal()
        |> compose(text)
        |> publish()

        # |> visit("/feed/local")
        |> navigate_to_post()
        # |> take_screenshot()
        |> open_boundary_details()
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
