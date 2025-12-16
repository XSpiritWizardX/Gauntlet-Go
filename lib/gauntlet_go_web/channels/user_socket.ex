defmodule GauntletGoWeb.UserSocket do
  use Phoenix.Socket

  channel "game:*", GauntletGoWeb.GameChannel

  @impl true
  def connect(params, socket, _connect_info) do
    player_id =
      case Map.get(params, "player_id") do
        id when id in [nil, "", "undefined", "null"] -> random_id()
        id -> id
      end

    {:ok, assign(socket, :player_id, player_id)}
  end

  @impl true
  def id(_socket), do: nil

  defp random_id do
    "p" <> Integer.to_string(:erlang.unique_integer([:positive]))
  end
end
