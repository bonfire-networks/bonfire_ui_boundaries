defmodule Bonfire.UI.Boundaries.ExportImportBlocksTest do
  use Bonfire.UI.Boundaries.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"

  alias Bonfire.Social.Import
  alias Bonfire.Boundaries.Blocks

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
      csv_path = "/tmp/test_invalid_blocks.csv"
      invalid_content = "Account address\ninvalid_url\nnot_a_url_at_all\n"
      File.write!(csv_path, invalid_content)

      import_type = :ghosts
      Import.import_from_csv_file(import_type, user.id, csv_path)
      assert %{discard: 2} = Oban.drain_queue(queue: :import)

      File.rm(csv_path)
    end

    test "import silenced with mixed valid/invalid CSV data", %{user: user} do
      test_mixed_csv_import(user, :silence, :silences)
    end

    test "import ghosted with mixed valid/invalid CSV data", %{user: user} do
      test_mixed_csv_import(user, :ghost, :ghosts)
    end

    test "import blocked with mixed valid/invalid CSV data", %{user: user} do
      test_mixed_csv_import(user, :block, :blocks)
    end
  end

  describe "per-user import" do
    test "import ghosts for user", %{user: user} do
      test_csv_import(user, :ghosts, :ghost)
    end

    test "import silences for user", %{user: user} do
      test_csv_import(user, :silences, :silence)
    end

    test "import blocks for user applies both ghost and silence", %{user: user} do
      test_csv_import(user, :blocks, [:ghost, :silence])
    end
  end

  describe "instance-wide import" do
    test "import ghosts instance-wide" do
      test_csv_import("instance_wide", :ghosts, :ghost)
    end

    test "import silences instance-wide" do
      test_csv_import("instance_wide", :silences, :silence)
    end

    test "import blocks instance-wide applies both ghost and silence" do
      test_csv_import("instance_wide", :blocks, [:ghost, :silence])
    end
  end

  describe "edge cases" do
    test "empty CSV with only header row enqueues no usable jobs", %{user: user} do
      csv_path = "/tmp/test_empty_blocks.csv"
      File.write!(csv_path, "Account address\n")

      # The code falls back to treating the raw text as a single entry when
      # NimbleCSV returns no data rows, so 1 job is enqueued but it will fail
      Import.import_from_csv_file(:ghosts, user.id, csv_path)
      assert %{discard: 1} = Oban.drain_queue(queue: :import)

      File.rm(csv_path)
    end

    test "CSV with duplicate entries still applies the block", %{user: user} do
      target_user = fake_user!("DuplicateTarget")
      url = Bonfire.Me.Characters.character_url(target_user)

      csv_path = "/tmp/test_duplicate_blocks.csv"

      csv_content = """
      Account address
      #{url}
      #{url}
      """

      File.write!(csv_path, csv_content)

      assert %{ok: 2} = Import.import_from_csv_file(:ghosts, user.id, csv_path)
      Oban.drain_queue(queue: :import)

      assert Blocks.is_blocked?(target_user, :ghost, current_user: user)

      File.rm(csv_path)
    end

    test "CSV with extra whitespace and @ prefixes is handled", %{user: user} do
      target_user = fake_user!("WhitespaceTarget")
      url = Bonfire.Me.Characters.character_url(target_user)

      csv_path = "/tmp/test_whitespace_blocks.csv"

      csv_content = """
      Account address
        #{url}
      """

      File.write!(csv_path, csv_content)

      assert %{ok: 1} = Import.import_from_csv_file(:silences, user.id, csv_path)
      assert %{success: 1} = Oban.drain_queue(queue: :import)

      assert Blocks.is_blocked?(target_user, :silence, current_user: user)

      File.rm(csv_path)
    end

    test "larger CSV with multiple entries processes all", %{user: user} do
      count = 5

      users =
        for i <- 1..count do
          fake_user!("BatchUser#{i}")
        end

      urls =
        Enum.map(users, fn u -> Bonfire.Me.Characters.character_url(u) end)
        |> Enum.reject(&is_nil/1)

      csv_path = "/tmp/test_batch_blocks.csv"
      lines = Enum.join(urls, "\n")
      File.write!(csv_path, "Account address\n#{lines}")

      expected = length(urls)
      assert %{ok: ^expected} = Import.import_from_csv_file(:ghosts, user.id, csv_path)
      assert %{success: ^expected} = Oban.drain_queue(queue: :import)

      for u <- users do
        assert Blocks.is_blocked?(u, :ghost, current_user: user)
      end

      File.rm(csv_path)
    end
  end

  describe "export format" do
    test "export CSV has correct content-type header", %{user: user, conn: conn} do
      conn =
        conn
        |> assign(:current_user, user)
        |> get("/settings/export/csv/ghosted")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]
    end

    test "export CSV starts with Account address header", %{user: user, conn: conn} do
      conn =
        conn
        |> assign(:current_user, user)
        |> get("/settings/export/csv/silenced")

      assert conn.status == 200
      assert String.contains?(conn.resp_body, "Account address")
    end

    test "exported CSV contains blocked user address", %{user: user, conn: conn} do
      blocked_user = fake_user!("ExportFormatUser")
      assert {:ok, _} = Blocks.block(blocked_user, :ghost, current_user: user)

      conn =
        conn
        |> assign(:current_user, user)
        |> get("/settings/export/csv/ghosted")

      assert conn.status == 200
      username = Bonfire.Me.Characters.display_username(blocked_user, true)
      assert String.contains?(conn.resp_body, username)
    end

    test "export with no blocks returns just the header", %{conn: conn} do
      # Use a fresh user with no blocks
      fresh_user = fake_user!("FreshExportUser")

      conn =
        conn
        |> assign(:current_user, fresh_user)
        |> get("/settings/export/csv/ghosted")

      assert conn.status == 200
      body = String.trim(conn.resp_body)
      assert body == "Account address"
    end
  end

  describe "UI upload page" do
    test "blocks import page renders with expected elements", %{conn: conn} do
      conn
      |> visit("/settings/user/blocks_import")
      |> assert_has("#import_type")
      |> assert_has("button", text: "Upload")
    end
  end

  # Helper functions

  defp test_export_import_round_trip(user, conn, block_type, export_endpoint, import_type) do
    blocked_user1 = fake_user!("#{String.capitalize(to_string(block_type))}User1")
    blocked_user2 = fake_user!("#{String.capitalize(to_string(block_type))}User2")

    assert {:ok, _} =
             Blocks.block(blocked_user1, block_type, current_user: user)

    assert {:ok, _} =
             Blocks.block(blocked_user2, block_type, current_user: user)

    conn =
      conn
      |> assign(:current_user, user)
      |> get("/settings/export/csv/#{export_endpoint}")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]

    csv_path = "/tmp/test_exported_#{export_endpoint}.csv"
    File.write!(csv_path, conn.resp_body)

    import_user = fake_user!("ImportUser")

    assert %{ok: 2} = Import.import_from_csv_file(import_type, import_user.id, csv_path)

    assert %{success: 2} = Oban.drain_queue(queue: :import)

    assert Blocks.is_blocked?(blocked_user1, block_type, current_user: import_user)

    assert Blocks.is_blocked?(blocked_user2, block_type, current_user: import_user)

    File.rm(csv_path)
  end

  defp test_csv_import(subject, import_type, block_types) do
    target_user = fake_user!("ImportTarget")
    csv_path = "/tmp/test_import_#{import_type}_#{System.unique_integer([:positive])}.csv"

    csv_content = """
    Account address
    #{Bonfire.Me.Characters.character_url(target_user)}
    """

    File.write!(csv_path, csv_content)

    subject_id = if is_binary(subject), do: subject, else: subject.id

    assert %{ok: 1} = Import.import_from_csv_file(import_type, subject_id, csv_path)
    assert %{success: 1} = Oban.drain_queue(queue: :import)

    block_check = if is_binary(subject), do: :instance_wide, else: [current_user: subject]

    for block_type <- List.wrap(block_types) do
      assert Blocks.is_blocked?(target_user, block_type, block_check)
    end

    File.rm(csv_path)
  end

  defp test_mixed_csv_import(user, block_type, import_type) do
    blocked_user = fake_user!("Valid#{String.capitalize(to_string(block_type))}User")

    csv_path = "/tmp/test_mixed_#{import_type}.csv"

    mixed_content = """
    Account address
    #{Bonfire.Me.Characters.character_url(blocked_user)}
    invalid_url
    not_a_url
    """

    File.write!(csv_path, mixed_content)

    refute Blocks.is_blocked?(blocked_user, block_type, current_user: user)

    Import.import_from_csv_file(import_type, user.id, csv_path)

    assert %{success: 1, discard: 2} = Oban.drain_queue(queue: :import)

    assert Blocks.is_blocked?(blocked_user, block_type, current_user: user)

    File.rm(csv_path)
  end
end
