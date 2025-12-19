defmodule GauntletGo.Rounds.Light do
  @moduledoc false

  @carry_rate 2.0
  @assist_rate 1.0
  @steal_radius 8.0
  @pickup_radius 6.0
  @chaos_every 12_000

  def init_round do
    %{elapsed_ms: 0, light_pos: {50.0, 50.0}, light_owner: nil, chaos_timer: 0}
  end

  def tick(players, round_state, dt) do
    chaos_timer = round_state.chaos_timer + trunc(dt * 1000)
    elapsed_ms = round_state.elapsed_ms + trunc(dt * 1000)
    light_pos = round_state.light_pos || {50.0, 50.0}
    light_owner = round_state.light_owner

    players = reset_carry_flags(players, light_owner)
    {players, light_owner, light_pos} =
      award_carry_and_assists(players, light_owner, dt, light_pos)

    {players, light_owner, light_pos} = maybe_pickup_unowned(players, light_owner, light_pos)
    {players, light_owner, light_pos} = maybe_resolve_steals(players, light_owner, light_pos)

    {light_owner, light_pos, chaos_timer} =
      maybe_chaos(light_owner, light_pos, chaos_timer)

    round_state = %{
      round_state
      | elapsed_ms: elapsed_ms,
        light_owner: light_owner,
        light_pos: light_pos,
        chaos_timer: chaos_timer
    }

    %{players: players, round_state: round_state}
  end

  def finished?(players, _round_state, elapsed_ms, duration_ms) do
    if map_size(players) == 0 do
      false
    else
      elapsed_ms >= duration_ms
    end
  end

  def on_round_end(players, round_state) do
    case round_state.light_owner do
      nil ->
        players

      owner ->
        case Map.get(players, owner) do
          nil ->
            players

          _player ->
            Map.update!(players, owner, fn p ->
              %{p | score: p.score + 10.0, carrying_light?: false}
            end)
        end
    end
  end

  defp reset_carry_flags(players, owner) do
    Enum.into(players, %{}, fn {id, p} ->
      {id, %{p | carrying_light?: owner == id}}
    end)
  end

  defp award_carry_and_assists(players, nil, _dt, light_pos) do
    {players, nil, light_pos}
  end

  defp award_carry_and_assists(players, owner, dt, light_pos) do
    owner_position = owner_pos(players, owner)

    if is_nil(owner_position) do
      {players, nil, light_pos}
    else
      players =
        Enum.into(players, %{}, fn {id, p} ->
          cond do
            id == owner ->
              {id, %{p | score: p.score + @carry_rate * dt, carrying_light?: true, pos: p.pos}}

            distance(p.pos, owner_position) <= @steal_radius ->
              {id, %{p | score: p.score + @assist_rate * dt}}

            true ->
              {id, p}
          end
        end)

      {players, owner, owner_position}
    end
  end

  defp maybe_pickup_unowned(players, owner, light_pos) when not is_nil(owner),
    do: {players, owner, light_pos}

  defp maybe_pickup_unowned(players, _owner, light_pos) do
    picker =
      players
      |> Enum.find(fn {_id, p} -> distance(p.pos, light_pos) <= @pickup_radius end)

    case picker do
      {id, p} ->
        players = Map.put(players, id, %{p | carrying_light?: true})
        {players, id, p.pos}

      _ ->
        {players, nil, light_pos}
    end
  end

  defp maybe_resolve_steals({players, owner, light_pos}),
    do: maybe_resolve_steals(players, owner, light_pos)

  defp maybe_resolve_steals(players, nil, light_pos), do: {players, nil, light_pos}

  defp maybe_resolve_steals(players, owner, light_pos) do
    owner_position = owner_pos(players, owner)

    if is_nil(owner_position) do
      {players, nil, light_pos}
    else
      attackers =
        players
        |> Enum.filter(fn {id, p} ->
          id != owner and p.input.action and
            distance(p.pos, owner_position) <= @steal_radius
        end)

      steal_strength =
        case length(attackers) do
          0 -> 0.0
          1 -> 0.45
          n -> 0.45 + 0.15 * (n - 1)
        end

      if steal_strength > 0 && :rand.uniform() < steal_strength do
        {new_owner_id, new_owner} = Enum.random(attackers)

        players =
          players
          |> Map.update!(owner, fn p -> %{p | carrying_light?: false} end)
          |> Map.update!(new_owner_id, fn p -> %{p | carrying_light?: true} end)

        {players, new_owner_id, new_owner.pos}
      else
        {players, owner, light_pos}
      end
    end
  end

  defp maybe_chaos(owner, light_pos, chaos_timer) when chaos_timer < @chaos_every do
    {owner, light_pos, chaos_timer}
  end

  defp maybe_chaos(_owner, light_pos, _chaos_timer) do
    # Chaos: force drop + small teleport
    pos = jitter(light_pos)
    {nil, pos, 0}
  end

  defp distance(pos_a, pos_b) do
    {x1, y1} = normalize_pos(pos_a)
    {x2, y2} = normalize_pos(pos_b)
    :math.sqrt(:math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2))
  end

  defp jitter({x, y}) do
    {clamp(x + (:rand.uniform() - 0.5) * 12.0, 5.0, 95.0),
     clamp(y + (:rand.uniform() - 0.5) * 12.0, 5.0, 95.0)}
  end

  defp owner_pos(players, owner) do
    case Map.get(players, owner) do
      nil -> nil
      %{pos: pos} -> normalize_pos(pos)
    end
  end

  defp normalize_pos({x, y}) when is_number(x) and is_number(y), do: {x * 1.0, y * 1.0}
  defp normalize_pos([x, y]) when is_number(x) and is_number(y), do: {x * 1.0, y * 1.0}
  defp normalize_pos(_), do: {0.0, 0.0}

  defp clamp(val, min, _max) when val < min, do: min
  defp clamp(val, _min, max) when val > max, do: max
  defp clamp(val, _min, _max), do: val
end
