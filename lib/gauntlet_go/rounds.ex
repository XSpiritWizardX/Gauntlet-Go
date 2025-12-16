defmodule GauntletGo.Rounds do
  @moduledoc false

  alias GauntletGo.Rounds.{Leak, Light, Survival}

  def init_round(:r1_survival), do: Survival.init_round()
  def init_round(:r2_light), do: Light.init_round()
  def init_round(:r3_leak), do: Leak.init_round()
  def init_round(_), do: %{}

  def tick(:r1_survival, players, round_state, dt) do
    Survival.tick(players, round_state, dt)
  end

  def tick(:r2_light, players, round_state, dt) do
    Light.tick(players, round_state, dt)
  end

  def tick(:r3_leak, players, round_state, dt) do
    Leak.tick(players, round_state, dt)
  end

  def tick(_, players, round_state, _dt) do
    %{players: players, round_state: round_state}
  end

  def finished?(:r1_survival, players, round_state, elapsed_ms, duration_ms),
    do: Survival.finished?(players, round_state, elapsed_ms, duration_ms)

  def finished?(:r2_light, players, round_state, elapsed_ms, duration_ms),
    do: Light.finished?(players, round_state, elapsed_ms, duration_ms)

  def finished?(:r3_leak, players, round_state, elapsed_ms, duration_ms),
    do: Leak.finished?(players, round_state, elapsed_ms, duration_ms)

  def finished?(_, _players, _round_state, _elapsed_ms, _duration_ms), do: true

  def on_round_end(:r1_survival, players, round_state),
    do: Survival.on_round_end(players, round_state)

  def on_round_end(:r2_light, players, round_state),
    do: Light.on_round_end(players, round_state)

  def on_round_end(:r3_leak, players, round_state),
    do: Leak.on_round_end(players, round_state)

  def on_round_end(_, players, _round_state), do: players
end
