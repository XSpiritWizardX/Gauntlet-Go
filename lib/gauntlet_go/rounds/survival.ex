defmodule GauntletGo.Rounds.Survival do
  @moduledoc false

  alias GauntletGo.Player

  @pickup_radius 3.5
  @hazard_radius 4.5
  @alive_score_per_sec 1.0

  def init_round do
    %{elapsed_ms: 0, pickups: [], hazards: [], bonus_given?: false}
  end

  def tick(players, round_state, dt) do
    elapsed_ms = round_state.elapsed_ms + trunc(dt * 1000)

    round_state =
      round_state
      |> Map.put(:elapsed_ms, elapsed_ms)
      |> spawn_pickups()
      |> spawn_hazards()
      |> age_hazards(dt)

    players =
      players
      |> add_survival_points(dt)
      |> collect_pickups(round_state.pickups)
      |> apply_hazards(round_state.hazards)

    %{players: players, round_state: round_state}
  end

  def finished?(players, _round_state, elapsed_ms, duration_ms) do
    if map_size(players) == 0 do
      false
    else
      alive_count =
        players
        |> Map.values()
        |> Enum.count(& &1.alive?)

      elapsed_ms >= duration_ms or alive_count <= 1
    end
  end

  def on_round_end(players, _round_state) do
    alive_players =
      players
      |> Enum.filter(fn {_id, p} -> p.alive? end)

    case alive_players do
      [{id, player}] ->
        Map.put(players, id, %{player | score: player.score + 15.0})

      _ ->
        players
    end
  end

  defp add_survival_points(players, dt) do
    Enum.into(players, %{}, fn {id, p} ->
      if p.alive? do
        {id, %{p | score: p.score + @alive_score_per_sec * dt}}
      else
        {id, p}
      end
    end)
  end

  defp collect_pickups(players, pickups) do
    Enum.reduce(pickups, players, fn pickup, acc ->
      Enum.reduce(acc, acc, fn {id, p}, inner_acc ->
        if p.alive? && distance(p.pos, pickup.pos) <= @pickup_radius do
          Map.put(inner_acc, id, %{p | score: p.score + pickup.value})
        else
          inner_acc
        end
      end)
    end)
  end

  defp apply_hazards(players, hazards) do
    Enum.into(players, %{}, fn {id, p} ->
      hit? =
        p.alive? &&
          !Player.airborne?(p) &&
          Enum.any?(hazards, fn hz -> distance(p.pos, hz.pos) <= @hazard_radius end)

      if hit? do
        {id, %{p | alive?: false}}
      else
        {id, p}
      end
    end)
  end

  defp spawn_pickups(%{pickups: pickups} = state) when length(pickups) >= 10, do: state

  defp spawn_pickups(state) do
    if :rand.uniform() < 0.25 do
      pickup = %{
        id: System.unique_integer([:positive]),
        pos: random_point(),
        value: Enum.random([3.0, 5.0, 8.0, 10.0])
      }

      %{state | pickups: [pickup | state.pickups]}
    else
      state
    end
  end

  defp spawn_hazards(%{hazards: hazards} = state) when length(hazards) >= 8, do: state

  defp spawn_hazards(state) do
    if :rand.uniform() < 0.15 do
      hazard = %{id: System.unique_integer([:positive]), pos: random_point(), ttl: 4.0}
      %{state | hazards: [hazard | state.hazards]}
    else
      state
    end
  end

  defp age_hazards(state, dt) do
    hazards =
      state.hazards
      |> Enum.map(fn hz -> %{hz | ttl: hz.ttl - dt} end)
      |> Enum.filter(&(&1.ttl > 0))

    %{state | hazards: hazards}
  end

  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt(:math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2))
  end

  defp random_point do
    {:rand.uniform() * 100.0, :rand.uniform() * 100.0}
  end
end
