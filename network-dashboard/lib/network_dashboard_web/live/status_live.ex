# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule NetworkDashboardWeb.StatusLive do
  @moduledoc """
  LiveView that displays FlatRacoon module status grid.
  Polls orchestrator /api/modules and renders real-time module health.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NetworkDashboard.PubSub, "modules")
    end

    modules = NetworkDashboard.ModulePoller.get_modules()

    {:ok,
     assign(socket,
       page_title: "FlatRacoon Dashboard",
       modules: modules,
       last_updated: DateTime.utc_now()
     )}
  end

  @impl true
  def handle_info({:modules_updated, modules}, socket) do
    {:noreply, assign(socket, modules: modules, last_updated: DateTime.utc_now())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard">
      <header>
        <h1>FlatRacoon Network Stack</h1>
        <p class="updated">Last updated: <%= Calendar.strftime(@last_updated, "%H:%M:%S UTC") %></p>
      </header>

      <div class="module-grid">
        <%= for module <- @modules do %>
          <div class={"module-card #{status_class(module)}"}>
            <div class="module-header">
              <span class="status-indicator"></span>
              <h3><%= module["name"] || "unknown" %></h3>
            </div>
            <dl>
              <dt>Layer</dt>
              <dd><%= module["layer"] || "?" %></dd>
              <dt>Status</dt>
              <dd><%= module["status"] || "unknown" %></dd>
              <dt>Mode</dt>
              <dd><%= module["deployment_mode"] || "?" %></dd>
            </dl>
          </div>
        <% end %>

        <%= if @modules == [] do %>
          <p class="empty">No modules reported. Is the orchestrator running?</p>
        <% end %>
      </div>
    </div>
    """
  end

  defp status_class(%{"status" => "healthy"}), do: "healthy"
  defp status_class(%{"status" => "degraded"}), do: "degraded"
  defp status_class(%{"status" => "down"}), do: "down"
  defp status_class(_), do: "unknown"
end
