# Checks

Plain shell, no framework — run them after touching the hook or the socket.

```bash
./hook-events.sh        # every Claude hook event → expected bridge events, nothing on stdout
./permission-e2e.sh     # allow / deny / hook death / monitor down / duplicate instance
```

`hook-events.sh` needs nothing running: it drives the hook, checks the event contract
(turn end, permission summaries), and runs `install.sh` against a throwaway `$HOME` to prove
it never rewrites a config it could not parse. Non-zero exit means a check failed.

`permission-e2e.sh` drives the **Debug** build from DerivedData and uses the dev switches
documented in `docs/bridge.md` (`SESSION_MONITOR_DEBUG`, `SESSION_MONITOR_AUTO_APPROVE`).
It stops the app when it finishes — start the installed one again with
`open /Applications/SessionMonitor.app`.
