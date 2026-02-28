# SPDX-License-Identifier: PMPL-1.0-or-later
#
# HAR.DataPlane.InputValidator — pre-parser defence layer for IaC config input.
#
# Part of the Hybrid Automation Router (HAR) project.
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

defmodule HAR.DataPlane.InputValidator do
  @moduledoc """
  Validates and sanitises incoming IaC configuration input before parsing.

  This module is the first line of defence in the data plane pipeline. It
  runs BEFORE any parser (YAML, HCL, JSON, etc.) touches the input, rejecting
  dangerous content at the gate. This is critical because parser vulnerabilities
  are a common attack vector — if malicious input reaches the parser, it may
  already be too late.

  ## Threat Model

  The validator defends against four categories of attack:

  ### 1. YAML Bombs (Billion Laughs Attack)

  YAML anchors (`&anchor`) and aliases (`*alias`) enable a classic exponential
  expansion attack. A small YAML file can reference itself recursively:

      a: &a ["lol","lol","lol","lol","lol","lol","lol","lol","lol"]
      b: &b [*a,*a,*a,*a,*a,*a,*a,*a,*a]
      c: &c [*b,*b,*b,*b,*b,*b,*b,*b,*b]

  Each level multiplies the data by 9x. With 10 levels, a 1KB input expands
  to 9^10 = 3.5 billion elements, consuming gigabytes of memory and crashing
  the parser process (and potentially the BEAM VM).

  The validator counts YAML aliases and rejects input exceeding a configurable
  threshold (default: 100). It also checks the anchor-to-alias ratio — a
  suspicious ratio (many more aliases than anchors) indicates an expansion
  attack even if the absolute count is below threshold.

  ### 2. Oversized Input

  IaC configs exceeding reasonable size limits could OOM the parser process.
  Production configs rarely exceed 1 MB; the default limit is 10 MB to allow
  headroom for machine-generated configs while preventing memory exhaustion.

  ### 3. Template Injection

  Many IaC tools support template expansion during parsing:
  - **Jinja2** (`{{ }}`) — Used by Ansible, Salt. Dangerous functions:
    `import`, `exec`, `eval`, `system`, `popen`.
  - **ERB** (`<%= %>`) — Used by Puppet, Chef. Dangerous: `system`, `exec`,
    `` `backticks` ``, `eval`.
  - **HCL** (`${ }`) — Used by Terraform. Dangerous functions: `file`,
    `templatefile`, `base64decode` (can leak local files).

  If the parser supports template expansion (e.g., Ansible's Jinja2 renderer),
  these patterns can execute arbitrary code during parsing. The validator
  detects and rejects configs containing these dangerous patterns.

  ### 4. Excessive Nesting Depth

  Deeply nested configs can:
  - Stack-overflow recursive parsers
  - Create pathological data structures that slow downstream processing
  - Exploit quadratic-time algorithms in tree traversal

  The validator estimates nesting depth by counting indentation levels (for
  YAML) and brace depth (for JSON/HCL), rejecting input exceeding a
  configurable threshold (default: 50 levels).

  ## Usage in the Pipeline

  The validator sits at the entry point of the data plane, before any
  format-specific parser:

      Raw Input → InputValidator.validate/2 → Parser → Semantic Graph

  If validation fails, the parser is never invoked, and an error tuple
  is returned to the caller with a human-readable reason.

  ## Configuration

  All thresholds are configurable via the `opts` keyword list:

  | Option          | Default    | Description                              |
  |-----------------|------------|------------------------------------------|
  | `:max_size`     | 10 MB      | Maximum input size in bytes              |
  | `:max_aliases`  | 100        | Maximum YAML alias count                 |
  | `:format`       | `:unknown` | Format hint for format-specific checks   |

  ## Performance

  All checks are O(n) in the input size (single pass with regex scanning).
  The nesting depth check uses a line-by-line scan, not a full parse.
  Total overhead is typically <1ms for a 100KB input.
  """

  require Logger

  # ---------------------------------------------------------------------------
  # Configuration Constants
  # ---------------------------------------------------------------------------

  # Maximum input size in bytes (10 MB default).
  #
  # Rationale: Production IaC configs rarely exceed 1 MB. The 10 MB limit
  # provides 10x headroom for machine-generated configs (e.g., Terraform
  # plans with thousands of resources) while preventing memory exhaustion
  # attacks. If a legitimate config exceeds this, the caller can override
  # via the :max_size option.
  @max_input_size 10_485_760

  # Maximum YAML alias count.
  #
  # YAML anchors (&anchor) and aliases (*alias) enable the billion laughs
  # attack where N aliases each referencing the previous creates 2^N
  # expansion. Limiting aliases to 100 prevents this while still allowing
  # legitimate use of YAML anchors for config deduplication (most real
  # configs use fewer than 20 anchors).
  @max_yaml_aliases 100

  # Maximum nesting depth for any structured config format.
  #
  # Deeply nested configs can stack-overflow parsers or create pathological
  # data structures that degrade performance in downstream processing.
  # 50 levels is far beyond any reasonable config structure (most are <10
  # levels deep) while avoiding false positives on generated configs.
  @max_nesting_depth 50

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Validate raw input string before parsing.

  Runs all safety checks against the input and returns `{:ok, input}` if
  the input passes all checks, or `{:error, reason}` with a human-readable
  error message if any check fails.

  Checks are run in order of computational cost (cheapest first):
  1. Size check — O(1), just reads byte_size
  2. YAML bomb detection — O(n), regex scan for anchors/aliases
  3. Template injection — O(n), regex scan for dangerous patterns
  4. Nesting depth — O(n), line-by-line indentation analysis

  If any check fails, subsequent checks are skipped (fail-fast). This is
  both a performance optimization and a security measure — if the input
  is dangerously large, we shouldn't spend CPU time scanning it for
  template injection.

  ## Parameters

    - `input` — Raw configuration string (binary). Must be a valid Elixir
      binary (UTF-8 or ASCII).
    - `opts` — Keyword list of validation options:
      - `:max_size` — Maximum byte size. Default: 10 MB (10,485,760 bytes).
      - `:max_aliases` — Maximum YAML alias count. Default: 100.
      - `:format` — Expected format hint. One of `:yaml`, `:hcl`, `:json`,
        or `:unknown`. Used for format-specific checks (currently affects
        template injection detection). Default: `:unknown`.

  ## Returns

    - `{:ok, input}` — Input passes all checks; safe to parse.
    - `{:error, reason}` — Input failed a check. `reason` is a human-readable
      string describing the failure (e.g., "Input too large: 15000000 bytes
      (max 10485760)").

  ## Examples

      iex> InputValidator.validate("packages:\\n  - nginx\\n")
      {:ok, "packages:\\n  - nginx\\n"}

      iex> InputValidator.validate(String.duplicate("x", 20_000_000))
      {:error, "Input too large: 20000000 bytes (max 10485760)"}

      iex> InputValidator.validate("a: *bomb *bomb *bomb ...", max_aliases: 2)
      {:error, "Too many YAML aliases: 3 (max 2)"}
  """
  @spec validate(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def validate(input, opts \\ []) when is_binary(input) do
    max_size = Keyword.get(opts, :max_size, @max_input_size)
    max_aliases = Keyword.get(opts, :max_aliases, @max_yaml_aliases)
    format = Keyword.get(opts, :format, :unknown)

    # Run checks in order of computational cost (cheapest first).
    # The `with` macro short-circuits on the first non-:ok result,
    # so expensive checks are skipped if a cheap check already fails.
    with :ok <- check_size(input, max_size),
         :ok <- check_yaml_bombs(input, max_aliases),
         :ok <- check_template_injection(input, format),
         :ok <- check_nesting_depth(input) do
      {:ok, input}
    end
  end

  # ---------------------------------------------------------------------------
  # Private Check Functions
  # ---------------------------------------------------------------------------

  # Check 1: Reject input exceeding maximum byte size.
  #
  # This is O(1) because byte_size/1 reads a field from the binary header,
  # not by scanning the content. It's the cheapest check, so it runs first.
  defp check_size(input, max_size) do
    size = byte_size(input)

    if size > max_size do
      Logger.warning("Input rejected: size #{size} exceeds limit #{max_size}")
      {:error, "Input too large: #{size} bytes (max #{max_size})"}
    else
      :ok
    end
  end

  # Check 2: Detect YAML billion laughs attack via anchor/alias counting.
  #
  # The attack uses YAML anchors (&a) to create named values and aliases
  # (*a) to reference them. By chaining references, each level doubles
  # (or more) the data:
  #
  #   &a "lol"       # 3 bytes
  #   &b [*a, *a]    # 6 bytes
  #   &c [*b, *b]    # 12 bytes
  #   &d [*c, *c]    # 24 bytes
  #   ...
  #   &z [*y, *y]    # 3 * 2^25 = 100 MB
  #
  # Two detection heuristics:
  # 1. Absolute alias count > max_aliases (default 100)
  # 2. Suspicious alias-to-anchor ratio (>10:1) — many more references
  #    than definitions suggests exponential expansion
  defp check_yaml_bombs(input, max_aliases) do
    alias_count = length(Regex.scan(~r/\*[a-zA-Z_][a-zA-Z0-9_]*/, input))
    anchor_count = length(Regex.scan(~r/&[a-zA-Z_][a-zA-Z0-9_]*/, input))

    cond do
      alias_count > max_aliases ->
        Logger.warning("YAML bomb detected: #{alias_count} aliases (max #{max_aliases})")
        {:error, "Too many YAML aliases: #{alias_count} (max #{max_aliases})"}

      anchor_count > 0 and alias_count > anchor_count * 10 ->
        # Suspicious ratio: many more aliases than anchors suggests an
        # expansion attack. In legitimate configs, the ratio is typically
        # 1:1 to 1:5 (each anchor referenced a few times for deduplication).
        # A ratio above 10:1 is almost certainly malicious.
        Logger.warning("YAML bomb suspected: #{anchor_count} anchors, #{alias_count} aliases")
        {:error, "Suspicious anchor/alias ratio: #{anchor_count}:#{alias_count}"}

      true ->
        :ok
    end
  end

  # Check 3: Detect template injection attempts in config input.
  #
  # Many IaC tools support template expansion during parsing. If the input
  # contains template directives with dangerous function calls, it could
  # execute arbitrary code when the parser processes it.
  #
  # Three template syntaxes are checked:
  # - Jinja2 ({{ }}) — Ansible, Salt. Functions: import, exec, eval, system, popen.
  # - ERB (<%= %>) — Puppet, Chef. Functions: system, exec, eval, backtick execution.
  # - HCL (${ }) — Terraform. Functions: file, templatefile, base64decode.
  #
  # The `format` parameter is accepted for future use (e.g., only checking
  # Jinja2 patterns for YAML input, only HCL patterns for .tf files) but
  # currently all patterns are checked regardless of format for maximum
  # defence in depth.
  defp check_template_injection(input, _format) do
    dangerous_patterns = [
      {~r/\{\{.*?(import|exec|eval|system|popen).*?\}\}/, "Jinja2 code execution"},
      {~r/<%.*?(system|exec|eval|`.*`).*?%>/, "ERB code execution"},
      {~r/\$\{.*?(file|templatefile|base64decode).*?\}/, "HCL function injection"}
    ]

    case Enum.find(dangerous_patterns, fn {pattern, _desc} ->
           Regex.match?(pattern, input)
         end) do
      {_pattern, description} ->
        Logger.warning("Template injection detected: #{description}")
        {:error, "Dangerous template pattern detected: #{description}"}

      nil ->
        :ok
    end
  end

  # Check 4: Estimate nesting depth and reject excessively deep configs.
  #
  # Two complementary methods are used:
  #
  # 1. **Indentation depth** (for YAML, Python-like formats): Count leading
  #    spaces on each line and divide by the typical indent width (2 spaces).
  #    The maximum across all lines gives the deepest nesting level.
  #
  # 2. **Brace depth** (for JSON, HCL, Terraform): Track the running depth
  #    of `{`, `[` (increment) and `}`, `]` (decrement). The maximum depth
  #    reached during the scan gives the deepest nesting level.
  #
  # The effective depth is the maximum of both methods, since a config file
  # might use either or both styles.
  defp check_nesting_depth(input) do
    # Method 1: Indentation-based depth (YAML / whitespace-significant formats).
    # Scan each line, count leading spaces, divide by 2 (standard indent width).
    max_indent_depth =
      input
      |> String.split("\n")
      |> Enum.reduce(0, fn line, max_so_far ->
        spaces = String.length(line) - String.length(String.trim_leading(line))
        depth = div(spaces, 2)
        max(depth, max_so_far)
      end)

    # Method 2: Brace-based depth (JSON / HCL / Terraform).
    brace_depth = count_brace_depth(input)

    # Take the maximum of both methods as the effective nesting depth.
    effective_depth = max(max_indent_depth, brace_depth)

    if effective_depth > @max_nesting_depth do
      Logger.warning(
        "Excessive nesting depth: #{effective_depth} (max #{@max_nesting_depth})"
      )

      {:error, "Nesting too deep: #{effective_depth} levels (max #{@max_nesting_depth})"}
    else
      :ok
    end
  end

  # Count maximum brace nesting depth for JSON/HCL formats.
  #
  # Walks through the input character by character, incrementing depth on
  # `{` and `[`, decrementing on `}` and `]`. Tracks the maximum depth
  # reached at any point during the scan.
  #
  # The depth never goes below 0 (clamped with `max/2`) to handle
  # malformed input with unmatched closing braces gracefully — we don't
  # want a negative depth to cancel out a later deep nesting.
  #
  # Uses a two-element tuple accumulator {current_depth, max_depth} to
  # avoid allocating intermediate data structures.
  defp count_brace_depth(input) do
    input
    |> String.graphemes()
    |> Enum.reduce({0, 0}, fn
      "{", {current, max_d} -> {current + 1, max(current + 1, max_d)}
      "[", {current, max_d} -> {current + 1, max(current + 1, max_d)}
      "}", {current, max_d} -> {max(current - 1, 0), max_d}
      "]", {current, max_d} -> {max(current - 1, 0), max_d}
      _, acc -> acc
    end)
    |> elem(1)
  end
end
