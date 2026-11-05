// Applies every SQL file but the last in order, then runs the last as a statement-by-statement smoke test.
// Usage: node run.mjs stub.sql <migration.sql>... test.sql
import { PGlite } from '@electric-sql/pglite';
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm';
import fs from 'fs';
const files = process.argv.slice(2);
const test = fs.readFileSync(files.pop(), 'utf8');
const db = await PGlite.create({ extensions: { pg_trgm } });
for (const f of files) { await db.exec(fs.readFileSync(f, 'utf8')); console.log('applied', f.split('/').pop()); }
for (const s of test.split(/;\s*(?:--[^\n]*)?\n/).map(s => s.trim()).filter(Boolean)) {
  const r = (await db.exec(s + ';')).at(-1);
  if (r?.rows?.length) console.log(s.slice(0, 60).replace(/\s+/g, ' '), '=>', JSON.stringify(r.rows));
}
