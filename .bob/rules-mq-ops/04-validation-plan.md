# Rule: Provide a Validation Plan for Every Change

Every proposed remediation must include a validation plan - a set of
observable checks that confirm the change achieved the desired outcome
without introducing new problems.

## Validation Plan Structure

For each proposed change, provide:

### Immediate Checks (within 1 minute of applying)
MQSC commands to run immediately to confirm the change took effect.
Always include the exact command and the expected output.

Example for ALTER QLOCAL(Q) GET(ENABLED):
  Command: DISPLAY QLOCAL(Q) GET
  Expected: GET(ENABLED)

### Short-Term Checks (within 5-10 minutes)
Observable metrics that confirm the change is having the intended effect.

Example for enabling GET:
  Command: DISPLAY QLOCAL(Q) CURDEPTH IPPROCS
  Expected: CURDEPTH decreasing, IPPROCS > 0

### Failure Indicators (signs the change made things worse)
What to watch for that would indicate the change should be rolled back.

Example for enabling GET on a deep queue:
  - CURDEPTH not decreasing after 5 minutes -> consumer may be stalled
  - IPPROCS drops back to 0 -> consumer crashed on first message
  - Error messages in application logs referencing the queue

### Rollback Trigger
The exact condition that should trigger an immediate rollback, and
the rollback command to execute.

Example:
  Trigger: CURDEPTH exceeds MAXDEPTH * 0.95 within 10 minutes of change
  Rollback: ALTER QLOCAL(Q) GET(DISABLED)

## Standard Validation Template

Use this template for every change in the MQSC Remediation Commands section:

  Validation:
    Immediate : DISPLAY QLOCAL(<Q>) <changed-attribute>
    Short-term: DISPLAY QLOCAL(<Q>) CURDEPTH IPPROCS OPPROCS MSGAGE
    Watch for : <failure indicators specific to this change>
    Rollback if: <specific trigger condition>
    Rollback cmd: <exact MQSC or "No rollback available - IRREVERSIBLE">
