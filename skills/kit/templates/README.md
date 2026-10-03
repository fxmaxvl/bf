# {{KIT_NAME}}

{{KIT_DESCRIPTION}}

A standalone Claude Code plugin. Shared context lives in `context/main.md`, reference material in `knowledge/`, and skills in `skills/`.

## Install

Load it for one session:

```shell
claude --plugin-dir {{KIT_SOURCE_DIR}}
```

Or install it permanently from this directory, which doubles as a local marketplace:

```shell
/plugin marketplace add {{KIT_SOURCE_DIR}}
/plugin install {{KIT_NAME}}@{{KIT_NAME}}-local
```

## Picking up changes

Both install modes load the kit from this directory in place. After you edit a skill or the context, run `/reload-plugins`, or start a new session.

## Skills

| Skill | Kind | What it does |
|---|---|---|
| `/{{KIT_NAME}}:write-skill [idea]` | Utility | Author a new skill for this kit, or pick one up from `BACKLOG.md` |
| `/{{KIT_NAME}}:adopt-skill <url \| path>` | Utility | Adapt an existing skill from elsewhere into this kit |
| `/{{KIT_NAME}}:update-context [change \| file \| url]` | Utility | Revise the main context, or add material to `knowledge/` |
