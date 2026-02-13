# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.Backends.NixBackend do
  @moduledoc """
  Nix package manager backend.

  Nix has native generation-based transactions, making rollback trivial.
  Each package operation creates a new generation that can be switched to.

  Key commands:
  - nix-env -i <pkg>              # Install (creates new generation)
  - nix-env -e <pkg>              # Erase/remove (creates new generation)
  - nix-env -u                    # Upgrade all (creates new generation)
  - nix-env --rollback            # Rollback to previous generation
  - nix-env --switch-generation N # Switch to generation N
  - nix-env --list-generations    # List generations
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
  def name do
    if nixos?(), do: "NixOS", else: "Nix"
  end

  @impl DNFinition.Backends.Backend
  def pm_type, do: :nix

  @impl DNFinition.Backends.Backend
  def available? do
    System.find_executable("nix-env") != nil
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
  def garbage_collect(delete_old_generations \\ false) do
    GenServer.call(__MODULE__, {:gc, delete_old_generations}, :infinity)
  end

  @doc """
  Update channels.
  """
  def channel_update do
    GenServer.call(__MODULE__, :channel_update, :infinity)
  end

  @doc """
  Check if running on NixOS.
  """
  def nixos? do
    File.exists?("/etc/nixos/configuration.nix")
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    profile = Keyword.get(opts, :profile, "~/.nix-profile")

    state = %{
      profile: profile,
      available: available?(),
      is_nixos: nixos?()
    }

    Logger.info("Nix backend initialized (available: #{state.available}, NixOS: #{state.is_nixos})")
    {:ok, state}
  end

  @impl true
  def handle_call({:install, packages, _opts}, _from, state) do
    {:ok, gen_before} = get_current_generation(state)

    result =
      case System.cmd("nix-env", ["-p", state.profile, "-i" | packages], stderr_to_stdout: true) do
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
      case System.cmd("nix-env", ["-p", state.profile, "-e" | packages], stderr_to_stdout: true) do
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
        ["-p", state.profile, "-u"]
      else
        ["-p", state.profile, "-u" | packages]
      end

    result =
      case System.cmd("nix-env", args, stderr_to_stdout: true) do
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

    result =
      Enum.reduce_while(1..steps, {:ok, gen_before}, fn step, {:ok, _gen} ->
        case System.cmd("nix-env", ["-p", state.profile, "--rollback"], stderr_to_stdout: true) do
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
      case System.cmd("nix-env", ["-p", state.profile, "--switch-generation", "#{gen_id}"],
             stderr_to_stdout: true
           ) do
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
      case System.cmd("nix-env", ["-p", state.profile, "--list-generations"],
             stderr_to_stdout: true
           ) do
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
      case System.cmd("nix-env", ["-p", state.profile, "-q"], stderr_to_stdout: true) do
        {output, 0} ->
          packages = parse_installed(output)
          {:ok, packages}

        {error, _} ->
          {:error, error}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:search, query}, _from, _state) do
    # Use new nix search command if available, fallback to nix-env
    result =
      case System.cmd("nix", ["search", "nixpkgs", query], stderr_to_stdout: true) do
        {output, 0} ->
          packages = parse_search_results(output)
          {:ok, packages}

        {_error, _} ->
          # Fallback to nix-env
          case System.cmd("nix-env", ["-qa", "--description", "*#{query}*"],
                 stderr_to_stdout: true
               ) do
            {output, 0} ->
              packages = parse_legacy_search(output)
              {:ok, packages}

            {error, _} ->
              {:error, error}
          end
      end

    {:reply, result, _state}
  end

  @impl true
  def handle_call({:gc, delete_old}, _from, state) do
    Logger.info("Running nix garbage collection...")

    args = if delete_old, do: ["-d"], else: []

    result =
      case System.cmd("nix-collect-garbage", args, stderr_to_stdout: true) do
        {output, 0} ->
          Logger.info("Garbage collection completed")
          {:ok, output}

        {error, code} ->
          {:error, error, code}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:channel_update, _from, state) do
    Logger.info("Updating nix channels...")

    result =
      case System.cmd("nix-channel", ["--update"], stderr_to_stdout: true) do
        {output, 0} ->
          Logger.info("Channel update completed")
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
    case System.cmd("nix-env", ["-p", state.profile, "--list-generations"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        # Parse current generation (line with "(current)")
        current =
          output
          |> String.split("\n")
          |> Enum.find(&String.contains?(&1, "(current)"))
          |> case do
            nil ->
              1

            line ->
              case Regex.run(~r/^\s*(\d+)/, line) do
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
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(fn line ->
      # Format: "   1   2025-12-27 12:00:00   (current)"
      case Regex.run(~r/^\s*(\d+)\s+(\S+\s+\S+)\s*(\(current\))?/, line) do
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
      # Package names often include version: package-1.2.3
      case Regex.run(~r/^(.+)-([0-9].*)$/, line) do
        [_, name, version] ->
          %{name: name, version: version}

        _ ->
          %{name: String.trim(line), version: ""}
      end
    end)
  end

  defp parse_search_results(output) do
    # New nix search output format
    output
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "* "))
    |> Enum.map(fn line ->
      case Regex.run(~r/^\* (\S+) \((\S+)\)$/, line) do
        [_, name, version] ->
          %{name: name, version: version, description: ""}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_legacy_search(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(fn line ->
      parts = String.split(line, ~r/\s+/, parts: 2)

      case parts do
        [name | rest] ->
          %{
            name: name,
            version: "",
            description: Enum.join(rest, " ")
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
