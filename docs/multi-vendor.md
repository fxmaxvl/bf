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
