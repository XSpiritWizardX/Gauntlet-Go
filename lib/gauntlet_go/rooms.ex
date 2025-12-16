defmodule GauntletGo.Rooms do
  @moduledoc """
  Helpers for starting and locating game rooms.
  """

  alias GauntletGo.GameRoom

  def ensure_room(room_id) do
    case Registry.lookup(GauntletGo.RoomRegistry, room_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(GauntletGo.RoomSupervisor, {GameRoom, room_id: room_id})
    end
  end
end
