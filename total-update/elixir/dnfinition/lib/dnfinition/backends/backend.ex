# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.Backends.Backend do
  @moduledoc """
  Behaviour defining the interface for package manager backends.

  All backends must implement this behaviour to provide a consistent
  interface for package management operations.
  """

  @doc "Human-readable name of the package manager"
  @callback name() :: String.t()

  @doc "Package manager type atom"
  @callback pm_type() :: atom()

  @doc "Check if the backend is available on this system"
  @callback available?() :: boolean()

  @doc "Check if the backend supports atomic transactions"
  @callback supports_transactions?() :: boolean()

  @doc "Check if the backend supports rollback"
  @callback supports_rollback?() :: boolean()

  @doc "Install packages"
  @callback install(packages :: [String.t()], opts :: keyword()) :: map()

  @doc "Remove packages"
  @callback remove(packages :: [String.t()], opts :: keyword()) :: map()

  @doc "Upgrade packages (empty list = upgrade all)"
  @callback upgrade(packages :: [String.t()], opts :: keyword()) :: map()

  @doc "Rollback N generations"
  @callback rollback(steps :: pos_integer()) :: map()

  @doc "List installed packages"
  @callback installed() :: {:ok, [map()]} | {:error, term()}

  @doc "Search for packages"
  @callback search(query :: String.t()) :: {:ok, [map()]} | {:error, term()}
end
