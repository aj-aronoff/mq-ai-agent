# Rule: Evaluate the Diagnosis Before Recommending Action

Before proposing any remediation, you must evaluate the diagnosis returned by
the MQ AI Agent against the live queue attributes. Do not accept the diagnosis
at face value - verify it internally.

## Evaluation Steps

1. **Cross-check attributes** - Confirm the issue is supported by multiple
   queue attributes, not a single value. For example, a high CURDEPTH alone
   is not an incident if IPPROCS > 0 and messages are flowing.

2. **Identify the root cause category** - Classify the issue as one of:
   - APPLICATION: producer or consumer application problem
   - CONFIGURATION: queue attribute misconfigured (e.g. GET=DISABLED)
   - TRANSACTION: uncommitted messages blocking consumers (UNCOM > 0)
   - CAPACITY: queue depth approaching or exceeding MAXDEPTH
   - MONITORING: alerting or metrics disabled (QDPHIEV, MONQ)

3. **Check for compounding factors** - Note if multiple categories apply.
   A queue can have both a transaction issue AND monitoring disabled - both
   must be addressed or the incident will recur.

4. **State your confidence** - After evaluation, explicitly state:
   - HIGH confidence: multiple attributes corroborate the diagnosis
   - MEDIUM confidence: diagnosis is plausible but one key attribute is missing
   - LOW confidence: diagnosis is inferred; recommend further investigation first

5. **Flag if safe to proceed** - If confidence is LOW, recommend running
   additional MQSC commands (e.g. DISPLAY CONN, DISPLAY QSTATUS) before
   applying any remediation.
