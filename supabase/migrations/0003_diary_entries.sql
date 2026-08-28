-- diary_entries: one logged food per row. No nutrient snapshot here on
-- purpose — quantity_g + food_id join back to foods, so totals reflect
-- the food's current data and the aggregation itself is left as the
-- user's TODO in DiaryViewModel.

create table public.diary_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  food_id uuid not null references public.foods (id) on delete restrict,
  logged_on date not null default current_date,
  meal_type text not null check (meal_type in ('breakfast', 'lunch', 'dinner', 'snack')),
  quantity_g numeric(7, 2) not null check (quantity_g > 0),
  created_at timestamptz not null default now()
);

create index diary_entries_user_day_idx on public.diary_entries (user_id, logged_on);

alter table public.diary_entries enable row level security;

create policy "diary entries are self-viewable" on public.diary_entries
  for select using (auth.uid() = user_id);

create policy "diary entries are self-insertable" on public.diary_entries
  for insert with check (auth.uid() = user_id);

create policy "diary entries are self-updatable" on public.diary_entries
  for update using (auth.uid() = user_id);

create policy "diary entries are self-deletable" on public.diary_entries
  for delete using (auth.uid() = user_id);
