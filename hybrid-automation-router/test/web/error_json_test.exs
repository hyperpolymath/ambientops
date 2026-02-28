# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule HARWeb.ErrorJSONTest do
  @moduledoc """
  Tests for the HARWeb.ErrorJSON module.

  Verifies that JSON error responses render the correct status messages
  derived from the template name (e.g., "404.json" -> "Not Found").
  """

  use ExUnit.Case, async: true

  alias HARWeb.ErrorJSON

  describe "render/2" do
    test "renders 404.json with 'Not Found' detail" do
      result = ErrorJSON.render("404.json", %{})
      assert result == %{errors: %{detail: "Not Found"}}
    end

    test "renders 500.json with 'Internal Server Error' detail" do
      result = ErrorJSON.render("500.json", %{})
      assert result == %{errors: %{detail: "Internal Server Error"}}
    end

    test "renders 400.json with 'Bad Request' detail" do
      result = ErrorJSON.render("400.json", %{})
      assert result == %{errors: %{detail: "Bad Request"}}
    end

    test "renders 403.json with 'Forbidden' detail" do
      result = ErrorJSON.render("403.json", %{})
      assert result == %{errors: %{detail: "Forbidden"}}
    end

    test "renders 422.json with 'Unprocessable Content' detail" do
      result = ErrorJSON.render("422.json", %{})
      assert result == %{errors: %{detail: "Unprocessable Content"}}
    end

    test "renders 503.json with 'Service Unavailable' detail" do
      result = ErrorJSON.render("503.json", %{})
      assert result == %{errors: %{detail: "Service Unavailable"}}
    end
  end
end
