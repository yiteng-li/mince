grant usage on schema public to authenticated;
grant all on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
insert into auth.users values ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b');
select count(*) as groups_created from diary_groups;  -- expect 8
-- nutrients come from reference data
insert into foods (source, source_id, name, nutrients) values ('usda','1','Almonds','{"energy":579,"protein":21,"magnesium":270}'),('usda','2','Banana','{"energy":89,"protein":1.1,"magnesium":27}');
-- biometric types come from reference data

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select name from search_foods('almond');
select name from search_foods('almnds');  -- trigram typo
insert into diary_entries (user_id, day, kind, group_id, food_id, amount_g)
  select auth.uid(), '2026-11-05', 'food', (select id from diary_groups where position=0), id, 50 from foods where name='Almonds';
insert into diary_entries (user_id, day, kind, nutrients) values (auth.uid(),'2026-11-05','quick_add','{"energy":100}');
select * from nutrient_totals('2026-11-05','2026-11-05') order by 2;
do $$ begin perform nutrient_totals('2026-10-01','2026-11-05'); raise exception 'gate failed'; exception when sqlstate 'P0001' then if sqlerrm <> 'plus_required' then raise; end if; end $$;
-- timestamps need mince+
do $$ begin insert into diary_entries (user_id, day, kind, note, logged_at) values (auth.uid(),'2026-11-05','note','x',now()); raise exception 'rls failed'; exception when insufficient_privilege then null; end $$;
-- recipe
insert into foods (user_id, kind, source, name, recipe_yield_g) values (auth.uid(),'recipe','recipe','Trail mix',null);
insert into recipe_ingredients (recipe_id, food_id, amount_g) select (select id from foods where name='Trail mix'), id, 100 from foods where source='usda';
select recompute_recipe(id) from foods where name='Trail mix';
select nutrients from foods where name='Trail mix';
-- user b cannot see a's recipe
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select count(*) as b_sees_trailmix from foods where name='Trail mix';
select count(*) as b_sees_a_entries from diary_entries;
reset role;
insert into subscriptions values ('t1','00000000-0000-0000-0000-00000000000a','mince.plus.annual','active',now()+interval '1 year','Sandbox');
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select count(*) as long_range_rows from nutrient_totals('2026-10-01','2026-11-05');
insert into repeat_rules (user_id, food_id, amount_g, weekdays, starts_on) select auth.uid(), id, 120, '{0,1,2,3,4,5,6}', '2026-11-01' from foods where name='Banana';
select materialize_repeats('2026-11-06') as first, materialize_repeats('2026-11-06') as second;
delete from diary_entries where day='2026-11-06';
select materialize_repeats('2026-11-06') as after_delete;
select name from oracle('magnesium');
insert into fasts (user_id, started_at, target_minutes) values (auth.uid(), now(), 960);
do $$ begin insert into fasts (user_id, started_at, target_minutes) values (auth.uid(), now(), 960); raise exception 'two open fasts'; exception when unique_violation then null; end $$;
select 'ALL OK';
