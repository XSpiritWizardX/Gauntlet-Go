import {Socket} from "phoenix"

const state = {
  socket: null,
  channel: null,
  playerId: null,
  snapshot: null,
  gameOver: null,
  input: {move: {x: 0, y: 0}, jump: false, action: false},
  roomId: "family",
  name: "",
  color: null
}

const canvas = () => document.getElementById("game-canvas")
const joinForm = () => document.getElementById("join-form")
const roomInput = () => document.getElementById("room-id")
const nameInput = () => document.getElementById("player-name")
const colorInput = () => document.querySelector('input[name="player-color"]:checked')
const joinStatus = () => document.getElementById("join-status")
const leaderboardEl = () => document.getElementById("leaderboard")
const roundEl = () => document.getElementById("round-label")
const timerEl = () => document.getElementById("timer-label")
const crownEl = () => document.getElementById("crown-label")
const overlay = () => document.getElementById("game-over")
const overlayList = () => document.getElementById("game-over-list")
const countdownOverlay = () => document.getElementById("round-countdown")
const countdownLabel = () => document.getElementById("round-countdown-label")
const countdownTimer = () => document.getElementById("round-countdown-timer")
const aiCountInput = () => document.getElementById("ai-count")
const aiAddBtn = () => document.getElementById("ai-add-btn")
const aiClearBtn = () => document.getElementById("ai-clear-btn")
const aiStatus = () => document.getElementById("ai-status")
const round1Btn = () => document.getElementById("round-1-btn")
const round2Btn = () => document.getElementById("round-2-btn")
const round3Btn = () => document.getElementById("round-3-btn")
let runtime = null
const botState = {bots: [], counter: 0}

function setup() {
  if (window.__gauntletGameTeardown) window.__gauntletGameTeardown()
  runtime = {listeners: [], animationFrameId: null, inputIntervalId: null}

  const addListener = (el, event, handler, options) => {
    if (!el) return
    el.addEventListener(event, handler, options)
    runtime.listeners.push(() => el.removeEventListener(event, handler, options))
  }

  addListener(joinForm(), "submit", (e) => {
    e.preventDefault()
    connect()
  })
  addListener(aiAddBtn(), "click", (e) => {
    e.preventDefault()
    addBotsFromInput()
  })
  addListener(aiClearBtn(), "click", (e) => {
    e.preventDefault()
    clearBots()
  })
  addListener(round1Btn(), "click", () => forceRound("r1_survival"))
  addListener(round2Btn(), "click", () => forceRound("r2_light"))
  addListener(round3Btn(), "click", () => forceRound("r3_leak"))

  setupControls(addListener)
  addListener(window, "resize", resizeCanvas)
  resizeCanvas()
  renderLoop()
  runtime.inputIntervalId = setInterval(pushInput, 80)
  updateAiStatus()

  window.__gauntletGameTeardown = () => {
    runtime.listeners.forEach((off) => off())
    if (runtime.animationFrameId) cancelAnimationFrame(runtime.animationFrameId)
    if (runtime.inputIntervalId) clearInterval(runtime.inputIntervalId)
    clearBots()
    runtime = null
  }
}

function connect() {
  const roomId = roomInput()?.value?.trim() || "family"
  const name = nameInput()?.value?.trim() || "player"
  const color = colorInput()?.value || null

  if (state.channel) {
    state.channel.leave()
  }

  state.roomId = roomId
  state.name = name
  state.color = color
  state.socket = new Socket("/socket", {
    params: {player_id: state.playerId || null}
  })
  state.socket.connect()
  const channel = state.socket.channel(`game:${roomId}`, {
    player_id: state.playerId || null,
    name,
    color
  })
  channel.on("snapshot", handleSnapshot)
  channel.on("game_over", handleGameOver)
  channel
    .join()
    .receive("ok", (resp) => {
      state.playerId = resp.player_id
      updateJoinStatus(`Joined room ${roomId} as ${state.playerId}`)
    })
    .receive("error", () => updateJoinStatus("Unable to join room"))
  state.channel = channel
}

function handleSnapshot(payload) {
  state.snapshot = payload
  state.gameOver = null
  renderLeaderboard(payload.players)
  syncColorChoices(payload.players)
  updateCountdown(payload)

  if (roundEl()) roundEl().textContent = labelForRound(payload.round)
  if (timerEl()) timerEl().textContent = `T+ ${(payload.round_elapsed_ms / 1000).toFixed(1)}s`
  if (crownEl()) crownEl().textContent = payload.leader_id ? `👑 ${payload.leader_id}` : "No leader"
  hideOverlay()
}

function handleGameOver(payload) {
  state.gameOver = payload
  if (overlayList()) {
    overlayList().innerHTML = ""
    payload.leaderboard.forEach((entry, idx) => {
      const li = document.createElement("li")
      li.textContent = `${idx + 1}. ${entry.name || entry.id} — ${entry.score}`
      overlayList().appendChild(li)
    })
  }
  showOverlay()
}

function pushInput() {
  if (!state.channel) return
  state.channel.push("input", {
    move: [state.input.move.x, state.input.move.y],
    jump: state.input.jump,
    action: state.input.action
  })
  state.input.jump = false
  state.input.action = false
}

function setupControls(addListener) {
  const stick = document.getElementById("joystick-area")
  const thumb = document.getElementById("joystick-thumb")
  let activeId = null

  if (stick) {
    const onPointerDown = (e) => {
      activeId = e.pointerId
      stick.setPointerCapture(activeId)
      updateMoveFromEvent(stick, thumb, e)
    }
    const onPointerMove = (e) => {
      if (activeId === e.pointerId) updateMoveFromEvent(stick, thumb, e)
    }
    const reset = () => {
      activeId = null
      state.input.move = {x: 0, y: 0}
      if (thumb) thumb.style.transform = "translate(-50%, -50%)"
    }
    addListener(stick, "pointerdown", onPointerDown)
    addListener(stick, "pointermove", onPointerMove)
    addListener(stick, "pointerup", reset)
    addListener(stick, "pointercancel", reset)
    addListener(stick, "pointerleave", reset)
  }

  const jumpBtn = document.getElementById("jump-btn")
  const actionBtn = document.getElementById("action-btn")
  addListener(jumpBtn, "pointerdown", () => (state.input.jump = true))
  addListener(actionBtn, "pointerdown", () => (state.input.action = true))
}

function updateMoveFromEvent(stick, thumb, e) {
  const rect = stick.getBoundingClientRect()
  const cx = rect.left + rect.width / 2
  const cy = rect.top + rect.height / 2
  const dx = e.clientX - cx
  const dy = e.clientY - cy
  const max = rect.width / 2
  const clamp = (v) => Math.max(-1, Math.min(1, v))
  state.input.move = {x: clamp(dx / max), y: clamp(dy / max)}
  if (thumb) {
    thumb.style.transform = `translate(calc(-50% + ${dx * 0.3}px), calc(-50% + ${dy * 0.3}px))`
  }
}

function updateCountdown(payload) {
  if (!countdownOverlay()) return
  const ms = payload.countdown_ms || 0

  if (ms > 0) {
    const seconds = Math.max(1, Math.ceil(ms / 1000))
    const nextRound = payload.countdown_round || payload.round
    if (countdownTimer()) countdownTimer().textContent = seconds
    if (countdownLabel()) {
      countdownLabel().textContent = `${labelForRound(nextRound)} starts in`
    }
    countdownOverlay().removeAttribute("hidden")
  } else {
    countdownOverlay().setAttribute("hidden", "")
  }
}

function forceRound(round) {
  if (!state.channel) {
    updateJoinStatus("Join a room before forcing a round.")
    return
  }

  state.channel.push("force_round", {round})
}

function syncColorChoices(players) {
  const inputs = [...document.querySelectorAll('input[name="player-color"]')]
  if (inputs.length === 0) return

  const taken = new Map()
  players.forEach((player) => {
    if (player.color) taken.set(player.color, player.id)
  })

  const ownId = state.playerId
  const ownEntry = players.find((player) => player.id === ownId)
  const ownColor = ownEntry?.color
  const disabledClasses = ["opacity-40", "cursor-not-allowed"]

  let firstAvailable = null
  inputs.forEach((input) => {
    const ownerId = taken.get(input.value)
    const isTaken = ownerId && ownerId !== ownId
    if (!isTaken && !firstAvailable) firstAvailable = input
  })

  inputs.forEach((input) => {
    const ownerId = taken.get(input.value)
    const isTaken = ownerId && ownerId !== ownId
    input.disabled = !!isTaken
    const label = input.closest("label")
    if (label) {
      if (isTaken) label.classList.add(...disabledClasses)
      else label.classList.remove(...disabledClasses)
    }
  })

  if (ownColor) {
    const match = inputs.find((input) => input.value === ownColor)
    if (match) match.checked = true
    return
  }

  const checked = inputs.find((input) => input.checked)
  if (checked && checked.disabled && firstAvailable) firstAvailable.checked = true
}

function addBotsFromInput() {
  const input = aiCountInput()
  const requested = Number.parseInt(input?.value, 10)
  const count = Number.isFinite(requested) ? requested : 1
  const normalized = Math.max(1, Math.min(9, count))

  if (input) input.value = normalized

  const remaining = 9 - botState.bots.length
  if (remaining <= 0) {
    updateAiStatus("Max AI reached.")
    return
  }

  const roomId = roomInput()?.value?.trim() || state.roomId || "family"
  const toAdd = Math.min(normalized, remaining)

  for (let i = 0; i < toAdd; i += 1) {
    const bot = createBot(roomId)
    botState.bots.push(bot)
  }

  if (toAdd < normalized) updateAiStatus("Room cap reached.")
  else updateAiStatus()
}

function clearBots() {
  botState.bots.forEach((bot) => teardownBot(bot))
  botState.bots = []
  updateAiStatus("AI cleared.")
}

function createBot(roomId) {
  botState.counter += 1
  const botIndex = botState.counter
  const botId = `ai_${botIndex}_${Date.now()}`
  const name = `AI ${botIndex}`
  const color = pickBotColor(botIndex)
  const socket = new Socket("/socket", {
    params: {player_id: botId}
  })

  socket.connect()
  const channel = socket.channel(`game:${roomId}`, {
    player_id: botId,
    name,
    color
  })

  const bot = {id: botId, socket, channel, intervalId: null}

  channel
    .join()
    .receive("ok", () => {
      bot.intervalId = startBotLoop(channel)
      updateAiStatus()
    })
    .receive("error", () => {
      teardownBot(bot)
      botState.bots = botState.bots.filter((entry) => entry !== bot)
      updateAiStatus("Room full or unavailable.")
    })

  return bot
}

function teardownBot(bot) {
  if (bot.intervalId) clearInterval(bot.intervalId)
  if (bot.channel) bot.channel.leave()
  if (bot.socket) bot.socket.disconnect()
}

function startBotLoop(channel) {
  let move = randomMove()
  let nextChangeAt = Date.now() + randomBetween(400, 900)

  return setInterval(() => {
    const now = Date.now()
    if (now >= nextChangeAt) {
      move = randomMove()
      nextChangeAt = now + randomBetween(400, 900)
    }

    channel.push("input", {
      move: [move.x, move.y],
      jump: Math.random() < 0.05,
      action: Math.random() < 0.06
    })
  }, 120)
}

function randomMove() {
  if (Math.random() < 0.2) return {x: 0, y: 0}
  const angle = Math.random() * Math.PI * 2
  return {x: Math.cos(angle), y: Math.sin(angle)}
}

function randomBetween(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

function pickBotColor(idx) {
  const palette = [...document.querySelectorAll('input[name="player-color"]')]
    .map((input) => input.value)
    .filter(Boolean)
  if (palette.length === 0) return "#38bdf8"
  return palette[idx % palette.length]
}

function updateAiStatus(message) {
  if (!aiStatus()) return
  const total = botState.bots.length
  const label = `${total} AI opponent${total === 1 ? "" : "s"}`
  aiStatus().textContent = message ? `${label} · ${message}` : label
}

function renderLoop() {
  render()
  if (runtime) runtime.animationFrameId = requestAnimationFrame(renderLoop)
}

function render() {
  const c = canvas()
  if (!c || !state.snapshot) return
  const ctx = c.getContext("2d")
  ctx.imageSmoothingEnabled = false
  const snap = state.snapshot
  const worldW = snap.round === "r3_leak" ? 130 : 100
  const worldH = 100
  ctx.clearRect(0, 0, c.width, c.height)
  ctx.fillStyle = "#0b1221"
  ctx.fillRect(0, 0, c.width, c.height)
  drawCheckerboard(ctx, c.width, c.height, 32)

  const scaleX = c.width / worldW
  const scaleY = c.height / worldH
  const toScreen = (pos) => [pos[0] * scaleX, pos[1] * scaleY]

  drawRoundSpecific(ctx, snap, toScreen, scaleX, scaleY, worldW, worldH)

  snap.players.forEach((p) => {
    const [x, y] = toScreen(p.pos)
    const size = 18
    const half = size / 2
    ctx.fillStyle = p.color || "#38bdf8"
    ctx.fillRect(x - half, y - half, size, size)
  })
}

function drawCheckerboard(ctx, width, height, cellSize) {
  const colorA = "rgba(15, 23, 42, 0.55)"
  const colorB = "rgba(30, 41, 59, 0.55)"
  const cols = Math.ceil(width / cellSize)
  const rows = Math.ceil(height / cellSize)

  for (let y = 0; y < rows; y += 1) {
    for (let x = 0; x < cols; x += 1) {
      ctx.fillStyle = (x + y) % 2 === 0 ? colorA : colorB
      ctx.fillRect(x * cellSize, y * cellSize, cellSize, cellSize)
    }
  }
}

function drawRoundSpecific(ctx, snap, toScreen, scaleX, scaleY, worldW, worldH) {
  const widthPx = ctx.canvas.width
  const heightPx = ctx.canvas.height

  if (snap.round === "r1_survival") {
    ctx.fillStyle = "rgba(56,189,248,0.08)"
    ctx.fillRect(0, 0, widthPx, heightPx)
    snap.round_state.pickups?.forEach((p) => {
      const [x, y] = toScreen(p.pos)
      ctx.fillStyle = "#34d399"
      ctx.beginPath()
      ctx.arc(x, y, 6, 0, Math.PI * 2)
      ctx.fill()
    })
    snap.round_state.hazards?.forEach((hz) => {
      const [x, y] = toScreen(hz.pos)
      ctx.fillStyle = "#f43f5e"
      ctx.beginPath()
      ctx.arc(x, y, 8, 0, Math.PI * 2)
      ctx.fill()
    })
  } else if (snap.round === "r2_light") {
    ctx.fillStyle = "rgba(244,114,182,0.08)"
    ctx.fillRect(0, 0, widthPx, heightPx)
    if (snap.round_state.light_pos) {
      const [x, y] = toScreen(snap.round_state.light_pos)
      ctx.save()
      ctx.shadowColor = "rgba(252, 211, 77, 0.75)"
      ctx.shadowBlur = 28
      ctx.fillStyle = "#fcd34d"
      ctx.beginPath()
      ctx.arc(x, y, 10, 0, Math.PI * 2)
      ctx.fill()
      ctx.restore()
      ctx.strokeStyle = "#f59e0b"
      ctx.lineWidth = 3
      ctx.stroke()
    }
  } else if (snap.round === "r3_leak") {
    ctx.fillStyle = "rgba(16,185,129,0.08)"
    ctx.fillRect(0, 0, widthPx, heightPx)
    ctx.strokeStyle = "#22c55e"
    ctx.lineWidth = 3
    const finishX = (snap.round_state.finish_x || 120) * scaleX
    ctx.beginPath()
    ctx.moveTo(finishX, 0)
    ctx.lineTo(finishX, heightPx)
    ctx.stroke()
    snap.round_state.obstacles?.forEach((ob) => {
      const y1 = ob.y1 ?? 0
      const y2 = ob.y2 ?? worldH
      ctx.fillStyle = "#f97316"
      ctx.fillRect(
        ob.x1 * scaleX,
        y1 * scaleY,
        (ob.x2 - ob.x1) * scaleX,
        (y2 - y1) * scaleY
      )
    })
  }
}

function renderLeaderboard(players) {
  if (!leaderboardEl()) return
  const sorted = [...players].sort((a, b) => b.score - a.score)
  leaderboardEl().innerHTML = sorted
    .slice(0, 5)
    .map((p, idx) => `<li>${idx + 1}. ${p.name || p.id} — ${p.score}</li>`)
    .join("")
}

function updateJoinStatus(text) {
  if (joinStatus()) joinStatus().textContent = text
}

function labelForRound(round) {
  switch (round) {
    case "r1_survival":
      return "Round 1: Survival Rush"
    case "r2_light":
      return "Round 2: Carry the Light"
    case "r3_leak":
      return "Round 3: Leak Run"
    case "done":
      return "Game Over"
    default:
      return "Waiting"
  }
}

function resizeCanvas() {
  const c = canvas()
  if (!c) return
  const rect = c.getBoundingClientRect()
  c.width = rect.width
  c.height = rect.height
}

function showOverlay() {
  if (overlay()) overlay().removeAttribute("hidden")
}

function hideOverlay() {
  if (overlay()) overlay().setAttribute("hidden", "")
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", setup)
} else {
  setup()
}
