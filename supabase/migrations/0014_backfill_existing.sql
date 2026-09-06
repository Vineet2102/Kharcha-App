-- The one pre-existing household predates created_by / joined_at / invites.
update public.households h
   set created_by = (select p.id from public.profiles p
                      where p.household_id = h.id and p.role = 'admin'
                      order by p.created_at limit 1)
 where h.created_by is null;

update public.profiles
   set joined_at = coalesce(joined_at, created_at)
 where household_id is not null and joined_at is null;

insert into public.household_invites (household_id, code, created_by, expires_at, max_uses)
select h.id, public.gen_invite_code(), h.created_by, now() + interval '365 days', 50
  from public.households h
 where h.created_by is not null
   and not exists (select 1 from public.household_invites i where i.household_id = h.id);

-- 0009_seed.sql stays in the repo as history. Never re-run it — it seeds one
-- hardcoded household id. New households are seeded by seed_household_defaults().
