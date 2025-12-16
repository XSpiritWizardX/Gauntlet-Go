defmodule GauntletGo.Leader do
  @moduledoc false

  def calc(players) when map_size(players) == 0, do: nil

  def calc(players) do
    players
    |> Enum.sort_by(fn {_id, p} -> {-p.score, p.finished_at_ms || :infinity} end)
    |> List.first()
    |> elem(0)
  end
end
