begin;

create or replace function public.teacher_issue_activation_code(
  requested_class_name text,
  requested_student_number text,
  activation_code text,
  requested_roster_nickname text default null,
  expires_at timestamptz default null
)
returns public.enrollments
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  current_term public.academic_terms;
  matched_class public.classes;
  result public.enrollments;
  normalized_number text := upper(trim(requested_student_number));
begin
  if not public.is_teacher() then raise exception 'TEACHER_REQUIRED'; end if;
  if normalized_number !~ '^[A-Z][0-9]{8}$' then raise exception 'INVALID_STUDENT_NUMBER'; end if;
  if length(activation_code) < 6 then raise exception 'ACTIVATION_CODE_TOO_SHORT'; end if;

  select * into current_term from public.academic_terms where is_active limit 1;
  if current_term.id is null then raise exception 'NO_ACTIVE_TERM'; end if;
  select * into matched_class from public.classes
  where term_id=current_term.id and active and name=trim(requested_class_name) limit 1;
  if matched_class.id is null then raise exception 'CLASS_NOT_FOUND'; end if;

  insert into public.enrollments(
    term_id,class_id,student_number,roster_nickname,
    activation_code_hash,activation_expires_at,active
  ) values(
    current_term.id,matched_class.id,normalized_number,nullif(trim(requested_roster_nickname),''),
    crypt(activation_code,gen_salt('bf')),expires_at,true
  )
  on conflict(term_id,class_id,student_number) do update set
    roster_nickname=coalesce(excluded.roster_nickname,public.enrollments.roster_nickname),
    activation_code_hash=excluded.activation_code_hash,
    activation_expires_at=excluded.activation_expires_at,
    active=true,
    updated_at=now()
  returning * into result;

  insert into public.audit_logs(actor_user_id,action,target_type,target_id,metadata)
  values(auth.uid(),'enrollment.activation_issued','enrollment',result.id::text,
    jsonb_build_object('class_name',matched_class.name,'student_number',normalized_number));
  return result;
end;
$$;

create or replace function public.teacher_reset_student_device(
  requested_enrollment_id uuid,
  new_activation_code text,
  expires_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_teacher() then raise exception 'TEACHER_REQUIRED'; end if;
  if length(new_activation_code) < 6 then raise exception 'ACTIVATION_CODE_TOO_SHORT'; end if;
  update public.enrollments set
    user_id=null,
    activated_at=null,
    activation_code_hash=crypt(new_activation_code,gen_salt('bf')),
    activation_expires_at=expires_at,
    updated_at=now()
  where id=requested_enrollment_id;
  if not found then raise exception 'ENROLLMENT_NOT_FOUND'; end if;
  insert into public.audit_logs(actor_user_id,action,target_type,target_id)
  values(auth.uid(),'enrollment.device_reset','enrollment',requested_enrollment_id::text);
  return true;
end;
$$;

revoke all on function public.teacher_issue_activation_code(text,text,text,text,timestamptz) from public;
revoke all on function public.teacher_reset_student_device(uuid,text,timestamptz) from public;
grant execute on function public.teacher_issue_activation_code(text,text,text,text,timestamptz) to authenticated;
grant execute on function public.teacher_reset_student_device(uuid,text,timestamptz) to authenticated;

commit;
