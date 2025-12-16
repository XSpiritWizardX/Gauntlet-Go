defmodule GauntletGo.GameRoom do
  @moduledoc """
  Authoritative game state per room.
  """

  use GenServer

  alias GauntletGo.{Leader, Player, Rounds, Snapshot}
  @tick_ms 100
  @dt @tick_ms / 1000
  @cycle_ms 300_000
  @max_players 10

  @round_durations %{
    r1_survival: 45_000,
    r2_light: 60_000,
    r3_leak: 70_000
  }

  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, %{room_id: room_id}, name: via(room_id))
  end

  def join(room_id, player_id, name \\ nil) do
    GenServer.call(via(room_id), {:join, player_id, name})
  end

  def leave(room_id, player_id) do
    GenServer.cast(via(room_id), {:leave, player_id})
  end

  def input(room_id, player_id, input) do
    GenServer.cast(via(room_id), {:input, player_id, input})
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
      match_started_at_ms: nil
    }

    :timer.send_interval(@tick_ms, :tick)
    {:ok, state}
  end

  @impl true
  def handle_call({:join, player_id, name}, _from, state) do
    cond do
      map_size(state.players) >= @max_players ->
        {:reply, {:error, :room_full}, state}

      true ->
        players =
          Map.update(state.players, player_id, Player.new(player_id), fn p ->
            %{p | name: name || player_id}
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
      |> tick_players()
      |> tick_round()
      |> maybe_advance_round()
      |> update_leader()
      |> maybe_broadcast()

    {:noreply, state}
  end

  defp tick_players(state) do
    if state.status == :idle or map_size(state.players) == 0 do
      state
    else
      speed =
        case state.round do
          :r3_leak -> 45.0
          :r2_light -> 36.0
          _ -> 40.0
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
    if state.status == :idle or map_size(state.players) == 0 do
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
    if state.status == :idle or map_size(state.players) == 0 do
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
        players: players
    }
  end

  defp finish_round(state) do
    next_round = next_round(state.round)
    players = Rounds.on_round_end(state.round, state.players, state.round_state)

    %{
      state
      | round: next_round,
        round_state: Rounds.init_round(next_round),
        round_elapsed_ms: 0,
        players: reset_players_for_round(players, next_round)
    }
  end

  defp reset_players_for_round(players, :r1_survival),
    do: Enum.into(players, %{}, fn {id, p} -> {id, Player.reset_for_round(p, {50.0, 50.0})} end)

  defp reset_players_for_round(players, :r2_light),
    do: Enum.into(players, %{}, fn {id, p} -> {id, Player.reset_for_round(p, {50.0, 50.0})} end)

  defp reset_players_for_round(players, :r3_leak),
    do: Enum.into(players, %{}, fn {id, p} -> {id, Player.reset_for_round(p, {0.0, 50.0})} end)

  defp reset_players_for_round(players, _), do: players

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

  defp maybe_start_match(%{status: :active} = state), do: state

  defp maybe_start_match(state) do
    if map_size(state.players) > 0 do
      now = System.system_time(:millisecond)

      players =
        Enum.into(state.players, %{}, fn {id, p} ->
          {id, %{Player.reset_for_round(p, {50.0, 50.0}) | score: 0.0}}
        end)

      %{
        state
        | status: :active,
          round: :r1_survival,
          round_state: Rounds.init_round(:r1_survival),
          round_elapsed_ms: 0,
          match_started_at_ms: now,
          players: players
      }
    else
      state
    end
  end

  defp maybe_restart_cycle(%{status: :idle} = state), do: state

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

  defp via(room_id), do: {:via, Registry, {GauntletGo.RoomRegistry, room_id}}

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
