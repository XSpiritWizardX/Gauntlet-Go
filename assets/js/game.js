import {Socket} from "phoenix"

const state = {
  socket: null,
  channel: null,
  playerId: null,
  snapshot: null,
  gameOver: null,
  input: {move: {x: 0, y: 0}, jump: false, action: false},
  roomId: "family",
  name: ""
}

const canvas = () => document.getElementById("game-canvas")
const joinForm = () => document.getElementById("join-form")
const roomInput = () => document.getElementById("room-id")
const nameInput = () => document.getElementById("player-name")
const joinStatus = () => document.getElementById("join-status")
const leaderboardEl = () => document.getElementById("leaderboard")
const roundEl = () => document.getElementById("round-label")
const timerEl = () => document.getElementById("timer-label")
const crownEl = () => document.getElementById("crown-label")
const overlay = () => document.getElementById("game-over")
const overlayList = () => document.getElementById("game-over-list")

function setup() {
  if (joinForm()) {
    joinForm().addEventListener("submit", (e) => {
      e.preventDefault()
      connect()
    })
  }

  setupControls()
  window.addEventListener("resize", resizeCanvas)
  resizeCanvas()
  renderLoop()
  setInterval(pushInput, 80)
}

function connect() {
  const roomId = roomInput()?.value?.trim() || "family"
  const name = nameInput()?.value?.trim() || "player"

  if (state.channel) {
    state.channel.leave()
  }

  state.roomId = roomId
  state.name = name
  state.socket = new Socket("/socket", {params: {player_id: state.playerId || undefined}})
  state.socket.connect()
  const channel = state.socket.channel(`game:${roomId}`, {player_id: state.playerId || undefined, name})
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

function setupControls() {
  const stick = document.getElementById("joystick-area")
  const thumb = document.getElementById("joystick-thumb")
  let activeId = null

  if (stick) {
    stick.addEventListener("pointerdown", (e) => {
      activeId = e.pointerId
      stick.setPointerCapture(activeId)
      updateMoveFromEvent(stick, thumb, e)
    })
    stick.addEventListener("pointermove", (e) => {
      if (activeId === e.pointerId) updateMoveFromEvent(stick, thumb, e)
    })
    const reset = () => {
      activeId = null
      state.input.move = {x: 0, y: 0}
      if (thumb) thumb.style.transform = `translate(0px, 0px)`
    }
    stick.addEventListener("pointerup", reset)
    stick.addEventListener("pointercancel", reset)
    stick.addEventListener("pointerleave", reset)
  }

  const jumpBtn = document.getElementById("jump-btn")
  const actionBtn = document.getElementById("action-btn")
  if (jumpBtn) jumpBtn.addEventListener("pointerdown", () => (state.input.jump = true))
  if (actionBtn) actionBtn.addEventListener("pointerdown", () => (state.input.action = true))
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
  if (thumb) thumb.style.transform = `translate(${dx * 0.3}px, ${dy * 0.3}px)`
}

function renderLoop() {
  render()
  requestAnimationFrame(renderLoop)
}

function render() {
  const c = canvas()
  if (!c || !state.snapshot) return
  const ctx = c.getContext("2d")
  const snap = state.snapshot
  const worldW = snap.round === "r3_leak" ? 130 : 100
  const worldH = 100
  ctx.clearRect(0, 0, c.width, c.height)
  ctx.fillStyle = "#0b1221"
  ctx.fillRect(0, 0, c.width, c.height)

  const scaleX = c.width / worldW
  const scaleY = c.height / worldH
  const toScreen = (pos) => [pos[0] * scaleX, pos[1] * scaleY]

  drawRoundSpecific(ctx, snap, toScreen, scaleX, scaleY, worldW, worldH)

  snap.players.forEach((p) => {
    const [x, y] = toScreen(p.pos)
    const r = 10
    ctx.beginPath()
    ctx.fillStyle = p.color || "#38bdf8"
    ctx.arc(x, y, r, 0, Math.PI * 2)
    ctx.fill()
    if (!p.alive) {
      ctx.strokeStyle = "#f97316"
      ctx.lineWidth = 2
      ctx.stroke()
    }
    if (p.id === snap.leader_id) {
      ctx.fillStyle = "#ffd700"
      ctx.font = "16px sans-serif"
      ctx.fillText("👑", x - 8, y - 14)
    }
    ctx.fillStyle = "#fff"
    ctx.font = "10px sans-serif"
    ctx.fillText(p.id, x - 10, y + 16)
  })
}

function drawRoundSpecific(ctx, snap, toScreen, scaleX, _scaleY, worldW, worldH) {
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
      ctx.fillStyle = "#fcd34d"
      ctx.beginPath()
      ctx.arc(x, y, 10, 0, Math.PI * 2)
      ctx.fill()
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
      ctx.fillStyle = "#f97316"
      ctx.fillRect(ob.x1 * scaleX, 0, (ob.x2 - ob.x1) * scaleX, heightPx * 0.2)
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

document.addEventListener("DOMContentLoaded", setup)
