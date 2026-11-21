begin;

create or replace function public.claim_enrollment_without_code(
  requested_class_name text,
  requested_student_number text
)
returns public.enrollments
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  matched public.enrollments;
  old_user_id uuid;
  new_user_id uuid := auth.uid();
  old_nickname text;
  old_leaderboard_public boolean;
  normalized_class_name text := trim(requested_class_name);
  normalized_number text := upper(trim(requested_student_number));
begin
  if new_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if normalized_number !~ '^[A-Z][0-9]{8}$' then
    raise exception 'INVALID_STUDENT_NUMBER';
  end if;

  select e.* into matched
  from public.enrollments e
  join public.classes c
    on c.id = e.class_id
   and c.active
  join public.academic_terms t
    on t.id = e.term_id
   and t.is_active
  where c.name = normalized_class_name
    and e.student_number = normalized_number
    and e.active
  for update of e;

  if matched.id is null then
    raise exception 'ENROLLMENT_NOT_FOUND';
  end if;

  old_user_id := matched.user_id;
  if old_user_id = new_user_id then
    return matched;
  end if;

  if exists (
    select 1 from public.enrollments e
    where e.user_id = new_user_id
      and e.active
      and e.id <> matched.id
  ) then
    raise exception 'USER_ALREADY_ENROLLED';
  end if;

  if old_user_id is not null then
    select p.nickname,p.leaderboard_public
      into old_nickname,old_leaderboard_public
    from public.profiles p
    where p.user_id=old_user_id;

    update public.quiz_attempts set user_id=new_user_id where user_id=old_user_id;
    update public.consultations set user_id=new_user_id where user_id=old_user_id;
    update public.extension_responses set user_id=new_user_id where user_id=old_user_id;
    update public.point_events set user_id=new_user_id where user_id=old_user_id;
    update public.challenge_reports set user_id=new_user_id where user_id=old_user_id;
    update public.leaderboard_entries set user_id=new_user_id where user_id=old_user_id;
    update storage.objects set owner_id=new_user_id::text where owner_id=old_user_id::text;
    update public.enrollments set user_id=new_user_id,updated_at=now() where user_id=old_user_id;

    update public.profiles
    set nickname=coalesce(left(old_nickname,20),nickname),
        leaderboard_public=coalesce(old_leaderboard_public,leaderboard_public),
        updated_at=now()
    where user_id=new_user_id;
  else
    update public.enrollments
    set user_id=new_user_id,
        activated_at=coalesce(activated_at,now()),
        updated_at=now()
    where id=matched.id;
  end if;

  select * into matched from public.enrollments where id=matched.id;

  insert into public.audit_logs(actor_user_id,action,target_type,target_id,metadata)
  values(
    new_user_id,
    'enrollment.claimed_without_code',
    'enrollment',
    matched.id::text,
    jsonb_build_object(
      'class_name',normalized_class_name,
      'student_number',normalized_number,
      'previous_user_id',old_user_id,
      'records_preserved',true
    )
  );

  return matched;
end;
$$;

revoke all on function public.claim_enrollment_without_code(text,text) from public;
grant execute on function public.claim_enrollment_without_code(text,text) to authenticated;

commit;
