defmodule Bonfire.UI.Boundaries.CircleMembersWidgetTest do
  @moduledoc "The circle members widget shows the members of a circle chosen in the widget settings (like the feed widget's feed), or given as `?circle=` when embedded."
  use Bonfire.UI.Boundaries.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Social.Objects

  setup do
    # the dashboard lists only this widget, so it's on unless someone turns it off
    Process.put([:bonfire, Bonfire.Web.Views.DashboardLive, :widgets], main: [:circle_members])

    account = fake_account!()
    me = fake_user!(account)
    friend = fake_user!("circle friend")

    {:ok, circle} = Circles.create(me, %{named: %{name: "Garden friends"}})
    {:ok, _} = Circles.add_to_circles(friend, circle, skip_boundary_check: true)

    {:ok, conn: conn(user: me, account: account), me: me, circle: circle}
  end

  test "with no circle chosen, the dashboard doesn't show the widget", %{conn: conn} do
    conn
    |> visit("/dashboard")
    |> refute_has("[data-widget-id=circle_members] [data-role=widget-heading]")
    |> refute_has("[data-widget-id=circle_members]", text: "circle friend")
  end

  test "a member chooses one of their circles in the dashboard settings, and the dashboard shows its members",
       %{conn: conn} do
    conn
    |> visit("/settings/user/dashboard")
    # on the widget's tile; by its selector, not within the tile: `within` hides the form the select belongs to
    |> PhoenixTest.select(
      "[data-widget-id=circle_members] [data-role=widget-edit-controls] select",
      "Circle shown on the dashboard",
      option: "Garden friends"
    )
    |> visit("/dashboard")
    |> assert_has("[data-widget-id=circle_members] [data-role=widget-heading]",
      text: "Garden friends"
    )
    |> assert_has("[data-widget-id=circle_members] [data-role=user_name]", text: "circle friend")
  end

  describe "embedded" do
    setup %{me: me, circle: circle} do
      # shared with everyone, as a public list: what the circle manager's visibility picker does
      {:ok, _} = Objects.reset_preset_boundary(me, circle, nil, to_boundaries: "public")
      :ok
    end

    test "?circle= shows a public circle's members to anyone, as tiles with ?variant=portrait", %{
      circle: circle
    } do
      conn()
      |> visit("/embed/widget/circle_members?circle=#{circle.id}")
      |> assert_has("[data-widget-id=circle_members] [data-role=user_name]",
        text: "circle friend"
      )

      html =
        get(conn(), "/embed/widget/circle_members?circle=#{circle.id}&variant=portrait")
        |> html_response(200)

      assert html =~ "circle friend"
      refute Floki.find(Floki.parse_document!(html), "[data-role=user_name]") != []
    end

    test "a circle guests can't see shows nobody" do
      account = fake_account!()
      owner = fake_user!(account)
      {:ok, private} = Circles.create(owner, %{named: %{name: "Private garden"}})

      {:ok, _} =
        Circles.add_to_circles(fake_user!("secret friend"), private, skip_boundary_check: true)

      html =
        get(conn(), "/embed/widget/circle_members?circle=#{private.id}")
        |> html_response(200)

      refute html =~ "secret friend"
      refute html =~ "Private garden"
    end

    # a copy of the circle members embed saved on disk, as the static cache saves one per query string; every circle's copies are under the widget's one tag
    defp save_embed_copy do
      file =
        Path.join([
          Bonfire.UI.Common.StaticGenerator.dest_path(),
          Bonfire.UI.Common.Widgets.embed_tag(:circle_members),
          "_qs_saved",
          "index.html"
        ])

      File.mkdir_p!(Path.dirname(file))
      File.write!(file, "a saved copy")
      on_exit(fn -> File.rm_rf!(Path.dirname(Path.dirname(file))) end)
      file
    end

    test "a change to who a circle shows purges its embed's saved copies", %{
      me: me,
      circle: circle
    } do
      newcomer = fake_user!("newcomer")

      for change <- [
            fn -> Circles.add_to_circles(newcomer, circle, skip_boundary_check: true) end,
            fn -> Circles.remove_from_circles(newcomer, circle, skip_boundary_check: true) end,
            fn -> Circles.edit(circle, me, %{named: %{name: "Renamed garden"}}) end,
            fn -> Objects.reset_preset_boundary(me, circle, "public", to_boundaries: "local") end,
            fn -> Circles.empty_circles([circle]) end,
            fn -> Circles.delete(circle, current_user: me) end
          ] do
        copy = save_embed_copy()
        change.()
        refute File.exists?(copy), inspect(change)
      end
    end

    test "a member turning undiscoverable purges the embed's saved copies" do
      copy = save_embed_copy()
      member = fake_user!()

      Bonfire.Common.Settings.put([Bonfire.Me.Users, :undiscoverable], true, current_user: member)

      refute File.exists?(copy)
    end

    # the address now falls to the circle's own page (`/circle/:id/:tab`), not the iframe layout embeds get
    test "the old circle embed address serves no embed", %{circle: circle} do
      html = conn() |> get("/circle/#{circle.id}/embed") |> response(200)

      refute html =~ "bonfire:iframe-resize"
    end
  end
end
