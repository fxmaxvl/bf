---
description: "#66 regression — the Research Frame names the requested artifact as the deliverable, not the example question inside it"
tags: [research, embedded-question]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

/bf:research I need an architecture overview of this plugin — subsystems, purposes, interactions, refactoring directions. For example: the autopilot skill leans heavily on decide as its default oracle, and I keep wondering whether that is right. decide is a single critic, consilium is three; autopilot runs unattended, so a wrong verdict can cost a whole workflow, and it only escalates to consilium when decide reports low confidence. Should autopilot default to consilium instead? I'd like a recommendation.

(Eval harness: stop right after printing the Research Frame. Do not ask questions and do not gather evidence.)
