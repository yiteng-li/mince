-- weight_logs: one weigh-in per user per day (upsert on conflict to correct
-- a same-day entry rather than creating duplicates).

create table public.weight_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  logged_on date not null default current_date,
  weight_kg numeric(5, 1) not null,
  created_at timestamptz not null default now(),
  unique (user_id, logged_on)
);

alter table public.weight_logs enable row level security;

create policy "weight logs are self-viewable" on public.weight_logs
  for select using (auth.uid() = user_id);

create policy "weight logs are self-insertable" on public.weight_logs
  for insert with check (auth.uid() = user_id);

create policy "weight logs are self-updatable" on public.weight_logs
  for update using (auth.uid() = user_id);

create policy "weight logs are self-deletable" on public.weight_logs
  for delete using (auth.uid() = user_id);
