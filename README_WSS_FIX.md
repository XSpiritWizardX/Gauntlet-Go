# WebSocket Failures on Render? Quick Fix

If you see `Could not check origin for Phoenix.Socket transport` or browser console errors like `WebSocket connection failed`:

- Ensure `PHX_HOST=gauntlet-go.onrender.com` (host only) is set in Render env vars.
- We set `check_origin: false` in `config/runtime.exs` to allow WebSockets from Render. Redeploy after this change.

If you want stricter origin checking later, set:

```elixir
check_origin: ["//gauntlet-go.onrender.com", "https://gauntlet-go.onrender.com"]
```

and redeploy.
