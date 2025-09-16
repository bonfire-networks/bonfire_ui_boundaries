defmodule Bonfire.UI.Boundaries.ExportImportCirclesTest do
  use Bonfire.UI.Boundaries.ConnCase, async: true
  use Bonfire.Common.Utils

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Social.Import

  setup do
    account = fake_account!()
    me = fake_user!(account)

    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, user: me}
  end

  test "export and then import circles with valid CSV data works", %{user: user, conn: conn} do
    # Create users to add to circles
    member1 = fake_user!("Member1")
    member2 = fake_user!("Member2")
    member3 = fake_user!("Member3")

    # Create circles and add members
    {:ok, circle1} = Circles.create(user, "Friends")
    {:ok, circle2} = Circles.create(user, "Work")

    assert {:ok, _} = Circles.add_to_circles(member1, circle1)
    assert {:ok, _} = Circles.add_to_circles(member2, circle1)
    assert {:ok, _} = Circles.add_to_circles(member2, circle2)
    assert {:ok, _} = Circles.add_to_circles(member3, circle2)

    # Verify circles and memberships exist
    assert Circles.is_encircled_by?(member1, circle1)
    assert Circles.is_encircled_by?(member2, circle1)
    assert Circles.is_encircled_by?(member2, circle2)
    assert Circles.is_encircled_by?(member3, circle2)

    # Test export via controller
    Logger.metadata(action: info("export circles via controller"))

    conn =
      conn
      |> assign(:current_user, user)
      |> get("/settings/export/csv/circles")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]

    # Verify exported CSV contains expected circle/member pairs
    exported_content = conn.resp_body

    assert String.contains?(
             exported_content,
             "Friends,#{Bonfire.Me.Characters.display_username(member1, true)}"
           )

    assert String.contains?(
             exported_content,
             "Friends,#{Bonfire.Me.Characters.display_username(member2, true)}"
           )

    assert String.contains?(
             exported_content,
             "Work,#{Bonfire.Me.Characters.display_username(member2, true)}"
           )

    assert String.contains?(
             exported_content,
             "Work,#{Bonfire.Me.Characters.display_username(member3, true)}"
           )

    # Write exported CSV to file
    csv_path = "/tmp/test_exported_circles.csv"
    File.write!(csv_path, conn.resp_body)

    # Create a new user to test import
    import_user = fake_user!("ImportUser")

    # Verify new user has no circles initially
    assert [] = Circles.list_my(import_user, exclude_stereotypes: true)

    Logger.metadata(action: info("import exported CSV"))

    # Import the exported CSV
    assert %{ok: 4} = Import.import_from_csv_file(:circles, import_user.id, csv_path)

    assert %{success: 4} = Oban.drain_queue(queue: :import)

    # Verify circles and memberships were imported correctly
    imported_circles = Circles.list_my(import_user, exclude_stereotypes: true)
    assert length(imported_circles) == 2

    friends_circle = Enum.find(imported_circles, &(e(&1, :named, :name, nil) == "Friends"))
    work_circle = Enum.find(imported_circles, &(e(&1, :named, :name, nil) == "Work"))

    assert friends_circle
    assert work_circle

    assert Circles.is_encircled_by?(member1, friends_circle)
    assert Circles.is_encircled_by?(member2, friends_circle)
    assert Circles.is_encircled_by?(member2, work_circle)
    assert Circles.is_encircled_by?(member3, work_circle)

    File.rm(csv_path)
  end

  test "import circles handles invalid CSV data gracefully", %{user: user} do
    # Create invalid CSV file
    csv_path = "/tmp/test_invalid_circles.csv"
    invalid_content = "Invalid Circle,invalid_username\nBad Circle,not_a_user\n"
    File.write!(csv_path, invalid_content)

    Logger.metadata(action: info("import invalid CSV"))

    # Import should handle errors gracefully
    Import.import_from_csv_file(:circles, user.id, csv_path)

    assert %{discard: 2} = Oban.drain_queue(queue: :import)

    File.rm(csv_path)
  end

  test "import circles with mixed valid/invalid CSV data", %{user: user} do
    # Create user to add to circle
    valid_member = fake_user!("ValidMember")

    # Create CSV with mixed valid and invalid data
    csv_path = "/tmp/test_mixed_circles.csv"

    mixed_content = """
    Test Circle,#{Bonfire.Me.Characters.display_username(valid_member, true)}
    Bad Circle,invalid_username
    Another Bad,not_a_user
    """

    File.write!(csv_path, mixed_content)

    Logger.metadata(action: info("import mixed CSV"))

    # Import should handle partial success
    Import.import_from_csv_file(:circles, user.id, csv_path)

    assert %{success: 1, discard: 2} = Oban.drain_queue(queue: :import)

    # Valid entry should be imported
    circles = Circles.list_my(user, exclude_stereotypes: true)
    test_circle = Enum.find(circles, &(e(&1, :named, :name, nil) == "Test Circle"))

    assert test_circle
    assert Circles.is_encircled_by?(valid_member, test_circle)

    File.rm(csv_path)
  end

  test "import circles creates new circles when they don't exist", %{user: user} do
    member = fake_user!("NewMember")

    csv_path = "/tmp/test_new_circles.csv"
    csv_content = "New Circle,#{Bonfire.Me.Characters.display_username(member, true)}\n"
    File.write!(csv_path, csv_content)

    # Verify circle doesn't exist initially
    assert {:error, :not_found} = Circles.get_by_name("New Circle", user)

    Import.import_from_csv_file(:circles, user.id, csv_path)
    assert %{success: 1} = Oban.drain_queue(queue: :import)

    # Verify circle was created and member added
    {:ok, circle} = Circles.get_by_name("New Circle", user)
    assert Circles.is_encircled_by?(member, circle)

    File.rm(csv_path)
  end
end
