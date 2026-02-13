# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.Backends.GuixBackend do
  @moduledoc """
  Guix package manager backend.

  Guix has native generation-based transactions, making rollback trivial.
  Each package operation creates a new generation that can be switched to.

  Key commands:
  - guix package -i <pkg>       # Install (creates new generation)
  - guix package -r <pkg>       # Remove (creates new generation)
  - guix package -u             # Upgrade all (creates new generation)
  - guix package --roll-back    # Rollback to previous generation
  - guix package -S <N>         # Switch to generation N
  - guix package -l             # List generations
  """

  use GenServer
  require Logger

  @behaviour DNFinition.Backends.Backend

  # ═══════════════════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DNFinition.Backends.Backend
  def name, do: "GNU Guix"

  @impl DNFinition.Backends.Backend
  def pm_type, do: :guix

  @impl DNFinition.Backends.Backend
  def available? do
    System.find_executable("guix") != nil
  end

  @impl DNFinition.Backends.Backend
  def supports_transactions?, do: true

  @impl DNFinition.Backends.Backend
  def supports_rollback?, do: true

  @doc """
  Install packages with automatic generation creation.
  """
  @impl DNFinition.Backends.Backend
  def install(packages, opts \\ []) do
    GenServer.call(__MODULE__, {:install, packages, opts}, :infinity)
  end

  @doc """
  Remove packages.
  """
  @impl DNFinition.Backends.Backend
  def remove(packages, opts \\ []) do
    GenServer.call(__MODULE__, {:remove, packages, opts}, :infinity)
  end

  @doc """
  Upgrade packages (empty list = upgrade all).
  """
  @impl DNFinition.Backends.Backend
  def upgrade(packages \\ [], opts \\ []) do
    GenServer.call(__MODULE__, {:upgrade, packages, opts}, :infinity)
  end

  @doc """
  Rollback to previous generation.
  """
  @impl DNFinition.Backends.Backend
  def rollback(steps \\ 1) do
    GenServer.call(__MODULE__, {:rollback, steps}, :infinity)
  end

  @doc """
  Switch to a specific generation.
  """
  def switch_generation(generation_id) do
    GenServer.call(__MODULE__, {:switch_generation, generation_id})
  end

  @doc """
  Get current generation number.
  """
  def current_generation do
    GenServer.call(__MODULE__, :current_generation)
  end

  @doc """
  List all generations.
  """
  def list_generations do
    GenServer.call(__MODULE__, :list_generations)
  end

  @doc """
  Get installed packages.
  """
  @impl DNFinition.Backends.Backend
  def installed do
    GenServer.call(__MODULE__, :installed)
  end

  @doc """
  Search for packages.
  """
  @impl DNFinition.Backends.Backend
  def search(query) do
    GenServer.call(__MODULE__, {:search, query})
  end

  @doc """
  Garbage collect the store.
  """
  def garbage_collect do
    GenServer.call(__MODULE__, :gc, :infinity)
  end

  @doc """
  Update package definitions (guix pull).
  """
  def pull do
    GenServer.call(__MODULE__, :pull, :infinity)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    profile = Keyword.get(opts, :profile, "~/.guix-profile")

    state = %{
      profile: profile,
      available: available?()
    }

    Logger.info("Guix backend initialized (available: #{state.available})")
    {:ok, state}
  end

  @impl true
  def handle_call({:install, packages, opts}, _from, state) do
    pkg_list = Enum.join(packages, " ")
    profile_arg = "-p #{state.profile}"

    # Record current generation before install
    {:ok, gen_before} = get_current_generation(state)

    cmd = "guix package #{profile_arg} -i #{pkg_list}"
    Logger.info("Executing: #{cmd}")

    result =
      case System.cmd("guix", ["package", "-p", state.profile, "-i" | packages], stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, gen_after} = get_current_generation(state)
          Logger.info("Install succeeded. Generation: #{gen_before} -> #{gen_after}")

          %{
            status: :success,
            packages: packages,
            generation_before: gen_before,
            generation_after: gen_after,
            output: output
          }

        {error, code} ->
          Logger.error("Install failed (exit #{code}): #{error}")

          %{
            status: :failed,
            packages: packages,
            error: error,
            exit_code: code
          }
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:remove, packages, _opts}, _from, state) do
    {:ok, gen_before} = get_current_generation(state)

    result =
      case System.cmd("guix", ["package", "-p", state.profile, "-r" | packages], stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, gen_after} = get_current_generation(state)
          Logger.info("Remove succeeded. Generation: #{gen_before} -> #{gen_after}")

          %{
            status: :success,
            packages: packages,
            generation_before: gen_before,
            generation_after: gen_after,
            output: output
          }

        {error, code} ->
          Logger.error("Remove failed (exit #{code}): #{error}")

          %{
            status: :failed,
            packages: packages,
            error: error,
            exit_code: code
          }
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:upgrade, packages, _opts}, _from, state) do
    {:ok, gen_before} = get_current_generation(state)

    args =
      if packages == [] do
        ["package", "-p", state.profile, "-u"]
      else
        ["package", "-p", state.profile, "-u" | packages]
      end

    result =
      case System.cmd("guix", args, stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, gen_after} = get_current_generation(state)
          Logger.info("Upgrade succeeded. Generation: #{gen_before} -> #{gen_after}")

          %{
            status: :success,
            packages: packages,
            generation_before: gen_before,
            generation_after: gen_after,
            output: output
          }

        {error, code} ->
          Logger.error("Upgrade failed (exit #{code}): #{error}")

          %{
            status: :failed,
            packages: packages,
            error: error,
            exit_code: code
          }
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:rollback, steps}, _from, state) do
    {:ok, gen_before} = get_current_generation(state)

    # Execute rollback N times
    result =
      Enum.reduce_while(1..steps, {:ok, gen_before}, fn step, {:ok, _gen} ->
        case System.cmd("guix", ["package", "-p", state.profile, "--roll-back"], stderr_to_stdout: true) do
          {_output, 0} ->
            {:ok, new_gen} = get_current_generation(state)
            Logger.info("Rollback step #{step} succeeded. Now at generation #{new_gen}")
            {:cont, {:ok, new_gen}}

          {error, code} ->
            Logger.error("Rollback step #{step} failed: #{error}")
            {:halt, {:error, error, code}}
        end
      end)

    response =
      case result do
        {:ok, gen_after} ->
          %{
            status: :success,
            generation_before: gen_before,
            generation_after: gen_after,
            steps: steps
          }

        {:error, error, code} ->
          %{
            status: :failed,
            error: error,
            exit_code: code
          }
      end

    {:reply, response, state}
  end

  @impl true
  def handle_call({:switch_generation, gen_id}, _from, state) do
    result =
      case System.cmd("guix", ["package", "-p", state.profile, "-S", "#{gen_id}"], stderr_to_stdout: true) do
        {output, 0} ->
          Logger.info("Switched to generation #{gen_id}")
          %{status: :success, generation: gen_id, output: output}

        {error, code} ->
          Logger.error("Switch generation failed: #{error}")
          %{status: :failed, error: error, exit_code: code}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:current_generation, _from, state) do
    {:reply, get_current_generation(state), state}
  end

  @impl true
  def handle_call(:list_generations, _from, state) do
    result =
      case System.cmd("guix", ["package", "-p", state.profile, "-l"], stderr_to_stdout: true) do
        {output, 0} ->
          generations = parse_generations(output)
          {:ok, generations}

        {error, _} ->
          {:error, error}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:installed, _from, state) do
    result =
      case System.cmd("guix", ["package", "-p", state.profile, "-I"], stderr_to_stdout: true) do
        {output, 0} ->
          packages = parse_installed(output)
          {:ok, packages}

        {error, _} ->
          {:error, error}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:search, query}, _from, state) do
    result =
      case System.cmd("guix", ["search", query], stderr_to_stdout: true) do
        {output, 0} ->
          packages = parse_search_results(output)
          {:ok, packages}

        {error, _} ->
          {:error, error}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:gc, _from, state) do
    Logger.info("Running guix garbage collection...")

    result =
      case System.cmd("guix", ["gc"], stderr_to_stdout: true) do
        {output, 0} ->
          Logger.info("Garbage collection completed")
          {:ok, output}

        {error, code} ->
          {:error, error, code}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:pull, _from, state) do
    Logger.info("Running guix pull...")

    result =
      case System.cmd("guix", ["pull"], stderr_to_stdout: true) do
        {output, 0} ->
          Logger.info("Guix pull completed")
          {:ok, output}

        {error, code} ->
          {:error, error, code}
      end

    {:reply, result, state}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp get_current_generation(state) do
    case System.cmd("guix", ["package", "-p", state.profile, "-l"], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse first line which shows current generation
        # Format: "Generation 123	Dec 27 2025 12:00:00	(current)"
        current =
          output
          |> String.split("\n")
          |> Enum.find(&String.contains?(&1, "(current)"))
          |> case do
            nil -> 1
            line ->
              case Regex.run(~r/Generation\s+(\d+)/, line) do
                [_, gen] -> String.to_integer(gen)
                _ -> 1
              end
          end

        {:ok, current}

      {_error, _} ->
        {:ok, 1}
    end
  end

  defp parse_generations(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&String.match?(&1, ~r/^Generation\s+\d+/))
    |> Enum.map(fn line ->
      case Regex.run(~r/Generation\s+(\d+)\s+(.+?)(\s+\(current\))?$/, line) do
        [_, gen, timestamp | rest] ->
          %{
            id: String.to_integer(gen),
            timestamp: String.trim(timestamp),
            current: rest != []
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_installed(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(fn line ->
      parts = String.split(line, ~r/\s+/, parts: 4)

      case parts do
        [name, version | _] ->
          %{name: name, version: version}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_search_results(output) do
    # Guix search output is in recutils format
    output
    |> String.split("\n\n")
    |> Enum.map(fn block ->
      fields =
        block
        |> String.split("\n")
        |> Enum.map(fn line ->
          case String.split(line, ": ", parts: 2) do
            [key, value] -> {String.downcase(key), value}
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Map.new()

      if Map.has_key?(fields, "name") do
        %{
          name: fields["name"],
          version: fields["version"] || "",
          description: fields["synopsis"] || ""
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
