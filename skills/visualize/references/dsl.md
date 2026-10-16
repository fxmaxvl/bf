# LikeC4 DSL subset for bf:visualize

Pinned to the likec4 version defined by `LIKEC4_VERSION` in `scripts/install-likec4.sh`. This covers only what the skill emits. For more, `npx skills add https://likec4.dev/` installs LikeC4's own `likec4-dsl` agent skill; nothing here depends on it.

You write `model` and `views` blocks only. **Never write a `specification` block**: the element kinds come from the base spec plus an optional domain override, and `build.sh` rejects a model that contains one.

## Kinds

Base kinds: `person`, `system`, `container`, `component`, `database`, `queue`, `external`. A domain override (`visualize-spec.c4`) may add more; use those where they apply and the base kinds otherwise.

Example override: `references/wix-spec.example.c4` — copy it to `<project>/.bf/conventions/visualize-spec.c4` or `~/.bf/conventions/visualize-spec.c4`.

## Elements and nesting

```
model {
  user = person 'User'
  shop = system 'Shop' {
    web = container 'Web' {
      cart = component 'Cart'
    }
    db = database 'DB'
  }
}
```

- `<id> = <kind> '<title>'`, with children in `{ }`. Ids are lowercase and unique among siblings; refer to a child as `shop.web.cart`.
- Add `description '…'` inside the body. Start it with where the doc says so: `description 'from: Proposed design. Handles checkout.'`.

## Relationships

```
user -> shop.web 'browses'
shop.web -> shop.db 'reads and writes'
```

Only the plain `->` with a label. Draw relationships between the elements the doc connects, at the level it states them.

## Gaps: the `#tbd` tag

When the doc names something but leaves its kind, parent or connections unclear, declare it anyway and tag it. Put the open question in the description:

```
events = queue 'Events' {
  #tbd
  description 'from: Proposed design. Open question: which service consumes these events?'
}
```

Never fill a gap with a guess.

## Views

```
views {
  view index {
    include *
  }
  view shop of shop {
    include *
  }
}
```

- One `index` view, plus one `view <id> of <element>` for every element that has children, so drill-down works.
- `include *` shows the scope's direct children and their relationships. `include shop.web` adds one element; `exclude shop.db` removes one.
- Over about 20 elements in one view: split it into focused views, for example one per subsystem.

## Dynamic views (request flows)

```
dynamic view checkout {
  user -> shop.web 'opens'
  shop.web -> shop.api 'POST /orders'
  shop.api -> shop.db 'insert'
}
```

One step per `->`, in order, for a flow the doc describes step by step.

## Known warnings

LikeC4 prints layout warnings as bare lines and still exits 0. `build.sh` treats every one as a failure, so fix them.

- **`Sequence view does not support nested actors`**: a dynamic view mixes an element with one of its own descendants. Keep every step in a dynamic view at one nesting level.

  Wrong (`shop.web` and its child `shop.web.cart` both appear):

  ```
  dynamic view checkout {
    user -> shop.web 'opens'
    shop.web.cart -> shop.api.orders 'POST /orders'
  }
  ```

  Right (containers only):

  ```
  dynamic view checkout {
    user -> shop.web 'opens'
    shop.web -> shop.api 'POST /orders'
  }
  ```
