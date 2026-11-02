# Multi-vendor support

bf uses the open Agent Skills format for skills that do not depend on a specific host. The
`bf-discuss` skill is the first portable skill. Install it from this repository with the
[`skills` CLI](https://github.com/vercel-labs/skills).

`/bf:write-skill` and `/bf:onboard-skill` now create portable skills by default. They use the
standard `name` and `description` frontmatter, keep bundled resources skill-relative, and flag
host-specific behavior for adaptation. A host-specific skill must be explicitly requested and
clearly labeled.

Most existing skills are Claude Code workflows. They use Claude-specific paths, tool permissions,
orchestration, hooks, and model routing. The shared skill format does not translate those runtime
features by itself. Keep those workflows explicitly host-specific until an adapter implements and
validates the equivalent behavior.

When adding support for another host:

1. Keep portable skill instructions and resources in the Agent Skills format.
2. Keep manifests and runtime-specific orchestration in that host's adapter.
3. Port only workflows whose required tools and control flow are supported, and document gaps.
4. Use a converter only to bootstrap a port. Review tool calls, permissions, model routing,
   invocation behavior, hooks, and resource paths manually.

This lets users install portable skills independently while bf adds host adapters incrementally.

## Skill catalog status

`bf-discuss` is the only one of 58 skill entries currently ported for cross-agent use. The remaining
entries are listed here to make the adapter work visible. Listing a skill does not imply compatibility.

| Area | Skills | Status |
|---|---|---|
| Discussion | `bf-discuss` | Portable and installable |
| Design | `design`, `design/gather`, `design/generate` | Needs adapter for sub-skill orchestration and Excalidraw MCP tools |
| Feature workflow | `feature`, `feature/brainstorm`, `feature/brainstorm/generate`, `feature/collect-todos`, `feature/complexity-gate`, `feature/consistency-gate`, `feature/do-todo`, `feature/plan`, `feature/quality-gate`, `feature/refine`, `feature/research`, `feature/review-design`, `feature/review-design/fix`, `feature/review-impl`, `feature/review-impl/fix`, `feature/verify` | Needs adapter for subagents, skill routing, and plugin paths |
| Other workflows | `autopilot`, `bug-fix`, `bug-hunt`, `micro`, `micro/execute`, `quick` | Needs adapter for orchestration, hooks, and approval flow |
| Review and decisions | `coherence`, `consilium`, `decide`, `discuss`, `pr-comments`, `review`, `walkthrough` | Needs adapter for agent delegation, skill routing, or host invocation |
| Project and knowledge | `gather`, `onboard-project`, `onboard-project-brief`, `session-lesson`, `teach` | Needs adapter for persistent workspaces, host tools, or subagents |
| GitHub and Jira | `gh`, `jira` | Needs adapter for issue-tracker tools and skill routing |
| Authoring and setup | `kit`, `kit/templates/skills/adopt-skill`, `kit/templates/skills/update-context`, `kit/templates/skills/write-skill`, `onboard-skill`, `scan-conventions`, `write-skill` | Needs adapter for plugin scaffolding, conventions, and host-specific metadata |
| Local document workflows | `adr-writer`, `arch-audit`, `essence`, `plain`, `poc`, `research`, `session-summary`, `self-audit`, `self-heal`, `typesafe`, `visualize` | Needs adapter for plugin paths, scripts, configuration, or external integrations |
