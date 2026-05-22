# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule HARWeb.TransformControllerTest do
  @moduledoc """
  Tests for the HARWeb.TransformController module.

  Exercises all three API endpoints:
    - POST /api/transform  (transform action)
    - POST /api/parse      (parse action)
    - GET  /api/formats    (formats action)

  Tests verify HTTP status codes, JSON response structure, and error handling
  for invalid inputs. Runs async: false because the HAR application's
  HealthChecker GenServer state needs per-test setup.
  """

  use ExUnit.Case, async: false

  import Plug.Conn
  import Phoenix.ConnTest

  alias HAR.ControlPlane.HealthChecker

  @endpoint HARWeb.Endpoint

  setup do
    # Register all backends from the routing table as healthy so that
    # the control plane routing step inside transform/parse succeeds.
    routes = HAR.ControlPlane.RoutingTable.get_routes()

    for route <- routes, backend <- route.backends do
      HealthChecker.register_backend(backend)
      HealthChecker.set_health(backend, :healthy)
    end

    Process.sleep(50)
    :ok
  end

  # ------------------------------------------------------------------
  # GET /api/formats
  # ------------------------------------------------------------------

  describe "GET /api/formats" do
    test "returns 200 with list of supported formats" do
      conn =
        build_conn()
        |> get("/api/formats")

      assert json_response(conn, 200)
      body = json_response(conn, 200)
      assert is_list(body["formats"])
      assert length(body["formats"]) > 0
    end

    test "each format entry has id, name, and description" do
      conn =
        build_conn()
        |> get("/api/formats")

      body = json_response(conn, 200)

      for fmt <- body["formats"] do
        assert Map.has_key?(fmt, "id"), "format entry missing 'id'"
        assert Map.has_key?(fmt, "name"), "format entry missing 'name'"
        assert Map.has_key?(fmt, "description"), "format entry missing 'description'"
      end
    end

    test "includes all 9 expected formats" do
      conn =
        build_conn()
        |> get("/api/formats")

      body = json_response(conn, 200)
      ids = Enum.map(body["formats"], & &1["id"])

      for expected <- ~w(ansible salt terraform puppet chef kubernetes docker_compose cloudformation pulumi) do
        assert expected in ids, "expected format '#{expected}' in #{inspect(ids)}"
      end
    end
  end

  # ------------------------------------------------------------------
  # POST /api/transform - success cases
  # ------------------------------------------------------------------

  describe "POST /api/transform - success" do
    test "transforms Ansible to Salt and returns 200" do
      params = %{
        "source_format" => "ansible",
        "target_format" => "salt",
        "content" => ansible_sample()
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/transform", params)

      body = json_response(conn, 200)
      assert body["success"] == true
      assert is_binary(body["output"])
      assert is_map(body["graph"])
      assert is_integer(body["graph"]["operations"])
      assert is_integer(body["graph"]["dependencies"])
    end

    test "transform response includes operation types in graph summary" do
      params = %{
        "source_format" => "ansible",
        "target_format" => "salt",
        "content" => ansible_sample()
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/transform", params)

      body = json_response(conn, 200)
      assert is_list(body["graph"]["operation_types"])
    end
  end

  # ------------------------------------------------------------------
  # POST /api/transform - error cases
  # ------------------------------------------------------------------

  describe "POST /api/transform - errors" do
    test "returns 400 when source_format is missing" do
      params = %{
        "target_format" => "salt",
        "content" => "some content"
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/transform", params)

      body = json_response(conn, 400)
      assert body["success"] == false
      assert body["error"] =~ "source_format"
    end

    test "returns 400 when target_format is missing" do
      params = %{
        "source_format" => "ansible",
        "content" => "some content"
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/transform", params)

      body = json_response(conn, 400)
      assert body["success"] == false
      assert body["error"] =~ "target_format"
    end

    test "returns 400 when content is missing" do
      params = %{
        "source_format" => "ansible",
        "target_format" => "salt"
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/transform", params)

      body = json_response(conn, 400)
      assert body["success"] == false
      assert body["error"] =~ "content"
    end

    test "returns 400 when content is empty string" do
      params = %{
        "source_format" => "ansible",
        "target_format" => "salt",
        "content" => ""
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/transform", params)

      body = json_response(conn, 400)
      assert body["success"] == false
      assert body["error"] =~ "content"
    end

    test "returns 400 for unsupported source format" do
      params = %{
        "source_format" => "nonexistent_format",
        "target_format" => "salt",
        "content" => "some content"
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/transform", params)

      body = json_response(conn, 400)
      assert body["success"] == false
      assert body["error"] =~ "Invalid source_format"
    end

    test "returns 400 for unsupported target format" do
      params = %{
        "source_format" => "ansible",
        "target_format" => "nonexistent_format",
        "content" => "some content"
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/transform", params)

      body = json_response(conn, 400)
      assert body["success"] == false
      assert body["error"] =~ "Invalid target_format"
    end
  end

  # ------------------------------------------------------------------
  # POST /api/parse - success cases
  # ------------------------------------------------------------------

  describe "POST /api/parse - success" do
    test "parses Ansible content and returns graph details" do
      params = %{
        "format" => "ansible",
        "content" => ansible_sample()
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/parse", params)

      body = json_response(conn, 200)
      assert body["success"] == true
      assert is_map(body["graph"])
      assert is_integer(body["graph"]["operations"])
      assert is_integer(body["graph"]["dependencies"])
      assert is_list(body["graph"]["vertices"])
      assert is_list(body["graph"]["edges"])
    end

    test "parse response vertices have id, type, params, and target" do
      params = %{
        "format" => "ansible",
        "content" => ansible_sample()
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/parse", params)

      body = json_response(conn, 200)

      for vertex <- body["graph"]["vertices"] do
        assert Map.has_key?(vertex, "id"), "vertex missing 'id'"
        assert Map.has_key?(vertex, "type"), "vertex missing 'type'"
        assert Map.has_key?(vertex, "params"), "vertex missing 'params'"
        assert Map.has_key?(vertex, "target"), "vertex missing 'target'"
      end
    end
  end

  # ------------------------------------------------------------------
  # POST /api/parse - error cases
  # ------------------------------------------------------------------

  describe "POST /api/parse - errors" do
    test "returns 400 when format is missing" do
      params = %{"content" => "some content"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/parse", params)

      body = json_response(conn, 400)
      assert body["success"] == false
      assert body["error"] =~ "format"
    end

    test "returns 400 when content is missing" do
      params = %{"format" => "ansible"}

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/parse", params)

      body = json_response(conn, 400)
      assert body["success"] == false
      assert body["error"] =~ "content"
    end

    test "returns 400 for unsupported format" do
      params = %{
        "format" => "nonexistent_format",
        "content" => "some content"
      }

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/parse", params)

      body = json_response(conn, 400)
      assert body["success"] == false
      assert body["error"] =~ "Invalid format"
    end
  end

  # ------------------------------------------------------------------
  # Sample data helpers
  # ------------------------------------------------------------------

  defp ansible_sample do
    """
    - hosts: webservers
      tasks:
        - name: Install nginx
          apt:
            name: nginx
            state: present

        - name: Start nginx service
          service:
            name: nginx
            state: started
            enabled: true
    """
  end
end
