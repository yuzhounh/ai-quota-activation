The README now has a complete clone/check/dry-run quick start, preserves the existing centered logo header, and distinguishes script defaults from account-specific quota behavior. It also corrects the initial weekly trigger description and explains that an explicitly empty provider group disables its task.

Fixes found during the review:

- Persist CLI paths as absolute paths so scheduled tasks can find them from their deployed working directory.
- Parse reset-related timestamps instead of accidentally using an earlier log timestamp.
- Accept whitespace and trailing separators in provider lists, and align script version output with VERSION (0.4).
- Make installer tests independent of real CLI installations by supplying fixtures.

Validation: all three offline PowerShell suites passed (`test-v0.2.ps1`, `test-installer-v0.2.ps1`, and `test-reset-time.ps1`); both version commands report 0.4; `git diff --check` passed. Tests do not call live AI services, register real scheduled tasks, or put the computer to sleep. Live provider behavior has not been exercised.
