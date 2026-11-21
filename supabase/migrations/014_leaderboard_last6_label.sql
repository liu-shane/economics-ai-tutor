begin;

create or replace function public.get_learning_leaderboard(
  requested_type text,
  requested_scope text default 'weekly',
  requested_week_start date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_week date := coalesce(requested_week_start,date_trunc('week',now() at time zone 'Asia/Taipei')::date);
  result jsonb;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if requested_type not in ('trade_logistics','fashion','all') then raise exception 'INVALID_LEADERBOARD_TYPE'; end if;
  if requested_scope not in ('weekly','semester') then raise exception 'INVALID_LEADERBOARD_SCOPE'; end if;

  with eligible as (
    select
      e.id enrollment_id,
      e.user_id,
      e.student_number,
      c.name class_name,
      cg.code group_code,
      coalesce(nullif(trim(p.nickname),''),right(e.student_number,6)) display_name,
      coalesce(p.leaderboard_public,true) leaderboard_public,
      coalesce(sum(pe.points) filter (
        where pe.status='posted'
          and (requested_scope='semester' or pe.week_start=target_week)
      ),0)::int points
    from public.enrollments e
    join public.academic_terms t on t.id=e.term_id and t.is_active
    join public.classes c on c.id=e.class_id and c.active
    join public.class_group_assignments cga on cga.class_id=c.id and cga.valid_to is null
    join public.class_groups cg on cg.id=cga.group_id and cg.active
    left join public.profiles p on p.user_id=e.user_id
    left join public.point_events pe on pe.enrollment_id=e.id and pe.term_id=t.id
    where e.active and e.user_id is not null
      and (
        requested_type='all'
        or (requested_type='fashion' and cg.code='fashion')
        or (requested_type='trade_logistics' and cg.code in ('international_trade','logistics'))
      )
    group by e.id,e.user_id,e.student_number,c.name,cg.code,p.nickname,p.leaderboard_public
  ), ranked as (
    select *,rank() over(order by points desc) rank_number
    from eligible where points>0
  )
  select jsonb_build_object(
    'type',requested_type,
    'scope',requested_scope,
    'weekStart',target_week,
    'top',coalesce((select jsonb_agg(jsonb_build_object(
      'rank',rank_number,'className',class_name,'nickname',display_name,'points',points
    ) order by rank_number,student_number) from ranked where leaderboard_public and rank_number<=10),'[]'::jsonb),
    'me',(select jsonb_build_object(
      'rank',rank_number,'className',class_name,'nickname',display_name,'points',points,
      'public',leaderboard_public
    ) from ranked where user_id=auth.uid() limit 1)
  ) into result;
  return result;
end;
$$;

create or replace function public.get_teacher_learning_leaderboard(
  requested_type text default 'all',
  requested_scope text default 'weekly',
  requested_week_start date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_week date := coalesce(requested_week_start,date_trunc('week',now() at time zone 'Asia/Taipei')::date);
  result jsonb;
begin
  if not public.is_teacher() then raise exception 'TEACHER_REQUIRED'; end if;
  if requested_type not in ('trade_logistics','fashion','all') then raise exception 'INVALID_LEADERBOARD_TYPE'; end if;
  if requested_scope not in ('weekly','semester') then raise exception 'INVALID_LEADERBOARD_SCOPE'; end if;

  with eligible as (
    select
      e.user_id,
      e.student_number,
      c.name class_name,
      coalesce(nullif(trim(p.nickname),''),right(e.student_number,6)) display_name,
      coalesce(p.leaderboard_public,true) leaderboard_public,
      coalesce(sum(pe.points) filter (
        where pe.status='posted'
          and (requested_scope='semester' or pe.week_start=target_week)
      ),0)::int points
    from public.enrollments e
    join public.academic_terms t on t.id=e.term_id and t.is_active
    join public.classes c on c.id=e.class_id and c.active
    join public.class_group_assignments cga on cga.class_id=c.id and cga.valid_to is null
    join public.class_groups cg on cg.id=cga.group_id and cg.active
    left join public.profiles p on p.user_id=e.user_id
    left join public.point_events pe on pe.enrollment_id=e.id and pe.term_id=t.id
    where e.active and e.user_id is not null
      and (
        requested_type='all'
        or (requested_type='fashion' and cg.code='fashion')
        or (requested_type='trade_logistics' and cg.code in ('international_trade','logistics'))
      )
    group by e.id,e.user_id,e.student_number,c.name,p.nickname,p.leaderboard_public
  ), ranked as (
    select *,rank() over(order by points desc) rank_number
    from eligible where points>0
  )
  select jsonb_build_object(
    'type',requested_type,
    'scope',requested_scope,
    'weekStart',target_week,
    'count',count(*),
    'entries',coalesce(jsonb_agg(jsonb_build_object(
      'rank',rank_number,
      'className',class_name,
      'studentNumber',student_number,
      'nickname',display_name,
      'points',points,
      'public',leaderboard_public
    ) order by rank_number,student_number),'[]'::jsonb)
  ) into result
  from ranked;

  return result;
end;
$$;

revoke all on function public.get_learning_leaderboard(text,text,date) from public;
grant execute on function public.get_learning_leaderboard(text,text,date) to authenticated;
revoke all on function public.get_teacher_learning_leaderboard(text,text,date) from public;
grant execute on function public.get_teacher_learning_leaderboard(text,text,date) to authenticated;

commit;

