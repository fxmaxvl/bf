#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
mkdir -p src/orders src/db src/billing
cat > src/orders/paginate.js <<'JS'
function page(items, size, n) {
  const out = [];
  for (let i = n * size; i <= (n + 1) * size; i++) out.push(items[i]);
  return out;
}
module.exports = { page };
JS
cat > src/orders/save.js <<'JS'
const db = require('../db/client');
async function saveOrder(order) {
  try {
    await db.insert('orders', order);
  } catch (e) {}
  return { ok: true };
}
module.exports = { saveOrder };
JS
cat > src/orders/notify.js <<'JS'
const { send } = require('../db/client');
let sent = 0;
async function notifyAll(users) {
  users.forEach(async (u) => { await send(u.email); sent++; });
  return sent;
}
module.exports = { notifyAll };
JS
cat > src/db/client.js <<'JS'
const pool = require('./pool');
async function findUser(name) {
  return pool.query("SELECT * FROM users WHERE name = '" + name + "'");
}
async function transfer(from, to, amount) {
  await pool.query('UPDATE accounts SET balance = balance - $1 WHERE id = $2', [amount, from]);
  await pool.query('UPDATE accounts SET balance = balance + $1 WHERE id = $2', [amount, to]);
}
async function insert(table, row) { return pool.query(`INSERT INTO ${table} VALUES ($1)`, [row]); }
async function send(email) { return pool.query('INSERT INTO outbox VALUES ($1)', [email]); }
module.exports = { findUser, transfer, insert, send };
JS
cat > src/billing/price.js <<'JS'
// Returns the price in cents.
function priceCents(item) { return Math.round(item.price * 100); }
module.exports = { priceCents };
JS
cat > src/billing/invoice.js <<'JS'
const { priceCents } = require('./price');
// total() returns dollars.
function total(items) { return items.reduce((s, it) => s + priceCents(it), 0); }
module.exports = { total };
JS
git add .
git -c user.email=eval@example.com -c user.name=eval commit -q -m init
