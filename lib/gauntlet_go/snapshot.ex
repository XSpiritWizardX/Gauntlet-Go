defmodule GauntletGo.Snapshot do
  @moduledoc false

  def build(state) do
    %{
      round: state.round,
      leader_id: state.leader_id,
      round_elapsed_ms: state.round_elapsed_ms,
      countdown_ms: countdown_ms(state),
      countdown_round: state.countdown_round,
      players: serialize_players(state.players),
      round_state: serialize_round_state(state.round, state.round_state)
    }
  end

  def build_game_over(players) do
    leaderboard =
      players
      |> Enum.sort_by(fn {_id, p} -> {-p.score, p.finished_at_ms || :infinity} end)
      |> Enum.map(fn {id, p} ->
        %{id: id, name: p.name, score: round_score(p.score), color: p.color}
      end)

    %{leaderboard: leaderboard, top3: Enum.take(leaderboard, 3)}
  end

  defp serialize_players(players) do
    players
    |> Enum.map(fn {id, p} ->
      %{
        id: id,
        name: p.name,
        color: p.color,
        score: round_score(p.score),
        pos: tuple_to_list(p.pos),
        alive: p.alive?,
        carrying_light: p.carrying_light?,
        finished_at_ms: p.finished_at_ms
      }
    end)
  end

  defp serialize_round_state(:r1_survival, rs) do
    %{
      pickups: Enum.map(rs.pickups, &serialize_point/1),
      hazards: Enum.map(rs.hazards, &serialize_point/1)
    }
  end

  defp serialize_round_state(:r2_light, rs) do
    light_pos =
      case rs.light_pos do
        {x, y} -> [x, y]
        _ -> [50.0, 50.0]
      end

    %{
      light_pos: light_pos,
      light_owner: rs.light_owner
    }
  end

  defp serialize_round_state(:r3_leak, rs) do
    %{
      finished: MapSet.to_list(rs.finished),
      obstacles:
        Enum.map(rs.obstacles, fn ob ->
          %{x1: ob.x1, x2: ob.x2, y1: ob.y1, y2: ob.y2}
        end),
      finish_x: 120.0
    }
  end

  defp serialize_round_state(_, _), do: %{}

  defp serialize_point(%{pos: pos} = map), do: Map.put(map, :pos, tuple_to_list(pos))
  defp tuple_to_list({a, b}), do: [a, b]

  defp round_score(score), do: Float.round(score, 1)

  defp countdown_ms(%{status: :countdown, countdown_until_ms: until_ms})
       when is_integer(until_ms) do
    now = System.system_time(:millisecond)
    max(until_ms - now, 0)
  end

  defp countdown_ms(_state), do: 0
end
