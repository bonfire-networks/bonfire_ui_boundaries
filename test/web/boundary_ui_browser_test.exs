defmodule Bonfire.UI.Boundaries.BoundaryUIBrowserTest do
  use Bonfire.UI.Boundaries.BrowserCase, async: true

  alias Bonfire.Boundaries.{Circles, Acls, Grants}

  @tag :skip
  @tag :browser
  feature "can use a preset in composer and customize verb permissions", %{session: session} do
    # First get the logged-in user from browser session
    {user_session, me} = user_browser_session(session)

    # Create additional users for the test
    account = fake_account!()
    alice = fake_user!(account)
    bob = fake_user!(account)

    # Create circles and preset using the logged-in user
    circles = create_circles_and_preset(me)

    # Add users to circles
    {:ok, _} = Circles.add_to_circles(alice, circles.friends_circle)
    {:ok, _} = Circles.add_to_circles(bob, circles.work_circle)
    text = "Testing boundary assignment"

    user_session
    |> open_composer()
    |> open_boundary_modal()
    |> edit_permission("edit", circles.work_circle.id, 1)
    |> edit_default_boundary("local")
    |> close_boundary_modal()
    |> compose(text)
    |> publish()
    |> navigate_to_post()
    |> open_boundary_details()
  end
end
