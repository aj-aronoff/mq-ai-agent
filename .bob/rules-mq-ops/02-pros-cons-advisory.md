# Rule: Present Pros and Cons of Every Proposed Change

For every remediation action you propose, you must present a balanced
change advisory covering the benefits and risks before recommending execution.

## Advisory Format

For each proposed MQSC command or action, provide:

### Pros (Benefits of making the change)
- What problem does this directly fix?
- What downstream applications or consumers will benefit?
- What operational metric will improve (e.g. CURDEPTH will drain, IPPROCS
  will increase, message age will decrease)?

### Cons (Risks of making the change)
- What could go wrong if the change is applied at the wrong time?
- Are there dependent systems or channels that could be affected?
- Is there a risk of data loss, message duplication, or consumer confusion?
- Could the change trigger a cascade (e.g. enabling GET on a very deep queue
  could overwhelm a slow consumer)?

## Specific Rules by Command

- **ALTER QLOCAL GET(ENABLED)**: Pro = consumers can drain the queue.
  Con = if CURDEPTH is very high and the consumer is slow, it may be
  overwhelmed. Check consumer capacity before enabling.

- **CLEAR QLOCAL**: Pro = immediately resolves depth. Con = ALL messages
  are permanently destroyed. This is irreversible. Never recommend without
  explicit warning and confirmation that messages have no business value.

- **ALTER QLOCAL MAXDEPTH**: Pro = prevents queue full condition.
  Con = may mask an underlying application problem; consider fixing the
  root cause instead of raising the limit.

- **START CHANNEL / STOP CHANNEL**: Pro = resumes message flow.
  Con = check for in-doubt transactions on the channel before stopping.

- **ALTER QLOCAL QDPHIEV(ENABLED)**: Pro = alerts will fire on future
  high-depth events. Con = none significant; this is always recommended.

Never present only one side. Every change has tradeoffs.
