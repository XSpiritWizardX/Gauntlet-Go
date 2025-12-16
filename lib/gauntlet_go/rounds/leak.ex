defmodule GauntletGo.Rounds.Leak do
  @moduledoc false

  @bleed_rate 1.0
  @finish_x 120.0
  @obstacles [
    %{x1: 20.0, x2: 28.0, knockback: 6.0},
    %{x1: 48.0, x2: 55.0, knockback: 7.5},
    %{x1: 72.0, x2: 80.0, knockback: 8.5},
    %{x1: 98.0, x2: 105.0, knockback: 10.0}
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
    hit =
      Enum.find(obstacles, fn ob ->
        {x, _y} = player.pos
        x >= ob.x1 and x <= ob.x2 and player.jump_timer <= 0.0
      end)

    case hit do
      nil ->
        player

      ob ->
        {x, y} = player.pos
        %{player | pos: {max(x - ob.knockback, 0.0), y}}
    end
  end

  defp maybe_finish(player, elapsed_ms) do
    {x, _y} = player.pos

    if x >= @finish_x do
      %{player | finished_at_ms: player.finished_at_ms || elapsed_ms}
    else
      player
    end
  end
end
