defmodule GauntletGoWeb.GameChannel do
  use Phoenix.Channel

  alias GauntletGo.{GameRoom, Rooms}

  @impl true
  def join("game:" <> room_id, params, socket) do
    player_id = socket.assigns.player_id || params["player_id"] || random_id()
    name = params["name"] || player_id

    with {:ok, _pid} <- Rooms.ensure_room(room_id),
         :ok <- GameRoom.join(room_id, player_id, name) do
      {:ok, %{player_id: player_id},
       assign(socket, room_id: room_id, player_id: player_id, name: name)}
    else
      _ -> {:error, %{reason: "room_unavailable"}}
    end
  end

  @impl true
  def handle_in("input", payload, socket) do
    GameRoom.input(socket.assigns.room_id, socket.assigns.player_id, payload)
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    GameRoom.leave(socket.assigns.room_id, socket.assigns.player_id)
    :ok
  end

  defp random_id do
    "p" <> Integer.to_string(:erlang.unique_integer([:positive]))
  end
end
