-- foods: shared food database. Nutrients are plain columns (not an EAV
-- table) because the tracked nutrient set is fixed and small — a join table
-- would only pay off if nutrients were user-defined or numbered in the
-- hundreds. All nutrient values are PER 100g/100ml; serving_size_g +
-- serving_name are just a convenience default for quick-add UI.
--
-- created_by is null for seed/"official" foods, set for user-added customs.

create table public.foods (
  id uuid primary key default gen_random_uuid(),
  created_by uuid references auth.users (id) on delete set null,
  name text not null,
  brand text,
  serving_size_g numeric(7, 2) not null default 100,
  serving_name text not null default 'g',

  -- macros (per 100g)
  calories_kcal numeric(7, 2) not null,
  protein_g numeric(6, 2) not null default 0,
  carbs_g numeric(6, 2) not null default 0,
  fat_g numeric(6, 2) not null default 0,
  fiber_g numeric(6, 2) not null default 0,
  sugar_g numeric(6, 2) not null default 0,
  saturated_fat_g numeric(6, 2) not null default 0,
  cholesterol_mg numeric(7, 2) not null default 0,

  -- minerals (per 100g)
  sodium_mg numeric(7, 2) not null default 0,
  potassium_mg numeric(7, 2) not null default 0,
  calcium_mg numeric(7, 2) not null default 0,
  iron_mg numeric(6, 2) not null default 0,
  magnesium_mg numeric(6, 2) not null default 0,
  zinc_mg numeric(6, 2) not null default 0,

  -- vitamins (per 100g)
  vitamin_a_mcg numeric(7, 2) not null default 0,
  vitamin_c_mg numeric(7, 2) not null default 0,
  vitamin_d_mcg numeric(6, 2) not null default 0,
  vitamin_e_mg numeric(6, 2) not null default 0,
  vitamin_k_mcg numeric(7, 2) not null default 0,
  thiamine_b1_mg numeric(6, 3) not null default 0,
  riboflavin_b2_mg numeric(6, 3) not null default 0,
  niacin_b3_mg numeric(6, 2) not null default 0,
  vitamin_b6_mg numeric(6, 3) not null default 0,
  vitamin_b12_mcg numeric(6, 3) not null default 0,
  folate_mcg numeric(7, 2) not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- backs the (TODO, user-implemented) food search
create index foods_name_search_idx on public.foods using gin (to_tsvector('english', name));

alter table public.foods enable row level security;

create policy "foods are readable by any authenticated user" on public.foods
  for select using (auth.role() = 'authenticated');

create policy "users can insert their own foods" on public.foods
  for insert with check (auth.uid() = created_by);

create policy "users can update their own foods" on public.foods
  for update using (auth.uid() = created_by);

create policy "users can delete their own foods" on public.foods
  for delete using (auth.uid() = created_by);
