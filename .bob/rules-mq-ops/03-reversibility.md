# Rule: State Whether Each Change Is Reversible

Every proposed change must be explicitly classified as REVERSIBLE,
PARTIALLY REVERSIBLE, or IRREVERSIBLE before it appears in the
MQSC Remediation Commands section.

## Reversibility Classifications

### REVERSIBLE
The change can be undone with a single MQSC command and no data is lost.

Examples:
- ALTER QLOCAL(Q) GET(ENABLED) -> reverse with GET(DISABLED)
- ALTER QLOCAL(Q) GET(DISABLED) -> reverse with GET(ENABLED)
- ALTER QLOCAL(Q) QDPHIEV(ENABLED) -> reverse with QDPHIEV(DISABLED)
- ALTER QLOCAL(Q) MAXDEPTH(x) -> reverse with ALTER QLOCAL(Q) MAXDEPTH(y)
- ALTER QLOCAL(Q) MONQ(HIGH) -> reverse with ALTER QLOCAL(Q) MONQ(OFF)
- STOP LISTENER -> reverse with START LISTENER

### PARTIALLY REVERSIBLE
The structural change can be undone but side effects cannot.

Examples:
- STOP CHANNEL: channel can be restarted but in-doubt messages may need
  manual resolution
- Rolling back a transaction (via application restart): the transaction
  state is cleared but any work done by the application is lost
- Reducing MAXDEPTH below current CURDEPTH: not possible without draining

### IRREVERSIBLE
The change permanently destroys data or state that cannot be recovered
without a backup restore.

Examples:
- CLEAR QLOCAL(Q): ALL messages on the queue are permanently deleted.
  There is no undo. A backup via dmpmqmsg must be taken first if any
  messages have business value.
- DELETE QLOCAL(Q): The queue definition and all its messages are deleted.
- Committing a transaction that should have been rolled back.

## Required Output Format

For each proposed action in the Change Advisory section, include:

  Reversibility: REVERSIBLE | PARTIALLY REVERSIBLE | IRREVERSIBLE
  Undo command: <the exact MQSC to reverse this change, or "None - data loss">
