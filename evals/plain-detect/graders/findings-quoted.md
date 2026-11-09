---
type: llm
weight: 2
---
PASS only if the last message reports a finding for each of these lines of `docs/NOTES.md`, and each finding gives the line number and quotes the line: line 3 (banned word `seamless`), line 5 (banned word `robust`, throat-clearing opener `Let me be clear`, superficial -ing tail `highlighting`), line 7 (semicolon, weasel attribution `Experts agree`), and line 9 (summary recap `In conclusion`). Each of these seven findings must be present. A finding may name the pattern in its own words. Extra findings on other lines are allowed. FAIL if any of the seven findings is missing, if a finding has no line number or no quoted line, or if the message shows a rewritten version of the file.
