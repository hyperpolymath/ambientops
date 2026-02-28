# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule HARWeb.ErrorHTMLTest do
  @moduledoc """
  Tests for the HARWeb.ErrorHTML module.

  Verifies that HTML error responses render plain-text status messages
  derived from the template name (e.g., "404.html" -> "Not Found").
  """

  use ExUnit.Case, async: true

  alias HARWeb.ErrorHTML

  describe "render/2" do
    test "renders 404.html as 'Not Found'" do
      result = ErrorHTML.render("404.html", %{})
      assert result == "Not Found"
    end

    test "renders 500.html as 'Internal Server Error'" do
      result = ErrorHTML.render("500.html", %{})
      assert result == "Internal Server Error"
    end

    test "renders 400.html as 'Bad Request'" do
      result = ErrorHTML.render("400.html", %{})
      assert result == "Bad Request"
    end

    test "renders 403.html as 'Forbidden'" do
      result = ErrorHTML.render("403.html", %{})
      assert result == "Forbidden"
    end
  end
end
