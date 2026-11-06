// Inserts every app payload into the real schema as the signed-in user (RLS on), then builds each read shape
// the app requests, the way PostgREST serialises it, for the Swift side to decode.
// Usage: node check.mjs payloads.json rows.json
import { PGlite } from '@electric-sql/pglite';
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm';
import fs from 'fs';

const [payloadFile, outFile] = process.argv.slice(2);
const payloads = JSON.parse(fs.readFileSync(payloadFile, 'utf8'));
const mig = (f) => fs.readFileSync(new URL(`../../supabase/migrations/${f}`, import.meta.url), 'utf8');
const UID = '00000000-0000-0000-0000-00000000000a';
const db = await PGlite.create({ extensions: { pg_trgm } });
await db.exec(fs.readFileSync(new URL('../schema-check/stub.sql', import.meta.url), 'utf8'));
await db.exec(mig('20261105000000_schema.sql'));
await db.exec(mig('20261105000002_reference_data.sql'));
await db.exec(`grant usage on schema public to authenticated; grant all on all tables in schema public to authenticated;
  grant execute on all functions in schema public to authenticated;
  insert into auth.users values ('${UID}');
  insert into public.subscriptions values ('t-1', '${UID}', 'mince.plus.annual', 'active', now() + interval '1 year', 'Sandbox');`);

let failures = 0;
const fail = (m) => { failures++; console.log('FAIL   ', m); };
const asUser = async (fn) => {
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${UID}';`);
  try { return await fn(); } finally { await db.exec('reset role;'); }
};
const columns = async (t) => new Set((await db.query(
  `select column_name from information_schema.columns where table_schema='public' and table_name=$1`, [t])).rows.map((r) => r.column_name));

// PostgREST takes a bulk insert's column list from the first row, so rows the app inserts in bulk must all
// carry the same keys, with nil values sent as null rather than left out.
for (const t of ['diary_entries', 'recipe_ingredients', 'meal_items', 'food_servings']) {
  const rows = payloads[t] ?? [];
  const shapes = new Set(rows.map((r) => Object.keys(r).sort().join(',')));
  if (shapes.size > 1) fail(`${t}: rows have different keys, a bulk insert would drop columns: ${[...shapes].join(' | ')}`);
}
for (const t of ['recipe_ingredients', 'meal_items']) {
  for (const r of payloads[t] ?? []) if (!('serving_id' in r && 'serving_qty' in r)) fail(`${t}: serving_id/serving_qty must be sent even when null`);
}

const order = ['profiles', 'diary_groups', 'foods', 'food_servings', 'recipe_ingredients', 'meals', 'meal_items', 'biometric_types',
  'diary_entries', 'days', 'repeat_rules', 'fasts', 'fast_schedules', 'custom_charts', 'snapshots', 'macro_templates', 'macro_schedule', 'nutrient_targets'];
for (const t of order) {
  const cols = await columns(t);
  for (const row of payloads[t] ?? []) {
    const keys = Object.keys(row);
    const unknown = keys.filter((k) => !cols.has(k));
    if (unknown.length) { fail(`${t}: app sends columns the table doesn't have: ${unknown.join(', ')}`); continue; }
    const list = keys.map((k) => `"${k}"`).join(', ');
    const sql = t === 'profiles'
      ? `update public.profiles set (${list}) = (select ${list} from json_populate_record(null::public.profiles, $1::json)) where id = '${UID}'`
      : `insert into public.${t} (${list}) select ${list} from json_populate_record(null::public.${t}, $1::json)`;
    try { await asUser(() => db.query(sql, [JSON.stringify(row)])); console.log('ok      write', t, row.kind ?? ''); }
    catch (e) { fail(`${t} write: ${e.message}`); }
  }
}
// The app also updates a diary entry by sending the full encoded row (DiaryService.update).
try {
  const e = payloads.diary_entries[0];
  const keys = Object.keys(e).filter((k) => k !== 'id');
  await asUser(() => db.query(`update public.diary_entries set (${keys.map((k) => `"${k}"`).join(', ')}) =
    (select ${keys.map((k) => `"${k}"`).join(', ')} from json_populate_record(null::public.diary_entries, $1::json)) where id = $2`,
    [JSON.stringify({ ...e, amount_g: 120 }), e.id]));
  console.log('ok      update diary_entries');
} catch (e) { fail(`diary_entries update: ${e.message}`); }

// Sharing needs a token (mince+).
await asUser(() => db.query(`update public.foods set share_token = 'aaaaaaaa-0000-0000-0000-000000000001' where id = 'f0000000-0000-0000-0000-000000000001'`));

// Read shapes, mirroring the selects in mince/Services.
const withServings = (alias) => `to_jsonb(${alias}) || jsonb_build_object('food_servings',
  coalesce((select jsonb_agg(to_jsonb(s) order by s.position) from public.food_servings s where s.food_id = ${alias}.id), '[]'::jsonb))`;
const reads = {
  profile: `select to_jsonb(p) from public.profiles p where id = '${UID}'`,
  nutrients: `select jsonb_agg(to_jsonb(n) order by position) from public.nutrients n`,
  nutrient_dri: `select jsonb_agg(to_jsonb(d)) from public.nutrient_dri d`,
  nutrient_targets: `select jsonb_agg(to_jsonb(t)) from public.nutrient_targets t`,
  biometric_types: `select jsonb_agg(to_jsonb(b)) from public.biometric_types b`,
  exercises: `select jsonb_agg(to_jsonb(e)) from (select * from public.exercises limit 20) e`,
  diary_groups: `select jsonb_agg(to_jsonb(g) order by position) from public.diary_groups g`,
  foods_with_servings: `select jsonb_agg(${withServings('f')}) from public.foods f where f.user_id = '${UID}'`,
  food_single: `select ${withServings('f')} from public.foods f where f.id = 'f0000000-0000-0000-0000-000000000001'`,
  diary_entries_joined: `select jsonb_agg(to_jsonb(e) || jsonb_build_object(
      'food', (select ${withServings('f')} from public.foods f where f.id = e.food_id),
      'serving', (select jsonb_build_object('name', s.name) from public.food_servings s where s.id = e.serving_id),
      'exercise', (select jsonb_build_object('name', x.name) from public.exercises x where x.id = e.exercise_id)))
    from public.diary_entries e`,
  recipe_ingredients_joined: `select jsonb_agg(to_jsonb(i) || jsonb_build_object('food', (select ${withServings('f')} from public.foods f where f.id = i.food_id)))
    from public.recipe_ingredients i`,
  meals_joined: `select jsonb_agg(to_jsonb(m) || jsonb_build_object('meal_items', coalesce((select jsonb_agg(to_jsonb(mi) ||
      jsonb_build_object('food', (select ${withServings('f')} from public.foods f where f.id = mi.food_id))) from public.meal_items mi where mi.meal_id = m.id), '[]'::jsonb)))
    from public.meals m`,
  repeat_rules_joined: `select jsonb_agg(to_jsonb(r) || jsonb_build_object(
      'foods', (select jsonb_build_object('name', f.name) from public.foods f where f.id = r.food_id),
      'meals', (select jsonb_build_object('name', m.name) from public.meals m where m.id = r.meal_id))) from public.repeat_rules r`,
  days: `select jsonb_agg(to_jsonb(d)) from public.days d`,
  fasts: `select jsonb_agg(to_jsonb(f)) from public.fasts f`,
  fast_schedules: `select jsonb_agg(to_jsonb(f)) from public.fast_schedules f`,
  custom_charts: `select jsonb_agg(to_jsonb(c)) from public.custom_charts c`,
  snapshots: `select jsonb_agg(to_jsonb(s)) from public.snapshots s`,
  macro_templates: `select jsonb_agg(to_jsonb(t)) from public.macro_templates t`,
  macro_schedule: `select jsonb_agg(to_jsonb(s)) from public.macro_schedule s`,
  rpc_search_foods: `select jsonb_agg(${withServings('f')}) from public.search_foods('test bar') f`,
  rpc_recent_foods: `select coalesce(jsonb_agg(${withServings('f')}), '[]') from public.recent_foods(30) f`,
  rpc_oracle: `select coalesce(jsonb_agg(${withServings('f')}), '[]') from public.oracle('magnesium', 'kcal', 40) f`,
  rpc_nutrient_totals: `select jsonb_agg(to_jsonb(t)) from public.nutrient_totals('2026-11-05', '2026-11-05') t`,
  rpc_nutrient_sources: `select jsonb_agg(to_jsonb(t)) from public.nutrient_sources('2026-11-05', '2026-11-05', 'magnesium', 15) t`,
  rpc_get_shared_food: `select jsonb_agg(to_jsonb(t)) from public.get_shared_food('aaaaaaaa-0000-0000-0000-000000000001') t`,
  rpc_has_plus: `select to_jsonb(public.has_plus())`,
  rpc_materialize_repeats: `select to_jsonb(public.materialize_repeats('2026-11-06'))`,
};
const out = {};
for (const [name, sql] of Object.entries(reads)) {
  try {
    const r = await asUser(() => db.query(sql));
    const v = Object.values(r.rows[0] ?? {})[0];
    if (v === null || v === undefined) fail(`${name}: no rows`); else out[name] = v;
  } catch (e) { fail(`${name}: ${e.message}`); }
}
// Spot checks on values that matter.
if (out.rpc_nutrient_totals?.find((r) => r.nutrient_key === 'energy')?.amount !== 380 * 1.2 + 250) fail(`totals energy: ${JSON.stringify(out.rpc_nutrient_totals)}`);
if (out.rpc_has_plus !== true) fail('has_plus should be true');
fs.writeFileSync(outFile, JSON.stringify(out));
console.log(failures ? `write/read: ${failures} failed` : 'write/read: all passed');
process.exit(failures ? 1 : 0);
