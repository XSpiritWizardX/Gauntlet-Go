defmodule GauntletGo.Player do
  @moduledoc """
  Minimal server-side representation of a player.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          color: String.t(),
          score: float(),
          pos: {float(), float()},
          input: %{move: {float(), float()}, jump: boolean(), action: boolean()},
          jump_timer: float(),
          jump_cooldown: float(),
          alive?: boolean(),
          carrying_light?: boolean(),
          finished_at_ms: non_neg_integer() | nil
        }

  defstruct [
    :id,
    :name,
    :color,
    score: 0.0,
    pos: {0.0, 0.0},
    input: %{move: {0.0, 0.0}, jump: false, action: false},
    jump_timer: 0.0,
    jump_cooldown: 0.0,
    alive?: true,
    carrying_light?: false,
    finished_at_ms: nil
  ]

  @colors ~w[#22c55e #3b82f6 #f97316 #ef4444 #a855f7 #eab308 #06b6d4 #ec4899 #8b5cf6 #f59e0b]

  def colors, do: @colors

  def new(id, opts \\ []) do
    color = Keyword.get(opts, :color)

    %__MODULE__{
      id: id,
      name: id,
      color: normalize_color(color),
      pos: {10.0, 10.0}
    }
  end

  def maybe_update_color(player, color) do
    if valid_color?(color) do
      %{player | color: color}
    else
      player
    end
  end

  def valid_color?(color) when is_binary(color), do: color in @colors
  def valid_color?(_), do: false

  def reset_for_round(player, pos \\ {10.0, 10.0}) do
    %__MODULE__{
      player
      | pos: pos,
        input: %{move: {0.0, 0.0}, jump: false, action: false},
        jump_timer: 0.0,
        jump_cooldown: 0.0,
        alive?: true,
        carrying_light?: false,
        finished_at_ms: nil
    }
  end

  def apply_input(player, %{move: move, jump: jump, action: action}) do
    %{player | input: %{move: clamp_move(move), jump: jump, action: action}}
  end

  def tick(player, dt, opts \\ []) do
    if not player.alive? do
      player
    else
      speed = Keyword.get(opts, :speed, 40.0)
      {max_x, max_y} = Keyword.get(opts, :bounds, {100.0, 100.0})

      {mx, my} = player.input.move
      {x, y} = player.pos

      jump_timer = decrement(player.jump_timer, dt)
      jump_cd = decrement(player.jump_cooldown, dt)

      {jump_timer, jump_cd} =
        if player.input.jump && jump_cd <= 0.0 do
          {0.35, 0.35}
        else
          {jump_timer, jump_cd}
        end

      airborne? = jump_timer > 0.0
      friction = if airborne?, do: 0.6, else: 1.0

      nx = x + mx * speed * dt * friction
      ny = y + my * speed * dt * friction

      %{
        player
        | pos: {clamp(nx, 0.0, max_x), clamp(ny, 0.0, max_y)},
          jump_timer: jump_timer,
          jump_cooldown: jump_cd
      }
    end
  end

  def airborne?(%__MODULE__{jump_timer: t}), do: t > 0.0

  defp decrement(val, _dt) when val <= 0.0, do: 0.0
  defp decrement(val, dt), do: max(val - dt, 0.0)

  defp clamp_move({mx, my}) do
    {clamp(mx, -1.0, 1.0), clamp(my, -1.0, 1.0)}
  end

  defp clamp(val, min, _max) when val < min, do: min
  defp clamp(val, _min, max) when val > max, do: max
  defp clamp(val, _min, _max), do: val

  defp normalize_color(color) do
    if valid_color?(color), do: color, else: Enum.random(@colors)
  end
end
