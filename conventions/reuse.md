# Reuse-First Conventions

Before you write utility code, look for an existing solution. This file is the single source of truth for the lookup. Skills refer to its parts by name and do not repeat them.

## 1. When it applies

The code you are about to write adds a utility or generic capability: parse, format, validate, retry or backoff, string operations, dates and times, HTTP calls, collections, hashing or encoding, file and path handling, concurrency helpers. It does not apply to domain logic specific to the feature.

## 2. Level order

Check the levels in order and stop at the first hit.

- L1 repo helper: Grep or Glob the repo for an existing function, type or module that does the job.
- L2 standard library: the language's standard library.
- L3 declared dependency: read the manifest files at the repo root or in the touched package (package.json, BUILD.bazel, MODULE.bazel, pom.xml, build.gradle, build.gradle.kts, pyproject.toml, requirements.txt, go.mod, Cargo.toml). A library that is already declared adds no new dependency. Manifest reads are capped at 3 files per skill run. They do not count against any other file cap of the skill.
- L4 org shared library: the org is the owner segment of `git remote get-url origin` (git@host:org/repo or https://host/org/repo). Run `gh search code --owner=<org> "<query>"`, at most 3 queries per skill run. Skip this level silently when `gh` is missing or not logged in, when the remote has no org, or when the search fails or is denied.
- L5 well-known community library: from your own knowledge. No install and no network call.

## 3. Short form

The short form is L1 to L3 only. It has no org search and no L5 suggestion. The backstop is the review-impl phase in the feature, quick and micro flows, and `bf:review` in every other case. Bug-fix runs no review phase, so its backstop is a later `bf:review`.

## 4. Recording a hit

Tag each candidate with its level: `[L1 repo]`, `[L2 stdlib]`, `[L3 dep]`, `[L4 org]`, `[L5 community]`. Then give the name, the location or coordinates, and a one-line fit.

Example: `[L3 dep] jackson-databind: ObjectMapper parses the payload, already in pom.xml`

## 5. Suggest, never force

An L5 library is never added silently. The plan lists it as an option, with its trade-off (new dependency, size, licence, maintenance) next to writing the code by hand. The plan never writes it as a decided step. The person decides at the plan approval gate. Under autopilot the decide gate decides.

Writing by hand is valid when the need is a few lines and a new dependency costs more. Any step that writes a utility by hand gives a one-line reason.

## 6. Review check

Flag hand-written code that an L1 to L4 source already covers. Read the manifest files from section 2 first, within the manifest cap in section 2. Search L4 directly, within its query cap, for any hand-written utility that an org library may cover. Tag a concern `[org-search]` only when it asks how other repos do something. Name the helper or library that covers the code in the finding.
