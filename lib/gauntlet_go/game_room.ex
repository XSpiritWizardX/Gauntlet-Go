defmodule GauntletGo.GameRoom do
  @moduledoc """
  Authoritative game state per room.
  """

  use GenServer

  alias GauntletGo.{Leader, Player, Rounds, Snapshot}
  @tick_ms 100
  @dt @tick_ms / 1000
  @cycle_ms 360_000
  @countdown_ms 5_000
  @max_players 10

  @round_durations %{
    r1_survival: 120_000,
    r2_light: 120_000,
    r3_leak: 120_000
  }

  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, %{room_id: room_id}, name: via(room_id))
  end

  def join(room_id, player_id, name \\ nil, color \\ nil) do
    GenServer.call(via(room_id), {:join, player_id, name, color})
  end

  def leave(room_id, player_id) do
    GenServer.cast(via(room_id), {:leave, player_id})
  end

  def input(room_id, player_id, input) do
    GenServer.cast(via(room_id), {:input, player_id, input})
  end

  def force_round(room_id, round) do
    GenServer.call(via(room_id), {:force_round, round})
  end

  @impl true
  def init(%{room_id: room_id}) do
    round = :r1_survival

    state = %{
      room_id: room_id,
      status: :idle,
      round: round,
      round_state: Rounds.init_round(round),
      round_elapsed_ms: 0,
      players: %{},
      leader_id: nil,
      match_started_at_ms: nil,
      countdown_until_ms: nil,
      countdown_round: nil,
      countdown_reset_scores: false,
      manual_round: nil
    }

    :timer.send_interval(@tick_ms, :tick)
    {:ok, state}
  end

  @impl true
  def handle_call({:join, player_id, name, color}, _from, state) do
    cond do
      map_size(state.players) >= @max_players and not Map.has_key?(state.players, player_id) ->
        {:reply, {:error, :room_full}, state}

      true ->
        chosen_color = unique_color(state.players, player_id, color)

        players =
          Map.update(state.players, player_id, Player.new(player_id, color: chosen_color), fn p ->
            p
            |> Map.put(:name, name || player_id)
            |> Map.put(:color, unique_color(state.players, player_id, color, p.color))
          end)

        new_state =
          state
          |> Map.put(:players, players)
          |> maybe_start_match()
          |> update_leader()

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:force_round, round}, _from, state) do
    case normalize_round(round) do
      nil ->
        {:reply, {:error, :invalid_round}, state}

      round_atom ->
        state = %{state | manual_round: round_atom}
        {:reply, :ok, begin_countdown(state, round_atom)}
    end
  end

  @impl true
  def handle_cast({:leave, player_id}, state) do
    {:noreply, %{state | players: Map.delete(state.players, player_id)}}
  end

  @impl true
  def handle_cast({:input, player_id, input}, state) do
    players =
      Map.update(state.players, player_id, Player.new(player_id), fn player ->
        Player.apply_input(player, sanitize_input(input))
      end)

    {:noreply, %{state | players: players}}
  end

  @impl true
  def handle_info(:tick, state) do
    state =
      state
      |> maybe_restart_cycle()
      |> maybe_start_match()
      |> tick_countdown()
      |> tick_players()
      |> tick_round()
      |> maybe_advance_round()
      |> update_leader()
      |> maybe_broadcast()

    {:noreply, state}
  end

  defp tick_players(state) do
    if state.status != :active or map_size(state.players) == 0 do
      state
    else
      speed =
        case state.round do
          :r3_leak -> 38.0
          :r2_light -> 32.0
          _ -> 34.0
        end

      bounds =
        case state.round do
          :r3_leak -> {130.0, 100.0}
          _ -> {100.0, 100.0}
        end

      players =
        Enum.reduce(state.players, state.players, fn {id, player}, acc ->
          updated = Player.tick(player, @dt, speed: speed, bounds: bounds)
          Map.put(acc, id, updated)
        end)

      %{state | players: players}
    end
  end

  defp tick_round(state) do
    if state.status != :active or map_size(state.players) == 0 do
      state
    else
      %{players: players, round_state: round_state} =
        Rounds.tick(state.round, state.players, state.round_state, @dt)

      %{
        state
        | players: players,
          round_state: round_state,
          round_elapsed_ms: state.round_elapsed_ms + @tick_ms
      }
    end
  end

  defp maybe_advance_round(%{round: :done} = state), do: state

  defp maybe_advance_round(state) do
    if state.status != :active or map_size(state.players) == 0 do
      state
    else
      duration = Map.fetch!(@round_durations, state.round)

      finished? =
        Rounds.finished?(
          state.round,
          state.players,
          state.round_state,
          state.round_elapsed_ms,
          duration
        )

      if finished? do
        finish_round(state)
      else
        state
      end
    end
  end

  defp finish_round(%{round: :r3_leak} = state) do
    players = Rounds.on_round_end(state.round, state.players, state.round_state)
    broadcast_game_over(state, players)

    %{
      state
      | round: :done,
        players: players,
        manual_round: nil
    }
  end

  defp finish_round(state) do
    next_round = next_round(state.round)
    players = Rounds.on_round_end(state.round, state.players, state.round_state)

    begin_countdown(%{state | players: players}, next_round)
  end

  defp reset_players_for_round(players, round, reset_scores \\ false)

  defp reset_players_for_round(players, :r1_survival, reset_scores) do
    Enum.into(players, %{}, fn {id, p} ->
      player = Player.reset_for_round(p, {50.0, 50.0})
      player = if reset_scores, do: %{player | score: 0.0}, else: player
      {id, player}
    end)
  end

  defp reset_players_for_round(players, :r2_light, reset_scores) do
    Enum.into(players, %{}, fn {id, p} ->
      player = Player.reset_for_round(p, {50.0, 50.0})
      player = if reset_scores, do: %{player | score: 0.0}, else: player
      {id, player}
    end)
  end

  defp reset_players_for_round(players, :r3_leak, reset_scores) do
    Enum.into(players, %{}, fn {id, p} ->
      player = Player.reset_for_round(p, {0.0, 50.0})
      player = if reset_scores, do: %{player | score: 0.0}, else: player
      {id, player}
    end)
  end

  defp reset_players_for_round(players, _round, _reset_scores), do: players

  defp next_round(:r1_survival), do: :r2_light
  defp next_round(:r2_light), do: :r3_leak
  defp next_round(_), do: :done

  defp update_leader(state) do
    %{state | leader_id: Leader.calc(state.players)}
  end

  defp maybe_broadcast(state) do
    topic = "game:#{state.room_id}"

    GauntletGoWeb.Endpoint.broadcast!(topic, "snapshot", Snapshot.build(state))
    state
  end

  defp broadcast_game_over(state, players) do
    topic = "game:#{state.room_id}"
    GauntletGoWeb.Endpoint.broadcast!(topic, "game_over", Snapshot.build_game_over(players))
  end

  defp maybe_start_match(%{status: status} = state) when status != :idle, do: state
  defp maybe_start_match(%{manual_round: round} = state) when not is_nil(round), do: state
  defp maybe_start_match(%{round: round} = state) when round not in [:r1_survival, :done],
    do: state

  defp maybe_start_match(state) do
    if map_size(state.players) >= @max_players do
      begin_countdown(state, :r1_survival, reset_scores: true)
    else
      state
    end
  end

  defp maybe_restart_cycle(%{status: :idle} = state), do: state
  defp maybe_restart_cycle(%{round: round} = state) when round != :done, do: state

  defp maybe_restart_cycle(state) do
    now = System.system_time(:millisecond)

    should_restart =
      state.match_started_at_ms &&
        now - state.match_started_at_ms >= @cycle_ms

    if should_restart do
      %{state | status: :idle}
    else
      state
    end
  end

  defp tick_countdown(%{status: :countdown, countdown_until_ms: until_ms} = state)
       when is_integer(until_ms) do
    now = System.system_time(:millisecond)

    if now >= until_ms do
      start_round(state)
    else
      state
    end
  end

  defp tick_countdown(state), do: state

  defp start_round(%{countdown_round: round} = state) when round in [:r1_survival, :r2_light, :r3_leak] do
    now = System.system_time(:millisecond)
    match_started_at_ms =
      if state.countdown_reset_scores or is_nil(state.match_started_at_ms) do
        now
      else
        state.match_started_at_ms
      end

    %{
      state
      | status: :active,
        round: round,
        round_state: Rounds.init_round(round),
        round_elapsed_ms: 0,
        countdown_until_ms: nil,
        countdown_round: nil,
        countdown_reset_scores: false,
        manual_round: nil,
        match_started_at_ms: match_started_at_ms
    }
  end

  defp start_round(state),
    do: %{
      state
      | status: :active,
        countdown_until_ms: nil,
        countdown_round: nil,
        manual_round: nil
    }

  defp begin_countdown(state, round, opts \\ []) do
    reset_scores = Keyword.get(opts, :reset_scores, false)
    now = System.system_time(:millisecond)

    %{
      state
      | status: :countdown,
        round: round,
        round_state: Rounds.init_round(round),
        round_elapsed_ms: 0,
        countdown_until_ms: now + @countdown_ms,
        countdown_round: round,
        countdown_reset_scores: reset_scores,
        players: reset_players_for_round(state.players, round, reset_scores)
    }
  end

  defp via(room_id), do: {:via, Registry, {GauntletGo.RoomRegistry, room_id}}

  defp unique_color(players, player_id, desired_color, current_color \\ nil) do
    taken =
      players
      |> Enum.reject(fn {id, _player} -> id == player_id end)
      |> Enum.map(fn {_id, player} -> player.color end)
      |> MapSet.new()

    available =
      Player.colors()
      |> Enum.reject(fn color -> MapSet.member?(taken, color) end)

    desired_valid = Player.valid_color?(desired_color)
    desired_free = desired_valid and not MapSet.member?(taken, desired_color)

    current_valid = Player.valid_color?(current_color)
    current_free = current_valid and not MapSet.member?(taken, current_color)

    cond do
      desired_free -> desired_color
      current_free -> current_color
      available != [] -> List.first(available)
      desired_valid -> desired_color
      current_valid -> current_color
      true -> List.first(Player.colors())
    end
  end

  defp normalize_round("r1_survival"), do: :r1_survival
  defp normalize_round("r2_light"), do: :r2_light
  defp normalize_round("r3_leak"), do: :r3_leak
  defp normalize_round(:r1_survival), do: :r1_survival
  defp normalize_round(:r2_light), do: :r2_light
  defp normalize_round(:r3_leak), do: :r3_leak
  defp normalize_round(_), do: nil

  defp sanitize_input(%{"move" => [mx, my], "jump" => jump, "action" => action}) do
    %{move: {mx * 1.0, my * 1.0}, jump: !!jump, action: !!action}
  end

  defp sanitize_input(%{"move" => move} = payload) when is_map(move) do
    sanitize_input(%{
      "move" => [Map.get(move, "x", 0.0), Map.get(move, "y", 0.0)],
      "jump" => Map.get(payload, "jump", false),
      "action" => Map.get(payload, "action", false)
    })
  end

  defp sanitize_input(_), do: %{move: {0.0, 0.0}, jump: false, action: false}
end
