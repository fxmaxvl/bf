# Installing bfeature via local marketplace

If bfeature isn't yet listed on the official Anthropic marketplace, you can add it as a local marketplace source and install it directly from GitHub.

## The easy way — just ask Claude

Open Claude Code and type:

```
install the bfeature plugin from github.com/fxmaxvl/bfeature
```

Claude will handle the marketplace registration and installation for you.

## Step 1 — Add the marketplace source

```bash
/plugin marketplace add fxmaxvl/bfeature
```

This registers `github.com/fxmaxvl/bfeature` as a marketplace source in your Claude Code installation.

## Step 2 — Install the plugin

```bash
claude plugin install bfeature@fxmaxvl
```

## Step 3 — Verify

```bash
claude plugin list
```

You should see `bfeature` in the list. All skills are now available:

```
/bfeature:full
/bfeature:quick
/bfeature:design
/bfeature:gh
/bfeature:jira
/bfeature:session-summary
/bfeature:menu
```

## Updating

```bash
claude plugin update bfeature
```

## Removing

```bash
claude plugin uninstall bfeature
```
