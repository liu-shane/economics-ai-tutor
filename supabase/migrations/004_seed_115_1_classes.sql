begin;

update public.academic_terms
set is_active = false
where is_active
  and code <> '115-1';

insert into public.academic_terms (
  code,
  name,
  starts_on,
  ends_on,
  timezone,
  is_active
)
values (
  '115-1',
  '115學年度第1學期',
  date '2026-09-07',
  date '2027-01-08',
  'Asia/Taipei',
  true
)
on conflict (code) do update
set name = excluded.name,
    starts_on = excluded.starts_on,
    ends_on = excluded.ends_on,
    timezone = excluded.timezone,
    is_active = excluded.is_active;

with current_term as (
  select id from public.academic_terms where code = '115-1'
)
insert into public.classes (term_id, code, name, active)
select current_term.id, class_data.code, class_data.name, true
from current_term
cross join (
  values
    ('fashion-1a', '時尚一甲'),
    ('fashion-1b', '時尚一乙'),
    ('logistics-1a', '流通一甲'),
    ('trade-1a', '國貿一甲'),
    ('other', '其他')
) as class_data(code, name)
on conflict (term_id, code) do update
set name = excluded.name,
    active = excluded.active,
    updated_at = now();

with assignment_data as (
  select
    c.id as class_id,
    g.id as group_id,
    date '2026-09-07' as valid_from
  from public.classes c
  join public.academic_terms t
    on t.id = c.term_id
   and t.code = '115-1'
  join public.class_groups g
    on g.code = case c.code
      when 'fashion-1a' then 'fashion'
      when 'fashion-1b' then 'fashion'
      when 'logistics-1a' then 'logistics'
      when 'trade-1a' then 'international_trade'
    end
  where c.code in ('fashion-1a', 'fashion-1b', 'logistics-1a', 'trade-1a')
)
insert into public.class_group_assignments (class_id, group_id, valid_from)
select a.class_id, a.group_id, a.valid_from
from assignment_data a
where not exists (
  select 1
  from public.class_group_assignments existing
  where existing.class_id = a.class_id
    and existing.valid_to is null
);

commit;

select
  t.name as term_name,
  t.starts_on,
  t.ends_on,
  c.name as class_name,
  coalesce(g.name, '不納入排行榜') as leaderboard_group
from public.classes c
join public.academic_terms t on t.id = c.term_id
left join public.class_group_assignments a
  on a.class_id = c.id
 and a.valid_to is null
left join public.class_groups g on g.id = a.group_id
where t.code = '115-1'
order by c.code;
