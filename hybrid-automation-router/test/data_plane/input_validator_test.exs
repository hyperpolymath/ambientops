# SPDX-License-Identifier: MPL-2.0
#
# Tests for HAR.DataPlane.InputValidator — pre-parser defence layer.
#
# Validates that the input validator correctly rejects dangerous content
# (oversized input, YAML bombs, template injection, excessive nesting)
# before any parser touches the raw configuration string.
#
# Part of the Hybrid Automation Router (HAR) project.
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

defmodule HAR.DataPlane.InputValidatorTest do
  @moduledoc """
  Tests for the HAR.DataPlane.InputValidator module.

  All tests are stateless (pure function calls returning ok/error tuples),
  so they run in parallel with `async: true`. No GenServer or supervision
  tree dependencies.

  The test suite covers all four validation checks in the order they
  execute in the pipeline:

    1. Size check — byte_size against configurable max_size
    2. YAML bomb detection — alias counting and anchor:alias ratio
    3. Template injection — Jinja2, ERB, and HCL pattern detection
    4. Nesting depth — indentation-based and brace-based depth estimation

  Each describe block maps to one check, plus an edge-cases block for
  boundary conditions that span multiple checks.
  """

  use ExUnit.Case, async: true

  alias HAR.DataPlane.InputValidator

  # ---------------------------------------------------------------------------
  # Test Helpers
  # ---------------------------------------------------------------------------

  # Default max_size used by the module (10 MB = 10,485,760 bytes).
  # Duplicated here so tests can construct inputs relative to the threshold
  # without importing module attributes.
  @default_max_size 10_485_760

  # Default max YAML alias count.
  @default_max_aliases 100

  # ---------------------------------------------------------------------------
  # 1. Size Checks
  # ---------------------------------------------------------------------------

  describe "validate/2 — size checks" do
    test "normal input passes validation" do
      input = "packages:\n  - nginx\n  - redis\n"

      assert {:ok, ^input} = InputValidator.validate(input)
    end

    test "input at exact max_size passes" do
      # Build a string that is exactly @default_max_size bytes.
      # Use plain ASCII so byte_size == String.length.
      input = String.duplicate("x", @default_max_size)

      assert {:ok, ^input} = InputValidator.validate(input)
    end

    test "input 1 byte over max_size fails with 'Input too large'" do
      input = String.duplicate("x", @default_max_size + 1)

      assert {:error, reason} = InputValidator.validate(input)
      assert reason =~ "Input too large"
      assert reason =~ "#{@default_max_size + 1}"
      assert reason =~ "#{@default_max_size}"
    end

    test "custom max_size option is respected" do
      small_limit = 64
      input_under = String.duplicate("a", small_limit)
      input_over = String.duplicate("a", small_limit + 1)

      assert {:ok, ^input_under} = InputValidator.validate(input_under, max_size: small_limit)
      assert {:error, reason} = InputValidator.validate(input_over, max_size: small_limit)
      assert reason =~ "Input too large"
    end
  end

  # ---------------------------------------------------------------------------
  # 2. YAML Bomb Detection
  # ---------------------------------------------------------------------------

  describe "validate/2 — YAML bomb detection" do
    test "normal YAML with few anchors and aliases passes" do
      # 3 anchors and 3 aliases — well within thresholds
      input = """
      defaults: &defaults
        adapter: postgres
        host: localhost

      development:
        <<: *defaults
        database: dev_db

      test:
        <<: *defaults
        database: test_db

      production:
        <<: *defaults
        database: prod_db
      """

      assert {:ok, _} = InputValidator.validate(input)
    end

    test "input with 101 aliases fails at default threshold" do
      # Build input with 101 YAML aliases (*alias_N) and a single anchor.
      # The absolute count (101) exceeds the default max of 100.
      anchor_line = "&shared_config value\n"

      alias_lines =
        Enum.map_join(1..101, "\n", fn i ->
          "key_#{i}: *shared_config"
        end)

      input = anchor_line <> alias_lines

      assert {:error, reason} = InputValidator.validate(input)
      assert reason =~ "Too many YAML aliases" or reason =~ "Suspicious anchor/alias ratio"
    end

    test "custom max_aliases option is respected" do
      # 5 aliases with max_aliases: 3 should fail; with max_aliases: 10 should pass.
      anchor = "&base value\n"

      alias_lines =
        Enum.map_join(1..5, "\n", fn i ->
          "entry_#{i}: *base"
        end)

      input = anchor <> alias_lines

      assert {:error, _} = InputValidator.validate(input, max_aliases: 3)
      assert {:ok, _} = InputValidator.validate(input, max_aliases: 10)
    end

    test "suspicious anchor:alias ratio (2 anchors, 25 aliases) fails" do
      # 2 anchors and 25 aliases → ratio 12.5:1, exceeds 10:1 threshold.
      # Absolute count (25) is under 100, so this tests the ratio check.
      anchors = "&anchor_a val_a\n&anchor_b val_b\n"

      alias_lines =
        Enum.map_join(1..25, "\n", fn i ->
          "item_#{i}: *anchor_a"
        end)

      input = anchors <> alias_lines

      assert {:error, reason} = InputValidator.validate(input)
      assert reason =~ "Suspicious anchor/alias ratio"
    end

    test "ratio check passes when ratio is under 10:1 (10 anchors, 50 aliases)" do
      # 10 anchors and 50 aliases → ratio 5:1, under the 10:1 threshold.
      # Absolute count (50) is under 100. Both checks pass.
      anchors =
        Enum.map_join(1..10, "\n", fn i ->
          "&anchor_#{i} value_#{i}"
        end)

      alias_lines =
        Enum.map_join(1..50, "\n", fn i ->
          anchor_ref = "anchor_#{rem(i, 10) + 1}"
          "ref_#{i}: *#{anchor_ref}"
        end)

      input = anchors <> "\n" <> alias_lines

      assert {:ok, _} = InputValidator.validate(input)
    end

    test "no anchors with many aliases: only absolute count matters" do
      # 0 anchors, 50 aliases. The ratio check requires anchor_count > 0,
      # so it does not trigger. The absolute count (50) is under 100, so
      # this should pass.
      alias_lines =
        Enum.map_join(1..50, "\n", fn i ->
          "ref_#{i}: *some_alias"
        end)

      input = alias_lines

      assert {:ok, _} = InputValidator.validate(input)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Template Injection Detection
  # ---------------------------------------------------------------------------

  describe "validate/2 — template injection" do
    test "clean YAML without template directives passes" do
      input = """
      web_server:
        package: nginx
        version: "1.24"
        config:
          worker_processes: auto
          events:
            worker_connections: 1024
      """

      assert {:ok, _} = InputValidator.validate(input)
    end

    test "Jinja2 system() call is detected" do
      input = "command: {{ system('rm -rf /') }}"

      assert {:error, reason} = InputValidator.validate(input)
      assert reason =~ "Jinja2 code execution"
    end

    test "Jinja2 import statement is detected" do
      input = "payload: {{ import os }}"

      assert {:error, reason} = InputValidator.validate(input)
      assert reason =~ "Jinja2 code execution"
    end

    test "ERB system() call is detected" do
      input = "value: <%= system('whoami') %>"

      assert {:error, reason} = InputValidator.validate(input)
      assert reason =~ "ERB code execution"
    end

    test "ERB backtick execution is detected" do
      input = "value: <%= `ls` %>"

      assert {:error, reason} = InputValidator.validate(input)
      assert reason =~ "ERB code execution"
    end

    test "HCL file() function injection is detected" do
      input = ~s[secret = ${ file("/etc/shadow") }]

      assert {:error, reason} = InputValidator.validate(input)
      assert reason =~ "HCL function injection"
    end

    test "HCL templatefile() function injection is detected" do
      input = ~s[config = ${ templatefile("evil.tpl") }]

      assert {:error, reason} = InputValidator.validate(input)
      assert reason =~ "HCL function injection"
    end

    test "safe template syntax without dangerous functions passes" do
      # {{ variable_name }} — looks like Jinja2 but contains no dangerous
      # function name (import, exec, eval, system, popen). The regex only
      # fires when a dangerous function keyword is present inside the
      # mustache braces.
      input = "greeting: {{ user_name }}"

      assert {:ok, _} = InputValidator.validate(input)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Nesting Depth Checks
  # ---------------------------------------------------------------------------

  describe "validate/2 — nesting depth" do
    test "shallow YAML (5 levels indentation) passes" do
      # 5 levels of 2-space indentation = 10 leading spaces on deepest line.
      input =
        Enum.reduce(0..4, "", fn level, acc ->
          indent = String.duplicate("  ", level)
          acc <> indent <> "level_#{level}:\n"
        end) <> String.duplicate("  ", 5) <> "value: leaf\n"

      assert {:ok, _} = InputValidator.validate(input)
    end

    test "deep YAML (60 levels indentation) fails" do
      # 60 levels of 2-space indentation = 120 leading spaces on deepest line.
      # Exceeds the default max_nesting_depth of 50.
      input =
        Enum.map_join(0..59, "\n", fn level ->
          indent = String.duplicate("  ", level)
          indent <> "level_#{level}:"
        end) <> "\n" <> String.duplicate("  ", 60) <> "value: deep_leaf\n"

      assert {:error, reason} = InputValidator.validate(input)
      assert reason =~ "Nesting too deep"
    end

    test "deep JSON (55 nested braces) fails" do
      # 55 nested opening braces followed by 55 closing braces.
      # Brace depth 55 exceeds the default max_nesting_depth of 50.
      opening = String.duplicate("{", 55)
      closing = String.duplicate("}", 55)
      input = opening <> "\"leaf\": true" <> closing

      assert {:error, reason} = InputValidator.validate(input)
      assert reason =~ "Nesting too deep"
    end

    test "shallow JSON passes" do
      input = ~s({"a": {"b": {"c": {"d": "value"}}}})

      assert {:ok, _} = InputValidator.validate(input)
    end

    test "combined moderate indent and moderate braces under threshold passes" do
      # 20 indent levels (indentation depth = 20) and 20 brace levels
      # (brace depth = 20). The effective depth is max(20, 20) = 20,
      # which is well under the 50-level threshold.
      indent_part =
        Enum.map_join(0..19, "\n", fn level ->
          String.duplicate("  ", level) <> "key_#{level}:"
        end)

      brace_part = String.duplicate("{", 20) <> "\"v\":1" <> String.duplicate("}", 20)

      input = indent_part <> "\n" <> brace_part

      assert {:ok, _} = InputValidator.validate(input)
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Edge Cases
  # ---------------------------------------------------------------------------

  describe "validate/2 — edge cases" do
    test "empty string passes" do
      assert {:ok, ""} = InputValidator.validate("")
    end

    test "whitespace-only string passes" do
      input = "   \n\n  \t  \n  "

      assert {:ok, ^input} = InputValidator.validate(input)
    end

    test "binary data with non-UTF8-looking bytes passes size check" do
      # Construct a binary that contains bytes outside typical ASCII/UTF8
      # text ranges. It should still pass the size check (byte_size is
      # format-agnostic). Whether subsequent checks match regex patterns
      # is secondary — the key invariant is that it does not crash.
      input = <<0xFF, 0xFE, 0x00, 0x01, 0x80, 0xBF, 0xC0>>

      # Should not raise; may return ok or error depending on pattern matches.
      # The critical assertion is that no exception is thrown.
      result = InputValidator.validate(input)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "valid input passes all checks together" do
      # A realistic Ansible-style YAML snippet that exercises multiple
      # checks simultaneously: moderate size, a few anchors/aliases,
      # no template injection, moderate nesting.
      input = """
      ---
      defaults: &pkg_defaults
        state: present
        update_cache: yes

      - hosts: webservers
        become: yes
        tasks:
          - name: Install nginx
            apt:
              <<: *pkg_defaults
              name: nginx

          - name: Install redis
            apt:
              <<: *pkg_defaults
              name: redis

          - name: Configure nginx
            template:
              src: templates/nginx.conf.j2
              dest: /etc/nginx/nginx.conf
              mode: '0644'

          - name: Start nginx service
            service:
              name: nginx
              state: started
              enabled: yes
      """

      assert {:ok, ^input} = InputValidator.validate(input)
    end
  end
end
