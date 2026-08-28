-- profiles: one row per auth user (1:1 with auth.users), raw inputs only.
-- Calorie/macro targets are NOT stored here — they're derived client-side
-- (see CalorieCalculator.swift) from these fields, so targets never go stale
-- when the user edits their profile.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  date_of_birth date,
  sex text check (sex in ('male', 'female')),
  height_cm numeric(5, 1),
  weight_kg numeric(5, 1),
  activity_level text check (
    activity_level in ('sedentary', 'light', 'moderate', 'active', 'very_active')
  ),
  goal text check (goal in ('cut', 'maintain', 'bulk')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles are self-viewable" on public.profiles
  for select using (auth.uid() = id);

create policy "profiles are self-insertable" on public.profiles
  for insert with check (auth.uid() = id);

create policy "profiles are self-updatable" on public.profiles
  for update using (auth.uid() = id);
