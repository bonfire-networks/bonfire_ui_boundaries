defmodule Bonfire.UI.Boundaries.BlocklistUriTest do
  use Bonfire.UI.Boundaries.ConnCase, async: false
  @moduletag :ui
  import Tesla.Mock

  @remote_actor "https://mocked.local/users/karen"
  @remote_instance "mocked.local"

  setup do
    account = fake_account!()
    me = fake_user!(account)
    conn = conn(user: me, account: account)
    {:ok, conn: conn, me: me, account: account}
  end

  defp actor_json(uri) do
    %{
      "id" => uri,
      "type" => "Person",
      "preferredUsername" => "karen",
      "name" => "karen",
      "inbox" => uri <> "/inbox",
      "outbox" => uri <> "/outbox",
      "followers" => uri <> "/followers",
      "following" => uri <> "/following",
      "publicKey" => %{"id" => uri <> "#main-key", "owner" => uri, "publicKeyPem" => ""},
      "endpoints" => %{}
    }
  end

  defp nodeinfo_mock do
    mock(fn
      %{method: :get, url: "https://#{@remote_instance}/.well-known/nodeinfo"} ->
        json(%{
          "links" => [
            %{
              "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.1",
              "href" => "https://#{@remote_instance}/nodeinfo/2.1"
            }
          ]
        })

      %{method: :get, url: "https://#{@remote_instance}/nodeinfo/2.1"} ->
        json(%{"version" => "2.1", "software" => %{"name" => "test", "version" => "1.0"}})
    end)
  end

  describe "silence list" do
    test "user can add a local user by @handle", %{conn: conn, account: account} do
      alice = fake_user!(account)

      conn
      |> visit("/silenced")
      |> within("form#add_members_by_uri", fn s ->
        s
        |> fill_in("Actor URL, domain, or @handle@domain", with: "@#{alice.character.username}")
        |> click_button("Add")
      end)
      |> assert_has("li", text: alice.profile.name)
    end

    test "user can add a remote actor by URL", %{conn: conn} do
      mock(fn %{method: :get, url: @remote_actor} -> json(actor_json(@remote_actor)) end)

      conn
      |> visit("/silenced")
      |> within("form#add_members_by_uri", fn s ->
        s
        |> fill_in("Actor URL, domain, or @handle@domain", with: @remote_actor)
        |> click_button("Add")
      end)
      # the members list loads/refreshes async (renders skeletons first); wait for it to settle
      |> wait_async()
      |> assert_has("li", text: "karen")
      |> refute_has("li", text: "Unknown")
    end

    test "user can add a bare domain", %{conn: conn} do
      nodeinfo_mock()

      conn
      |> visit("/silenced")
      |> within("form#add_members_by_uri", fn s ->
        s
        |> fill_in("Actor URL, domain, or @handle@domain", with: @remote_instance)
        |> click_button("Add")
      end)
      |> assert_has("li", text: @remote_instance)
    end
  end

  describe "ghost list" do
    test "user can add a local user by @handle", %{conn: conn, account: account} do
      alice = fake_user!(account)

      conn
      |> visit("/ghosted")
      |> within("form#add_members_by_uri", fn s ->
        s
        |> fill_in("Actor URL, domain, or @handle@domain", with: "@#{alice.character.username}")
        |> click_button("Add")
      end)
      |> assert_has("li", text: alice.profile.name)
    end

    test "user can add a remote actor by URL", %{conn: conn} do
      mock(fn %{method: :get, url: @remote_actor} -> json(actor_json(@remote_actor)) end)

      conn
      |> visit("/ghosted")
      |> within("form#add_members_by_uri", fn s ->
        s
        |> fill_in("Actor URL, domain, or @handle@domain", with: @remote_actor)
        |> click_button("Add")
      end)
      # the members list loads/refreshes async (renders skeletons first); wait for it to settle
      |> wait_async()
      |> assert_has("li", text: "karen")
      |> refute_has("li", text: "Unknown")
    end
  end
end
