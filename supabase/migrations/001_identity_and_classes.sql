begin;

create extension if not exists pgcrypto;

create table public.academic_terms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  starts_on date not null,
  ends_on date not null,
  timezone text not null default 'Asia/Taipei',
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  constraint academic_terms_dates_check check (ends_on >= starts_on),
  constraint academic_terms_timezone_check check (timezone = 'Asia/Taipei')
);

create unique index academic_terms_one_active_idx
  on public.academic_terms (is_active)
  where is_active;

create table public.class_groups (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint class_groups_code_check
    check (code in ('international_trade', 'logistics', 'fashion'))
);

insert into public.class_groups (code, name, sort_order)
values
  ('international_trade', '國貿', 10),
  ('logistics', '流通', 20),
  ('fashion', '時尚', 30)
on conflict (code) do nothing;

create table public.classes (
  id uuid primary key default gen_random_uuid(),
  term_id uuid not null references public.academic_terms(id) on delete restrict,
  code text not null,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (term_id, code),
  unique (term_id, name)
);

create table public.class_group_assignments (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  group_id uuid not null references public.class_groups(id) on delete restrict,
  valid_from date not null,
  valid_to date,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  constraint class_group_assignment_dates_check
    check (valid_to is null or valid_to >= valid_from)
);

create unique index class_group_assignments_one_current_idx
  on public.class_group_assignments(class_id)
  where valid_to is null;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text,
  leaderboard_public boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_nickname_length_check
    check (nickname is null or char_length(nickname) between 1 and 30)
);

create table public.teacher_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'teacher',
  active boolean not null default true,
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id) on delete set null,
  constraint teacher_roles_role_check check (role in ('teacher', 'admin'))
);

create table public.enrollments (
  id uuid primary key default gen_random_uuid(),
  term_id uuid not null references public.academic_terms(id) on delete restrict,
  class_id uuid not null references public.classes(id) on delete restrict,
  student_number text not null,
  user_id uuid references auth.users(id) on delete set null,
  roster_nickname text,
  activation_code_hash text,
  activation_expires_at timestamptz,
  activated_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (term_id, class_id, student_number),
  constraint enrollments_student_number_check
    check (student_number ~ '^[A-Z][0-9]{8}$'),
  constraint enrollments_activation_check check (
    (user_id is null and activated_at is null)
    or (user_id is not null and activated_at is not null)
  )
);

create unique index enrollments_one_user_per_term_idx
  on public.enrollments(term_id, user_id)
  where user_id is not null and active;

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger classes_touch_updated_at
before update on public.classes
for each row execute function public.touch_updated_at();

create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();

create trigger enrollments_touch_updated_at
before update on public.enrollments
for each row execute function public.touch_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (user_id, nickname)
  values (new.id, nullif(left(coalesce(new.raw_user_meta_data ->> 'name', ''), 30), ''))
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

create or replace function public.is_teacher(check_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.teacher_roles tr
    where tr.user_id = check_user_id
      and tr.active
  );
$$;

create or replace function public.activate_enrollment(
  requested_class_id uuid,
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
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select * into matched
  from public.enrollments e
  where e.class_id = requested_class_id
    and e.student_number = upper(trim(requested_student_number))
    and e.active
  for update;

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
    select 1 from public.enrollments e
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

  insert into public.audit_logs(actor_user_id, action, target_type, target_id)
  values(auth.uid(), 'enrollment.activated', 'enrollment', matched.id::text);

  return matched;
end;
$$;

revoke all on function public.activate_enrollment(uuid, text, text) from public;
grant execute on function public.activate_enrollment(uuid, text, text) to authenticated;

commit;
