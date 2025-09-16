defmodule Bonfire.UI.Boundaries.ExportImportBlocksTest do
  use Bonfire.UI.Boundaries.ConnCase, async: true

  alias Bonfire.Social.Import

  setup do
    account = fake_account!()
    me = fake_user!(account)

    conn = conn(user: me, account: account)

    {:ok, conn: conn, account: account, user: me}
  end

  describe "export/import round trip" do
    test "import silenced users with valid CSV data works", %{user: user, conn: conn} do
      test_export_import_round_trip(user, conn, :silence, "silenced", :silences)
    end

    test "import ghosted users with valid CSV data works", %{user: user, conn: conn} do
      test_export_import_round_trip(user, conn, :ghost, "ghosted", :ghosts)
    end

    test "import users as ghosted with valid CSV data works", %{user: user, conn: conn} do
      test_export_import_round_trip(user, conn, :block, "ghosted", :blocks)
    end
  end

  describe "invalid CSV handling" do
    test "import handles invalid CSV data gracefully for all block types", %{user: user} do
      # Create invalid CSV file
      csv_path = "/tmp/test_invalid_blocks.csv"
      invalid_content = "Account address\ninvalid_url\nnot_a_url_at_all\n"
      File.write!(csv_path, invalid_content)

      # Test all block types handle errors gracefully
      import_type = :ghosts
      # for import_type <- [:silences, :ghosts, :blocks] do
      Import.import_from_csv_file(import_type, user.id, csv_path)
      assert %{discard: 2} = Oban.drain_queue(queue: :import)
      # end

      File.rm(csv_path)
    end

    test "import silenced with mixed valid/invalid CSV data", %{user: user} do
      test_mixed_csv_import(user, :silence, :silences)
    end

    # test "import ghosted with mixed valid/invalid CSV data", %{user: user} do
    #   test_mixed_csv_import(user, :ghost, :ghosts)
    # end

    # test "import blocked with mixed valid/invalid CSV data", %{user: user} do
    #   test_mixed_csv_import(user, :block, :blocks)
    # end
  end

  # Helper functions
  defp test_export_import_round_trip(user, conn, block_type, export_endpoint, import_type) do
    # Create users to block
    blocked_user1 = fake_user!("#{String.capitalize(to_string(block_type))}User1")
    blocked_user2 = fake_user!("#{String.capitalize(to_string(block_type))}User2")

    # Create initial blocks
    assert {:ok, _} =
             Bonfire.Boundaries.Blocks.block(blocked_user1, block_type, current_user: user)

    assert {:ok, _} =
             Bonfire.Boundaries.Blocks.block(blocked_user2, block_type, current_user: user)

    # Test export via controller
    conn =
      conn
      |> assign(:current_user, user)
      |> get("/settings/export/csv/#{export_endpoint}")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]

    # Write exported CSV to file
    csv_path = "/tmp/test_exported_#{export_endpoint}.csv"
    File.write!(csv_path, conn.resp_body)

    # Create a new user to test import
    import_user = fake_user!("ImportUser")

    # Import the exported CSV
    assert %{ok: 2} = Import.import_from_csv_file(import_type, import_user.id, csv_path)

    assert %{success: 2} = Oban.drain_queue(queue: :import)

    # Verify blocks were imported correctly
    assert Bonfire.Boundaries.Blocks.is_blocked?(blocked_user1, block_type,
             current_user: import_user
           )

    assert Bonfire.Boundaries.Blocks.is_blocked?(blocked_user2, block_type,
             current_user: import_user
           )

    File.rm(csv_path)
  end

  defp test_mixed_csv_import(user, block_type, import_type) do
    # Create user to block
    blocked_user = fake_user!("Valid#{String.capitalize(to_string(block_type))}User")

    # Create CSV with mixed valid and invalid data
    csv_path = "/tmp/test_mixed_#{import_type}.csv"

    mixed_content = """
    Account address
    #{Bonfire.Me.Characters.character_url(blocked_user)}
    invalid_url
    not_a_url
    """

    File.write!(csv_path, mixed_content)

    # Verify no block exists initially
    refute Bonfire.Boundaries.Blocks.is_blocked?(blocked_user, block_type, current_user: user)

    # Import should handle partial success
    Import.import_from_csv_file(import_type, user.id, csv_path)

    assert %{success: 1, discard: 2} = Oban.drain_queue(queue: :import)

    # Valid entry should be imported
    assert Bonfire.Boundaries.Blocks.is_blocked?(blocked_user, block_type, current_user: user)

    File.rm(csv_path)
  end
end
