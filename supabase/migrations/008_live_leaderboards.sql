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
      coalesce(nullif(p.nickname,''),left(e.student_number,5)||'****') display_name,
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

create or replace function public.update_my_leaderboard_profile(
  requested_nickname text,
  requested_public boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare clean_nickname text := nullif(trim(requested_nickname),'');
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if clean_nickname is not null and char_length(clean_nickname) not between 1 and 30 then raise exception 'INVALID_NICKNAME'; end if;
  insert into public.profiles(user_id,nickname,leaderboard_public)
  values(auth.uid(),clean_nickname,coalesce(requested_public,true))
  on conflict(user_id) do update set nickname=excluded.nickname,leaderboard_public=excluded.leaderboard_public,updated_at=now();
  insert into public.audit_logs(actor_user_id,action,target_type,target_id,metadata)
  values(auth.uid(),'leaderboard.profile_updated','profile',auth.uid()::text,jsonb_build_object('public',coalesce(requested_public,true)));
  return jsonb_build_object('nickname',clean_nickname,'public',coalesce(requested_public,true));
end;
$$;

create or replace function public.list_my_leaderboard_weeks()
returns table(week_start date)
language sql
security definer
set search_path = public
as $$
  select distinct pe.week_start
  from public.point_events pe
  join public.enrollments e on e.id=pe.enrollment_id
  where e.user_id=auth.uid() and pe.status='posted'
  order by pe.week_start desc;
$$;

revoke all on function public.get_learning_leaderboard(text,text,date) from public;
revoke all on function public.update_my_leaderboard_profile(text,boolean) from public;
revoke all on function public.list_my_leaderboard_weeks() from public;
grant execute on function public.get_learning_leaderboard(text,text,date) to authenticated;
grant execute on function public.update_my_leaderboard_profile(text,boolean) to authenticated;
grant execute on function public.list_my_leaderboard_weeks() to authenticated;

commit;

select 'leaderboard functions ready' as status;
