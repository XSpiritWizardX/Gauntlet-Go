defmodule GauntletGo.Rounds.Leak do
  @moduledoc false

  @bleed_rate 1.0
  @finish_x 120.0
  @obstacles [
    %{x1: 8.0, x2: 12.0, y1: 6.0, y2: 42.0, knockback: 5.0},
    %{x1: 8.0, x2: 12.0, y1: 58.0, y2: 94.0, knockback: 5.0},
    %{x1: 18.0, x2: 22.0, y1: 0.0, y2: 28.0, knockback: 5.0},
    %{x1: 18.0, x2: 22.0, y1: 36.0, y2: 72.0, knockback: 5.0},
    %{x1: 18.0, x2: 22.0, y1: 80.0, y2: 100.0, knockback: 5.0},
    %{x1: 30.0, x2: 34.0, y1: 10.0, y2: 48.0, knockback: 5.0},
    %{x1: 30.0, x2: 34.0, y1: 58.0, y2: 90.0, knockback: 5.0},
    %{x1: 40.0, x2: 70.0, y1: 18.0, y2: 22.0, knockback: 4.0},
    %{x1: 44.0, x2: 48.0, y1: 30.0, y2: 78.0, knockback: 5.0},
    %{x1: 56.0, x2: 60.0, y1: 8.0, y2: 40.0, knockback: 5.0},
    %{x1: 56.0, x2: 60.0, y1: 52.0, y2: 92.0, knockback: 5.0},
    %{x1: 68.0, x2: 72.0, y1: 26.0, y2: 70.0, knockback: 5.0},
    %{x1: 76.0, x2: 110.0, y1: 38.0, y2: 42.0, knockback: 4.0},
    %{x1: 82.0, x2: 86.0, y1: 6.0, y2: 30.0, knockback: 5.0},
    %{x1: 94.0, x2: 98.0, y1: 52.0, y2: 96.0, knockback: 5.0},
    %{x1: 104.0, x2: 108.0, y1: 10.0, y2: 60.0, knockback: 5.0},
    %{x1: 114.0, x2: 118.0, y1: 34.0, y2: 90.0, knockback: 5.0}
  ]

  def init_round do
    %{elapsed_ms: 0, finished: MapSet.new(), obstacles: @obstacles}
  end

  def tick(players, round_state, dt) do
    elapsed_ms = round_state.elapsed_ms + trunc(dt * 1000)

    {players, finished} =
      Enum.reduce(players, {players, round_state.finished}, fn {id, p},
                                                               {acc_players, acc_finished} ->
        if MapSet.member?(acc_finished, id) do
          {acc_players, acc_finished}
        else
          updated =
            apply_bleed(p, dt)
            |> maybe_hit_obstacle(round_state.obstacles)
            |> maybe_finish(elapsed_ms)

          acc_players = Map.put(acc_players, id, updated)

          acc_finished =
            if updated.finished_at_ms, do: MapSet.put(acc_finished, id), else: acc_finished

          {acc_players, acc_finished}
        end
      end)

    %{players: players, round_state: %{round_state | elapsed_ms: elapsed_ms, finished: finished}}
  end

  def finished?(players, round_state, elapsed_ms, duration_ms) do
    if map_size(players) == 0 do
      false
    else
      everyone_done? =
        map_size(players) > 0 and MapSet.size(round_state.finished) == map_size(players)

      everyone_done? or elapsed_ms >= duration_ms
    end
  end

  def on_round_end(players, _round_state) do
    Enum.into(players, %{}, fn {id, p} ->
      {id, %{p | score: max(p.score, 0.0)}}
    end)
  end

  defp apply_bleed(player, dt) do
    %{player | score: max(player.score - @bleed_rate * dt, 0.0)}
  end

  defp maybe_hit_obstacle(player, obstacles) do
    Enum.reduce_while(obstacles, player, fn ob, acc ->
      if acc.jump_timer > 0.0 do
        {:cont, acc}
      else
        {x, y} = acc.pos
        hit? = x >= ob.x1 and x <= ob.x2 and y >= ob.y1 and y <= ob.y2

        if hit? do
          updated = %{acc | pos: {0.0, 50.0}}
          {:halt, updated}
        else
          {:cont, acc}
        end
      end
    end)
  end

  defp maybe_finish(player, elapsed_ms) do
    {x, _y} = player.pos

    if x >= @finish_x do
      %{player | finished_at_ms: player.finished_at_ms || elapsed_ms}
    else
      player
    end
  end

  defp clamp(val, min, _max) when val < min, do: min
  defp clamp(val, _min, max) when val > max, do: max
  defp clamp(val, _min, _max), do: val
end
