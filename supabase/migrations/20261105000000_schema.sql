-- mince target schema: a rebuild of Cronometer (Basic + Gold) on Supabase.
-- Replaces the starter 0001-0005 migrations (reset approved; no production data).
-- Storage buckets: 20261105000001_storage.sql. Catalogues: 20261105000002_reference_data.sql.
--
-- Conventions
--   * every user-owned row has user_id -> auth.users on delete cascade (GDPR delete = delete the auth user)
--   * access = Postgres RLS on every table; Gold-only writes check public.is_gold()
--   * nutrient amounts live in foods.nutrients jsonb, keyed by nutrients.key, PER 100 g
--   * `day` is the user's local calendar date (client decides); instants are timestamptz (UTC)
--   * composite FKs (x_id, user_id) -> parent(id, user_id) make cross-user references impossible

create extension if not exists pg_trgm;

create or replace function public.set_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;

-- ───────────────────────────── Gold entitlement ─────────────────────────────

-- One row per App Store subscription (originalTransactionId). Written only by
-- Edge Functions with the service role (verify-purchase, appstore-notifications).
create table public.subscriptions (
  original_transaction_id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  product_id text not null,
  status text not null check (status in ('active', 'grace', 'expired', 'revoked')),
  expires_at timestamptz not null,
  environment text not null check (environment in ('Sandbox', 'Production')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.subscriptions (user_id);

-- Dedupe App Store Server Notifications (they can arrive more than once).
create table public.app_store_events (
  notification_uuid text primary key,
  received_at timestamptz not null default now()
);

create or replace function public.is_gold() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.subscriptions
    where user_id = auth.uid()
      and status in ('active', 'grace')
      and expires_at > now()
  )
$$;

-- Per-user daily counter for paid AI calls (photo, voice, import, coach).
-- Written by Edge Functions only.
create table public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  kind text not null check (kind in ('photo', 'voice', 'recipe_import', 'coach')),
  count int not null default 0,
  primary key (user_id, day, kind)
);

-- ───────────────────────────── profile + targets ─────────────────────────────

-- 1:1 with auth.users. Holds profile + energy/macro settings + prefs.
-- Current weight is NOT here: it is the latest 'weight' biometric entry.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  date_of_birth date,
  sex text check (sex in ('male', 'female')),
  height_cm numeric(5, 1) check (height_cm between 50 and 275),
  body_fat_pct numeric(4, 1) check (body_fat_pct between 2 and 70),

  -- energy
  bmr_method text not null default 'mifflin'
    check (bmr_method in ('mifflin', 'harris_benedict', 'katch_mcardle', 'custom')),
  custom_bmr_kcal int check (custom_bmr_kcal between 500 and 5000),
  activity_level text not null default 'sedentary'
    check (activity_level in ('sedentary', 'light', 'moderate', 'active', 'very_active')),
  goal_kg_per_week numeric(3, 2) not null default 0 check (goal_kg_per_week between -1 and 1),
  tef_pct numeric(3, 1) not null default 10 check (tef_pct between 0 and 25),
  use_health_active_energy boolean not null default false,

  -- macros
  macro_mode text not null default 'ratio' check (macro_mode in ('ratio', 'grams', 'keto')),
  protein_pct smallint not null default 30,
  carbs_pct smallint not null default 40,
  fat_pct smallint not null default 30,
  protein_g numeric(6, 1),
  carbs_g numeric(6, 1),
  fat_g numeric(6, 1),
  diet_preset text not null default 'none'
    check (diet_preset in ('none', 'keto', 'vegan', 'vegetarian', 'pescatarian', 'low_carb', 'high_protein', 'mediterranean')),

  -- prefs
  unit_system text not null default 'metric' check (unit_system in ('metric', 'imperial', 'uk')),
  energy_unit text not null default 'kcal' check (energy_unit in ('kcal', 'kj')),
  timezone text not null default 'UTC',
  water_target_ml int not null default 2500 check (water_target_ml > 0),
  selected_scores text[] not null default '{}' check (cardinality(selected_scores) <= 8),
  plus_menu text[] not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint macro_ratio_sums_to_100 check (
    macro_mode <> 'ratio' or protein_pct + carbs_pct + fat_pct = 100
  )
);
create trigger profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();

-- Nutrient catalogue (~90 rows, seeded from USDA FDC nutrient list). Read-only.
create table public.nutrients (
  key text primary key,                       -- 'protein', 'vitamin_c', 'magnesium', ...
  name text not null,
  unit text not null check (unit in ('kcal', 'g', 'mg', 'mcg', 'IU')),
  category text not null
    check (category in ('general', 'carbohydrates', 'lipids', 'protein', 'vitamins', 'minerals', 'other')),
  position smallint not null,
  fdc_nutrient_id int unique
);

-- Default targets (DRI: RDA/AI + UL) by sex and age band. Seeded, read-only.
create table public.nutrient_dri (
  nutrient_key text not null references public.nutrients (key) on delete cascade,
  sex text not null check (sex in ('male', 'female')),
  age_min smallint not null,
  age_max smallint not null,
  target numeric not null,     -- RDA or AI
  upper_limit numeric,         -- UL, null if none
  primary key (nutrient_key, sex, age_min),
  check (age_max >= age_min)
);

-- The user's overrides of DRI defaults (custom min/max per nutrient).
create table public.nutrient_targets (
  user_id uuid not null references auth.users (id) on delete cascade,
  nutrient_key text not null references public.nutrients (key) on delete cascade,
  min_amount numeric check (min_amount >= 0),
  max_amount numeric check (max_amount >= 0),
  enabled boolean not null default true,
  primary key (user_id, nutrient_key),
  check (min_amount is null or max_amount is null or max_amount >= min_amount)
);

-- Gold: Macro Scheduler.
create table public.macro_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  energy_kcal int check (energy_kcal between 500 and 10000),
  protein_g numeric(6, 1) check (protein_g >= 0),
  carbs_g numeric(6, 1) check (carbs_g >= 0),
  fat_g numeric(6, 1) check (fat_g >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);
create index on public.macro_templates (user_id);

create table public.macro_schedule (
  user_id uuid not null references auth.users (id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),   -- 0 = Sunday
  template_id uuid not null,
  primary key (user_id, weekday),
  foreign key (template_id, user_id) references public.macro_templates (id, user_id) on delete cascade
);
create index on public.macro_schedule (template_id);

-- ───────────────────────────── foods, recipes, meals ─────────────────────────────

-- user_id null = shared database food (USDA import). Otherwise private to the owner.
-- kind = 'recipe' rows have recipe_ingredients; their nutrients are recomputed on save.
create table public.foods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade,
  kind text not null default 'food' check (kind in ('food', 'recipe')),
  source text not null check (source in ('usda', 'off', 'custom', 'recipe', 'shared')),
  source_id text,                              -- FDC id, or barcode for OFF
  name text not null check (length(name) between 1 and 200),
  brand text,
  barcode text,
  nutrients jsonb not null default '{}' check (jsonb_typeof(nutrients) = 'object'),  -- per 100 g
  recipe_yield_g numeric(9, 2) check (recipe_yield_g > 0),                         -- final cooked weight
  instructions text,
  share_token uuid unique,                     -- Gold: share link
  archived_at timestamptz,                     -- soft delete (diary rows still reference it)
  search tsvector generated always as (
    to_tsvector('simple', coalesce(name, '') || ' ' || coalesce(brand, ''))
  ) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique nulls not distinct (user_id, source, source_id)
);
create index on public.foods (user_id);
create index on public.foods using gin (search);
create index on public.foods using gin (name gin_trgm_ops);
create index on public.foods (barcode) where barcode is not null;
create trigger foods_updated before update on public.foods
  for each row execute function public.set_updated_at();

create table public.food_servings (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references public.foods (id) on delete cascade,
  name text not null,                          -- '1 cup', '1 large', 'g'
  grams numeric(9, 3) not null check (grams > 0),
  is_default boolean not null default false,
  position smallint not null default 0
);
create index on public.food_servings (food_id);
create unique index food_servings_one_default on public.food_servings (food_id) where is_default;

create table public.recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.foods (id) on delete cascade,
  food_id uuid not null references public.foods (id) on delete restrict,
  serving_id uuid references public.food_servings (id) on delete set null,
  serving_qty numeric(9, 3),
  amount_g numeric(9, 2) not null check (amount_g > 0),
  position smallint not null default 0,
  check (recipe_id <> food_id)
);
create index on public.recipe_ingredients (recipe_id);
create index on public.recipe_ingredients (food_id);

-- Meals always explode into individual diary entries when logged.
create table public.meals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.meals (user_id);

create table public.meal_items (
  id uuid primary key default gen_random_uuid(),
  meal_id uuid not null references public.meals (id) on delete cascade,
  food_id uuid not null references public.foods (id) on delete restrict,
  serving_id uuid references public.food_servings (id) on delete set null,
  serving_qty numeric(9, 3),
  amount_g numeric(9, 2) not null check (amount_g > 0),
  position smallint not null default 0
);
create index on public.meal_items (meal_id);
create index on public.meal_items (food_id);

-- ───────────────────────────── catalogues ─────────────────────────────

-- Compendium of Physical Activities (public). kcal = met * kg * hours, computed client-side.
create table public.exercises (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  category text not null,
  met numeric(4, 1) not null check (met > 0)
);
create index on public.exercises using gin (name gin_trgm_ops);

-- user_id null = built-in (weight, waist, blood pressure, mood, sleep, stool, ...). Custom = Gold.
create table public.biometric_types (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade,
  key text not null,
  name text not null,
  unit text not null,
  category text not null
    check (category in ('body', 'vitals', 'blood', 'sleep', 'mood', 'digestion', 'lab', 'custom')),
  value_kind text not null default 'number'
    check (value_kind in ('number', 'pair', 'scale_1_7', 'scale_1_10', 'minutes')),
  unique nulls not distinct (user_id, key)
);

-- ───────────────────────────── diary ─────────────────────────────

create table public.diary_groups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (length(name) between 1 and 40),
  position smallint not null,
  unique (id, user_id)
);
create index on public.diary_groups (user_id, position);

-- Gold: Repeat Items. weekdays 0-6 (0 = Sunday); daily = all seven.
create table public.repeat_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  food_id uuid references public.foods (id) on delete cascade,
  meal_id uuid references public.meals (id) on delete cascade,
  serving_id uuid references public.food_servings (id) on delete set null,
  serving_qty numeric(9, 3),
  amount_g numeric(9, 2) check (amount_g > 0),
  group_id uuid,
  weekdays smallint[] not null check (cardinality(weekdays) between 1 and 7 and weekdays <@ '{0,1,2,3,4,5,6}'),
  starts_on date not null,
  ends_on date,
  created_at timestamptz not null default now(),
  check (num_nonnulls(food_id, meal_id) = 1),
  check (food_id is null or amount_g is not null),
  check (ends_on is null or ends_on >= starts_on),
  foreign key (group_id, user_id) references public.diary_groups (id, user_id) on delete set null (group_id)
);
create index on public.repeat_rules (user_id);
create index on public.repeat_rules (group_id);

-- Marks (rule, day) as already materialised, so deleting a repeated entry
-- for one day does not make it reappear.
create table public.repeat_runs (
  rule_id uuid not null references public.repeat_rules (id) on delete cascade,
  day date not null,
  primary key (rule_id, day)
);

-- One table for every diary row so a day is one query and copy/paste,
-- multi-select, groups and timestamps work the same for every kind.
create table public.diary_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  kind text not null check (kind in ('food', 'quick_add', 'exercise', 'biometric', 'note')),
  group_id uuid,
  logged_at timestamptz,                        -- Gold timestamps; always set for imported rows
  position int not null default 0,

  -- food
  food_id uuid references public.foods (id) on delete restrict,
  serving_id uuid references public.food_servings (id) on delete set null,
  serving_qty numeric(9, 3),
  amount_g numeric(9, 2) check (amount_g > 0),
  -- quick_add: nutrients given directly (absolute, not per 100 g)
  nutrients jsonb check (nutrients is null or jsonb_typeof(nutrients) = 'object'),
  -- exercise
  exercise_id uuid references public.exercises (id) on delete restrict,
  title text,
  minutes numeric(6, 1) check (minutes > 0),
  energy_kcal numeric(7, 1) check (energy_kcal >= 0),
  -- biometric
  biometric_type_id uuid references public.biometric_types (id) on delete cascade,
  value numeric(12, 3),
  value2 numeric(12, 3),                        -- e.g. diastolic
  -- note
  note text check (length(note) <= 5000),

  source text not null default 'manual'
    check (source in ('manual', 'health', 'repeat', 'photo', 'voice', 'import')),
  external_id text,                             -- HealthKit sample UUID, for idempotent import
  repeat_rule_id uuid references public.repeat_rules (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  foreign key (group_id, user_id) references public.diary_groups (id, user_id) on delete set null (group_id),
  constraint kind_fields check (case kind
    when 'food' then food_id is not null and amount_g is not null
    when 'quick_add' then nutrients is not null
    when 'exercise' then energy_kcal is not null and (exercise_id is not null or title is not null)
    when 'biometric' then biometric_type_id is not null and value is not null
    when 'note' then note is not null
  end)
);
create index on public.diary_entries (user_id, day);
create index on public.diary_entries (user_id, biometric_type_id, day) where kind = 'biometric';
create index on public.diary_entries (user_id, created_at desc) where kind = 'food';
create index on public.diary_entries (food_id);
create index on public.diary_entries (group_id);
create index on public.diary_entries (serving_id);
create index on public.diary_entries (exercise_id);
create index on public.diary_entries (biometric_type_id);
create index on public.diary_entries (repeat_rule_id);
create unique index diary_entries_external on public.diary_entries (user_id, source, external_id)
  where external_id is not null;
create trigger diary_entries_updated before update on public.diary_entries
  for each row execute function public.set_updated_at();

-- Per-day flags: Mark Day Complete (streaks).
create table public.days (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  completed boolean not null default false,
  primary key (user_id, day)
);

-- Gold: Fasting Timer. At most one open fast per user.
create table public.fasts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz,
  target_minutes int not null check (target_minutes between 60 and 10080),
  created_at timestamptz not null default now(),
  check (ended_at is null or ended_at > started_at)
);
create index on public.fasts (user_id, started_at desc);
create unique index fasts_one_open on public.fasts (user_id) where ended_at is null;

create table public.fast_schedules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  weekdays smallint[] not null check (cardinality(weekdays) between 1 and 7 and weekdays <@ '{0,1,2,3,4,5,6}'),
  start_time time not null,                     -- local time, user's timezone
  target_minutes int not null check (target_minutes between 60 and 10080)
);
create index on public.fast_schedules (user_id);

-- Gold: Custom Charts. series = [{"type":"nutrient"|"biometric","key":"..."}], max 2 (dual axis).
create table public.custom_charts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  series jsonb not null check (jsonb_typeof(series) = 'array' and jsonb_array_length(series) between 1 and 2),
  range_days int not null default 30 check (range_days > 0),
  pinned boolean not null default false,
  position smallint not null default 0
);
create index on public.custom_charts (user_id);

-- Progress photos. storage_path is in the private 'snapshots' bucket under <user_id>/.
create table public.snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  storage_path text not null unique,
  created_at timestamptz not null default now()
);
create index on public.snapshots (user_id, day);

-- ───────────────────────────── new-user bootstrap ─────────────────────────────

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id);
  insert into public.diary_groups (user_id, name, position) values
    (new.id, 'Breakfast', 0), (new.id, 'Lunch', 1), (new.id, 'Dinner', 2), (new.id, 'Snacks', 3);
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────────────────────────── RPCs ─────────────────────────────

-- Visible = shared database food or the caller's own.
create or replace function public.food_visible(f public.foods) returns boolean
language sql stable as $$ select f.user_id is null or f.user_id = auth.uid() $$;

-- Food search: own foods first, then full-text rank, then trigram similarity (typos).
create or replace function public.search_foods(q text, lim int default 30, off int default 0)
returns setof public.foods language sql stable as $$
  select f.* from public.foods f
  where f.archived_at is null
    and (f.user_id is null or f.user_id = auth.uid())
    and (f.search @@ websearch_to_tsquery('simple', q) or f.name % q)
  order by (f.user_id is not null) desc,
           ts_rank(f.search, websearch_to_tsquery('simple', q)) desc,
           similarity(f.name, q) desc
  limit least(lim, 100) offset off
$$;

-- Most recently logged distinct foods.
create or replace function public.recent_foods(lim int default 30)
returns setof public.foods language sql stable as $$
  select f.* from public.foods f
  join (
    select food_id, max(created_at) as last_at from public.diary_entries
    where user_id = auth.uid() and kind = 'food'
    group by food_id order by last_at desc limit least(lim, 100)
  ) r on r.food_id = f.id
  where f.archived_at is null
  order by r.last_at desc
$$;

-- Per-day per-nutrient intake. Basic users are limited to 7-day ranges (Gold: unlimited).
-- One aggregation path for diary, reports, charts and scores.
create or replace function public.nutrient_totals(p_from date, p_to date)
returns table (day date, nutrient_key text, amount double precision)
language plpgsql stable as $$
begin
  if p_to < p_from then raise exception 'p_to before p_from'; end if;
  if p_to - p_from >= 7 and not public.is_gold() then
    raise exception 'gold_required' using errcode = 'P0001';
  end if;
  return query
    select x.day, x.key, sum(x.amt)::float8 from (
      select e.day, n.key, n.value::numeric * e.amount_g / 100 as amt
      from public.diary_entries e
      join public.foods f on f.id = e.food_id
      cross join lateral jsonb_each_text(f.nutrients) n(key, value)
      where e.user_id = auth.uid() and e.kind = 'food' and e.day between p_from and p_to
      union all
      select e.day, n.key, n.value::numeric
      from public.diary_entries e
      cross join lateral jsonb_each_text(e.nutrients) n(key, value)
      where e.user_id = auth.uid() and e.kind = 'quick_add' and e.day between p_from and p_to
    ) x group by x.day, x.key;
end $$;

-- Which logged foods contributed most of a nutrient over a range (report drill-down).
create or replace function public.nutrient_sources(p_from date, p_to date, p_key text, lim int default 10)
returns table (food_id uuid, name text, amount double precision)
language plpgsql stable as $$
begin
  if p_to - p_from >= 7 and not public.is_gold() then
    raise exception 'gold_required' using errcode = 'P0001';
  end if;
  return query
    select f.id, f.name, sum((f.nutrients ->> p_key)::numeric * e.amount_g / 100)::float8 as amt
    from public.diary_entries e join public.foods f on f.id = e.food_id
    where e.user_id = auth.uid() and e.kind = 'food'
      and e.day between p_from and p_to and f.nutrients ? p_key
    group by f.id, f.name order by amt desc limit least(lim, 50);
end $$;

-- Gold: Oracle. Foods richest in a nutrient per 100 kcal (or per 100 g).
-- ponytail: sequential scan over foods; add an expression index per hot nutrient if slow.
create or replace function public.oracle(p_key text, per text default 'kcal', lim int default 50)
returns setof public.foods language plpgsql stable as $$
begin
  if not public.is_gold() then raise exception 'gold_required' using errcode = 'P0001'; end if;
  return query
    select f.* from public.foods f
    where f.archived_at is null and (f.user_id is null or f.user_id = auth.uid())
      and f.nutrients ? p_key
      and (per <> 'kcal' or coalesce((f.nutrients ->> 'energy')::numeric, 0) > 0)
    order by case when per = 'kcal'
                  then (f.nutrients ->> p_key)::numeric / (f.nutrients ->> 'energy')::numeric
                  else (f.nutrients ->> p_key)::numeric end desc
    limit least(lim, 100);
end $$;

-- Recompute a recipe's per-100 g nutrients from its ingredients. Called after saving a recipe.
-- ponytail: recipes don't auto-update when an ingredient food is edited later; call again on open if needed.
create or replace function public.recompute_recipe(p_recipe uuid) returns void
language plpgsql as $$
declare total_g numeric;
begin
  select coalesce(r.recipe_yield_g, sum(i.amount_g)) into total_g
  from public.foods r left join public.recipe_ingredients i on i.recipe_id = r.id
  where r.id = p_recipe and r.user_id = auth.uid() and r.kind = 'recipe'
  group by r.recipe_yield_g;
  if total_g is null then raise exception 'recipe not found'; end if;

  update public.foods set nutrients = coalesce((
    select jsonb_object_agg(k, round(v * 100 / total_g, 4)) from (
      select n.key as k, sum(n.value::numeric * i.amount_g / 100) as v
      from public.recipe_ingredients i
      join public.foods f on f.id = i.food_id
      cross join lateral jsonb_each_text(f.nutrients) n(key, value)
      where i.recipe_id = p_recipe
      group by n.key
    ) s
  ), '{}')
  where id = p_recipe;
end $$;

-- Gold: materialise repeat rules into a day. Idempotent; a deleted repeated
-- entry stays deleted because repeat_runs remembers the (rule, day).
create or replace function public.materialize_repeats(p_day date) returns int
language plpgsql as $$
declare r record; n int := 0;
begin
  if not public.is_gold() then return 0; end if;
  for r in
    select rr.* from public.repeat_rules rr
    where rr.user_id = auth.uid()
      and p_day >= rr.starts_on and (rr.ends_on is null or p_day <= rr.ends_on)
      and extract(dow from p_day)::smallint = any (rr.weekdays)
  loop
    insert into public.repeat_runs (rule_id, day) values (r.id, p_day) on conflict do nothing;
    if not found then continue; end if;
    if r.food_id is not null then
      insert into public.diary_entries (user_id, day, kind, group_id, food_id, serving_id, serving_qty, amount_g, source, repeat_rule_id)
      values (r.user_id, p_day, 'food', r.group_id, r.food_id, r.serving_id, r.serving_qty, r.amount_g, 'repeat', r.id);
      n := n + 1;
    else
      insert into public.diary_entries (user_id, day, kind, group_id, food_id, serving_id, serving_qty, amount_g, source, repeat_rule_id, position)
      select r.user_id, p_day, 'food', r.group_id, mi.food_id, mi.serving_id, mi.serving_qty, mi.amount_g, 'repeat', r.id, mi.position
      from public.meal_items mi where mi.meal_id = r.meal_id;
      get diagnostics n = row_count;
    end if;
  end loop;
  return n;
end $$;

-- Gold: read a shared food/recipe by its token (bypasses RLS for that one row).
-- Importing = the client inserts a copy with source = 'shared'.
create or replace function public.get_shared_food(p_token uuid)
returns table (food jsonb, servings jsonb)
language sql stable security definer set search_path = public as $$
  select to_jsonb(f) - 'user_id' - 'share_token',
         coalesce((select jsonb_agg(to_jsonb(s) - 'food_id') from public.food_servings s where s.food_id = f.id), '[]')
  from public.foods f
  where f.share_token = p_token and f.archived_at is null
$$;

-- ───────────────────────────── row level security ─────────────────────────────

alter table public.subscriptions      enable row level security;
alter table public.app_store_events   enable row level security;
alter table public.ai_usage           enable row level security;
alter table public.profiles           enable row level security;
alter table public.nutrients          enable row level security;
alter table public.nutrient_dri       enable row level security;
alter table public.nutrient_targets   enable row level security;
alter table public.macro_templates    enable row level security;
alter table public.macro_schedule     enable row level security;
alter table public.foods              enable row level security;
alter table public.food_servings      enable row level security;
alter table public.recipe_ingredients enable row level security;
alter table public.meals              enable row level security;
alter table public.meal_items         enable row level security;
alter table public.exercises          enable row level security;
alter table public.biometric_types    enable row level security;
alter table public.diary_groups       enable row level security;
alter table public.repeat_rules       enable row level security;
alter table public.repeat_runs        enable row level security;
alter table public.diary_entries      enable row level security;
alter table public.days               enable row level security;
alter table public.fasts              enable row level security;
alter table public.fast_schedules     enable row level security;
alter table public.custom_charts      enable row level security;
alter table public.snapshots          enable row level security;

-- service-role only (no policies): app_store_events. Read-own only: subscriptions, ai_usage.
create policy own_read on public.subscriptions for select using (user_id = auth.uid());
create policy own_read on public.ai_usage for select using (user_id = auth.uid());

-- catalogues: read-only for signed-in users
create policy read_all on public.nutrients       for select to authenticated using (true);
create policy read_all on public.nutrient_dri    for select to authenticated using (true);
create policy read_all on public.exercises       for select to authenticated using (true);

-- profile: no delete (cascade from auth.users only)
create policy own_read   on public.profiles for select using (id = auth.uid());
create policy own_update on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- simple owner-only tables
create policy own_all on public.nutrient_targets for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_all on public.meals            for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_all on public.diary_groups     for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_all on public.days             for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_all on public.snapshots        for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Gold tables: read/delete own always (so data survives a lapse), write needs Gold
create policy own_read   on public.macro_templates for select using (user_id = auth.uid());
create policy own_delete on public.macro_templates for delete using (user_id = auth.uid());
create policy gold_write on public.macro_templates for insert with check (user_id = auth.uid() and public.is_gold());
create policy gold_edit  on public.macro_templates for update using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_gold());

create policy own_read   on public.macro_schedule for select using (user_id = auth.uid());
create policy own_delete on public.macro_schedule for delete using (user_id = auth.uid());
create policy gold_write on public.macro_schedule for insert with check (user_id = auth.uid() and public.is_gold());
create policy gold_edit  on public.macro_schedule for update using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_gold());

create policy own_read   on public.repeat_rules for select using (user_id = auth.uid());
create policy own_delete on public.repeat_rules for delete using (user_id = auth.uid());
create policy gold_write on public.repeat_rules for insert with check (user_id = auth.uid() and public.is_gold());
create policy gold_edit  on public.repeat_rules for update using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_gold());

create policy own_all on public.repeat_runs for all
  using (exists (select 1 from public.repeat_rules r where r.id = rule_id and r.user_id = auth.uid()))
  with check (exists (select 1 from public.repeat_rules r where r.id = rule_id and r.user_id = auth.uid()));

create policy own_read   on public.fasts for select using (user_id = auth.uid());
create policy own_delete on public.fasts for delete using (user_id = auth.uid());
create policy gold_write on public.fasts for insert with check (user_id = auth.uid() and public.is_gold());
create policy gold_edit  on public.fasts for update using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_gold());

create policy own_read   on public.fast_schedules for select using (user_id = auth.uid());
create policy own_delete on public.fast_schedules for delete using (user_id = auth.uid());
create policy gold_write on public.fast_schedules for insert with check (user_id = auth.uid() and public.is_gold());
create policy gold_edit  on public.fast_schedules for update using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_gold());

create policy own_read   on public.custom_charts for select using (user_id = auth.uid());
create policy own_delete on public.custom_charts for delete using (user_id = auth.uid());
create policy gold_write on public.custom_charts for insert with check (user_id = auth.uid() and public.is_gold());
create policy gold_edit  on public.custom_charts for update using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_gold());

-- biometric types: built-ins readable by all; custom ones are Gold to create
create policy read_visible on public.biometric_types for select using (user_id is null or user_id = auth.uid());
create policy own_delete   on public.biometric_types for delete using (user_id = auth.uid());
create policy gold_write   on public.biometric_types for insert with check (user_id = auth.uid() and public.is_gold());
create policy gold_edit    on public.biometric_types for update using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_gold());

-- foods: shared database read-only; own foods full access; sharing a food needs Gold
create policy read_visible on public.foods for select using (user_id is null or user_id = auth.uid());
create policy own_insert   on public.foods for insert with check (user_id = auth.uid() and (share_token is null or public.is_gold()));
create policy own_update   on public.foods for update using (user_id = auth.uid())
  with check (user_id = auth.uid() and (share_token is null or public.is_gold()));
create policy own_delete   on public.foods for delete using (user_id = auth.uid());

create policy read_visible on public.food_servings for select
  using (exists (select 1 from public.foods f where f.id = food_id and (f.user_id is null or f.user_id = auth.uid())));
create policy own_write on public.food_servings for all
  using (exists (select 1 from public.foods f where f.id = food_id and f.user_id = auth.uid()))
  with check (exists (select 1 from public.foods f where f.id = food_id and f.user_id = auth.uid()));

-- children of recipes/meals: parent must be mine, referenced food must be visible to me
create policy own_all on public.recipe_ingredients for all
  using (exists (select 1 from public.foods r where r.id = recipe_id and r.user_id = auth.uid()))
  with check (
    exists (select 1 from public.foods r where r.id = recipe_id and r.user_id = auth.uid() and r.kind = 'recipe')
    and exists (select 1 from public.foods f where f.id = food_id and (f.user_id is null or f.user_id = auth.uid()))
  );

create policy own_all on public.meal_items for all
  using (exists (select 1 from public.meals m where m.id = meal_id and m.user_id = auth.uid()))
  with check (
    exists (select 1 from public.meals m where m.id = meal_id and m.user_id = auth.uid())
    and exists (select 1 from public.foods f where f.id = food_id and (f.user_id is null or f.user_id = auth.uid()))
  );

-- diary: own rows; referenced food / biometric type must be visible; timestamps are Gold
-- (imported Health rows always carry logged_at, so they are exempt)
create policy own_read   on public.diary_entries for select using (user_id = auth.uid());
create policy own_delete on public.diary_entries for delete using (user_id = auth.uid());
create policy own_insert on public.diary_entries for insert with check (
  user_id = auth.uid()
  and (food_id is null or exists (select 1 from public.foods f where f.id = food_id and (f.user_id is null or f.user_id = auth.uid())))
  and (biometric_type_id is null or exists (select 1 from public.biometric_types b where b.id = biometric_type_id and (b.user_id is null or b.user_id = auth.uid())))
  and (logged_at is null or source = 'health' or public.is_gold())
);
create policy own_update on public.diary_entries for update using (user_id = auth.uid()) with check (
  user_id = auth.uid()
  and (food_id is null or exists (select 1 from public.foods f where f.id = food_id and (f.user_id is null or f.user_id = auth.uid())))
  and (biometric_type_id is null or exists (select 1 from public.biometric_types b where b.id = biometric_type_id and (b.user_id is null or b.user_id = auth.uid())))
  and (logged_at is null or source = 'health' or public.is_gold())
);
