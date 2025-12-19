defmodule GauntletGoWeb.PageController do
  use GauntletGoWeb, :controller

  alias GauntletGo.Player

  def home(conn, _params) do
    player_colors = Player.colors()
    default_color = List.first(player_colors) || "#22c55e"
    form = Phoenix.Component.to_form(%{room_id: "family", player_color: default_color}, as: :join)
    ai_form = Phoenix.Component.to_form(%{ai_count: 2}, as: :ai)

    render(conn, :home,
      form: form,
      ai_form: ai_form,
      player_colors: player_colors,
      default_color: default_color
    )
  end
end
