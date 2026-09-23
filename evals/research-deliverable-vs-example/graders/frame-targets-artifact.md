---
type: llm
weight: 2
---
Find the printed "Research Frame" block. PASS only if all of these hold:
- Its `Deliverable` line names the architecture overview of the plugin (subsystems, purposes, interactions, refactoring directions).
- Its `Question` line is about producing that overview, not "should autopilot stop depending on decide?" or any other framing of the example as the whole task.
- The autopilot/decide dependency appears, if at all, as one part of the overview (e.g. one refactoring direction), never as the research question itself.
FAIL if no Research Frame was printed, or if the Frame treats the autopilot/decide example as the thing to research.
