# Session Monitor verification (2026-07-22T14:32Z)

## Agent-run results (no “please check yourself”)

| Check | Result | Detail |
|-------|--------|--------|
| Island process + window | PASS | bounds `{'X': 1182.0, 'Height': 34.0, 'Y': 31.0, 'Width': 196.0}` |
| Near top (curtain region) | PASS | Y=31.0 |
| Expand ⌘⇧A | PASS | height=420.0 |
| Collapse Esc | FAIL | height after=420.0 |
| Hub focus via commands.jsonl | PASS | active=`4a2ef8f6-b192-426d-ab1a-3f1dc712e73b` target=`4a2ef8f6-b192-426d-ab1a-3f1dc712e73b` |
| Hub reply via commands.jsonl | PASS | state=True events=True |

## Apps left running for you

- SessionMonitor.app (menu-bar island)
- Chat Hub (`pnpm dev`)

## What works in the island UI right now

1. Top-center island (pill / expanded)
2. Click session → writes `session.focus` (opens chat if Hub running)
3. Waiting sessions → Allow/Deny + text reply → `session.reply`
4. OS notifications on waiting/done/error
