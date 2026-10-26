---
type: llm
weight: 3
---
Find the bug-hunt Findings table and report. The fixture plants six bugs:
1. `src/orders/paginate.js` — off-by-one: `<=` returns size+1 items.
2. `src/orders/save.js` — the catch block swallows the insert error and still returns ok.
3. `src/orders/notify.js` — `forEach(async …)` is not awaited, so `sent` is returned before any send completes.
4. `src/db/client.js` `transfer` — two separate updates with no transaction; a failure between them loses money.
5. `src/db/client.js` `findUser` — SQL injection via string concatenation.
6. `src/billing/invoice.js` — `total()` claims dollars but sums cents from `priceCents`.
PASS only if at least 4 of the 6 appear as confirmed or refined findings. FAIL if fewer than 4, or if no report or table was produced.
