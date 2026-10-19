alter table public.academic_terms enable row level security;
alter table public.class_groups enable row level security;
alter table public.classes enable row level security;
alter table public.class_group_assignments enable row level security;
alter table public.profiles enable row level security;
alter table public.teacher_roles enable row level security;
alter table public.enrollments enable row level security;
alter table public.audit_logs enable row level security;
alter table public.quiz_attempts enable row level security;
alter table public.quiz_answers enable row level security;
alter table public.consultations enable row level security;
alter table public.consultation_checks enable row level security;
alter table public.extension_responses enable row level security;
alter table public.point_rules enable row level security;
alter table public.point_events enable row level security;
alter table public.challenge_reports enable row level security;
alter table public.challenge_attachments enable row level security;
alter table public.challenge_reviews enable row level security;
alter table public.content_revisions enable row level security;
alter table public.leaderboard_snapshots enable row level security;
alter table public.leaderboard_entries enable row level security;

create policy "public reads active terms"
on public.academic_terms for select
using (is_active or public.is_teacher());

create policy "public reads active class groups"
on public.class_groups for select
using (active or public.is_teacher());

create policy "public reads active classes"
on public.classes for select
using (active or public.is_teacher());

create policy "authenticated reads current group assignments"
on public.class_group_assignments for select to authenticated
using (valid_to is null or public.is_teacher());

create policy "teachers manage terms"
on public.academic_terms for all to authenticated
using (public.is_teacher()) with check (public.is_teacher());
create policy "teachers manage class groups"
on public.class_groups for all to authenticated
using (public.is_teacher()) with check (public.is_teacher());
create policy "teachers manage classes"
on public.classes for all to authenticated
using (public.is_teacher()) with check (public.is_teacher());
create policy "teachers manage group assignments"
on public.class_group_assignments for all to authenticated
using (public.is_teacher()) with check (public.is_teacher());

create policy "users read own profile"
on public.profiles for select to authenticated
using (user_id = auth.uid() or public.is_teacher());
create policy "users update own profile"
on public.profiles for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "teachers read their role"
on public.teacher_roles for select to authenticated
using (user_id = auth.uid() or public.is_teacher());

create policy "students read own enrollment"
on public.enrollments for select to authenticated
using (user_id = auth.uid() or public.is_teacher());
create policy "teachers manage enrollments"
on public.enrollments for all to authenticated
using (public.is_teacher()) with check (public.is_teacher());

create policy "teachers read audit logs"
on public.audit_logs for select to authenticated
using (public.is_teacher());

create policy "students read own quiz attempts"
on public.quiz_attempts for select to authenticated
using (user_id = auth.uid() or public.is_teacher());
create policy "students read own quiz answers"
on public.quiz_answers for select to authenticated
using (
  exists (
    select 1 from public.quiz_attempts qa
    where qa.id = attempt_id
      and (qa.user_id = auth.uid() or public.is_teacher())
  )
);

create policy "students read own consultations"
on public.consultations for select to authenticated
using (user_id = auth.uid() or public.is_teacher());
create policy "students read own consultation checks"
on public.consultation_checks for select to authenticated
using (
  exists (
    select 1 from public.consultations c
    where c.id = consultation_id
      and (c.user_id = auth.uid() or public.is_teacher())
  )
);
create policy "students read own extension responses"
on public.extension_responses for select to authenticated
using (user_id = auth.uid() or public.is_teacher());

create policy "authenticated reads active point rules"
on public.point_rules for select to authenticated
using (active or public.is_teacher());
create policy "students read own point events"
on public.point_events for select to authenticated
using (user_id = auth.uid() or public.is_teacher());

create policy "students read own challenge reports"
on public.challenge_reports for select to authenticated
using (user_id = auth.uid() or public.is_teacher());
create policy "students read own challenge attachments"
on public.challenge_attachments for select to authenticated
using (
  exists (
    select 1 from public.challenge_reports cr
    where cr.id = report_id
      and (cr.user_id = auth.uid() or public.is_teacher())
  )
);
create policy "students read own challenge reviews"
on public.challenge_reviews for select to authenticated
using (
  exists (
    select 1 from public.challenge_reports cr
    where cr.id = report_id
      and (cr.user_id = auth.uid() or public.is_teacher())
  )
);

create policy "teachers read content revisions"
on public.content_revisions for select to authenticated
using (public.is_teacher());
create policy "teachers manage content revisions"
on public.content_revisions for insert to authenticated
with check (public.is_teacher() and changed_by = auth.uid());

create policy "authenticated reads leaderboard snapshots"
on public.leaderboard_snapshots for select to authenticated
using (true);
create policy "authenticated reads public leaderboard entries"
on public.leaderboard_entries for select to authenticated
using (public_at_snapshot or user_id = auth.uid() or public.is_teacher());

revoke insert, update, delete on public.quiz_attempts from anon, authenticated;
revoke insert, update, delete on public.quiz_answers from anon, authenticated;
revoke insert, update, delete on public.consultations from anon, authenticated;
revoke insert, update, delete on public.consultation_checks from anon, authenticated;
revoke insert, update, delete on public.extension_responses from anon, authenticated;
revoke insert, update, delete on public.point_events from anon, authenticated;
revoke insert, update, delete on public.challenge_reviews from anon, authenticated;
revoke insert, update, delete on public.leaderboard_snapshots from anon, authenticated;
revoke insert, update, delete on public.leaderboard_entries from anon, authenticated;
revoke all on public.audit_logs from anon, authenticated;
grant select on public.audit_logs to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'challenge-evidence',
  'challenge-evidence',
  false,
  10485760,
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "students upload challenge evidence to own folder"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'challenge-evidence'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "students and teachers read challenge evidence"
on storage.objects for select to authenticated
using (
  bucket_id = 'challenge-evidence'
  and (
    owner_id = auth.uid()::text
    or public.is_teacher()
  )
);

create policy "students delete unreviewed own challenge evidence"
on storage.objects for delete to authenticated
using (
  bucket_id = 'challenge-evidence'
  and owner_id = auth.uid()::text
  and not exists (
    select 1
    from public.challenge_attachments ca
    join public.challenge_reviews cr on cr.report_id = ca.report_id
    where ca.storage_path = name
  )
);
