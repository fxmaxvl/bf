---
type: llm
---
Line 11 of `docs/NOTES.md` ("The detail that makes it work: every build changes little.") is a colon reveal, which the lint does not report. PASS only if the last message reports line 11 as a colon reveal, or as a fake reveal through a colon, and quotes the line. FAIL if line 11 is not reported, or if the message shows a rewritten version of the file.
