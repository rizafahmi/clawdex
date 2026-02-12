defmodule ClawdexWeb.CoreComponents do
  @moduledoc false

  use Phoenix.Component

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div class="fixed top-4 right-4 z-50 space-y-2">
      <.flash :if={@flash["info"]} kind={:info} message={@flash["info"]} />
      <.flash :if={@flash["error"]} kind={:error} message={@flash["error"]} />
    </div>
    """
  end

  attr :kind, :atom, required: true
  attr :message, :string, required: true

  def flash(assigns) do
    ~H"""
    <div class={[
      "rounded-lg px-4 py-3 text-sm shadow-lg",
      @kind == :info && "bg-emerald-900 text-emerald-200",
      @kind == :error && "bg-red-900 text-red-200"
    ]}>
      {@message}
    </div>
    """
  end
end
