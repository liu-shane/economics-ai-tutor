begin;

create or replace function public.activate_enrollment_by_class_name(
  requested_class_name text,
  requested_student_number text,
  activation_code text
)
returns public.enrollments
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  matched public.enrollments;
  normalized_class_name text := trim(requested_class_name);
  normalized_number text := upper(trim(requested_student_number));
begin
  if auth.uid() is null then
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
  if matched.user_id is not null and matched.user_id <> auth.uid() then
    raise exception 'ENROLLMENT_ALREADY_CLAIMED';
  end if;
  if matched.activation_expires_at is not null and matched.activation_expires_at < now() then
    raise exception 'ACTIVATION_CODE_EXPIRED';
  end if;
  if matched.activation_code_hash is null
     or crypt(activation_code, matched.activation_code_hash) <> matched.activation_code_hash then
    raise exception 'INVALID_ACTIVATION_CODE';
  end if;
  if exists (
    select 1
    from public.enrollments e
    where e.term_id = matched.term_id
      and e.user_id = auth.uid()
      and e.active
      and e.id <> matched.id
  ) then
    raise exception 'USER_ALREADY_ENROLLED';
  end if;

  update public.enrollments
  set user_id = auth.uid(),
      activated_at = coalesce(activated_at, now()),
      activation_code_hash = null,
      activation_expires_at = null,
      updated_at = now()
  where id = matched.id
  returning * into matched;

  insert into public.audit_logs(actor_user_id, action, target_type, target_id, metadata)
  values(
    auth.uid(),
    'enrollment.activated',
    'enrollment',
    matched.id::text,
    jsonb_build_object(
      'class_name', normalized_class_name,
      'student_number', normalized_number,
      'activation_method', 'class_name'
    )
  );

  return matched;
end;
$$;

revoke all on function public.activate_enrollment_by_class_name(text,text,text) from public;
grant execute on function public.activate_enrollment_by_class_name(text,text,text) to authenticated;

commit;
