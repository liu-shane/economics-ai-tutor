begin;

create table public.quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  enrollment_id uuid not null references public.enrollments(id) on delete restrict,
  unit_code text not null,
  question_count integer not null,
  correct_count integer,
  score integer,
  status text not null default 'started',
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at timestamptz not null default (now() + interval '2 hours'),
  idempotency_key text not null unique,
  constraint quiz_attempts_question_count_check check (question_count in (5, 10)),
  constraint quiz_attempts_score_check check (score is null or score between 0 and 100),
  constraint quiz_attempts_correct_count_check
    check (correct_count is null or correct_count between 0 and question_count),
  constraint quiz_attempts_status_check
    check (status in ('started', 'completed', 'expired', 'void'))
);

create table public.quiz_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.quiz_attempts(id) on delete cascade,
  question_id text not null,
  question_order integer not null,
  student_answer jsonb not null,
  correct_answer jsonb not null,
  is_correct boolean not null,
  explanation text not null,
  answered_at timestamptz not null default now(),
  unique (attempt_id, question_id),
  unique (attempt_id, question_order)
);

create table public.consultations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  enrollment_id uuid not null references public.enrollments(id) on delete restrict,
  topic text not null,
  question text not null,
  normalized_question_hash text not null,
  answer text not null,
  status text not null default 'answered',
  created_at timestamptz not null default now(),
  idempotency_key text not null unique,
  constraint consultations_status_check
    check (status in ('answered', 'invalid', 'void'))
);

create index consultations_duplicate_guard_idx
  on public.consultations(user_id, normalized_question_hash, created_at);

create table public.consultation_checks (
  id uuid primary key default gen_random_uuid(),
  consultation_id uuid not null unique references public.consultations(id) on delete cascade,
  question text not null,
  choices jsonb not null,
  student_answer integer,
  correct_answer integer not null,
  is_correct boolean,
  answered_at timestamptz,
  created_at timestamptz not null default now(),
  constraint consultation_check_answer_check
    check (correct_answer between 0 and 3 and (student_answer is null or student_answer between 0 and 3))
);

create table public.extension_responses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  consultation_id uuid not null references public.consultations(id) on delete cascade,
  prompt text not null,
  response text not null,
  completed_at timestamptz not null default now(),
  idempotency_key text not null unique
);

create table public.point_rules (
  event_type text not null,
  version integer not null,
  points integer not null,
  daily_limit integer,
  effective_from date not null,
  effective_to date,
  active boolean not null default true,
  primary key (event_type, version),
  constraint point_rules_event_type_check check (event_type in (
    'daily_first_learning', 'quiz_completed', 'question_first_correct',
    'consultation_valid', 'extension_completed', 'challenge_submitted',
    'challenge_approved', 'challenge_full_explanation', 'reversal'
  )),
  constraint point_rules_dates_check check (effective_to is null or effective_to >= effective_from)
);

insert into public.point_rules(event_type, version, points, daily_limit, effective_from)
values
  ('daily_first_learning', 1, 2, 1, current_date),
  ('quiz_completed', 1, 10, 3, current_date),
  ('question_first_correct', 1, 2, null, current_date),
  ('consultation_valid', 1, 3, 5, current_date),
  ('extension_completed', 1, 5, 2, current_date),
  ('challenge_submitted', 1, 5, 2, current_date),
  ('challenge_approved', 1, 20, null, current_date),
  ('challenge_full_explanation', 1, 10, null, current_date)
on conflict do nothing;

create table public.point_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  enrollment_id uuid not null references public.enrollments(id) on delete restrict,
  term_id uuid not null references public.academic_terms(id) on delete restrict,
  class_id uuid not null references public.classes(id) on delete restrict,
  group_id uuid references public.class_groups(id) on delete restrict,
  event_type text not null,
  points integer not null,
  rule_version integer,
  source_type text not null,
  source_id text not null,
  local_date date not null,
  week_start date not null,
  status text not null default 'posted',
  idempotency_key text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  awarded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint point_events_status_check check (status in ('posted', 'reversed')),
  constraint point_events_week_start_check
    check (extract(isodow from week_start) = 1)
);

create index point_events_weekly_leaderboard_idx
  on public.point_events(term_id, group_id, week_start, status, user_id);
create index point_events_semester_leaderboard_idx
  on public.point_events(term_id, status, user_id);

create table public.challenge_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  enrollment_id uuid not null references public.enrollments(id) on delete restrict,
  source_type text not null,
  source_id text not null,
  error_type text not null,
  original_answer text not null,
  proposed_answer text not null,
  rationale text not null,
  references_text text,
  status text not null default 'submitted',
  idempotency_key text not null unique,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint challenge_reports_source_type_check check (source_type in ('quiz', 'consultation')),
  constraint challenge_reports_status_check check (status in ('submitted', 'under_review', 'approved', 'rejected', 'needs_revision'))
);

create trigger challenge_reports_touch_updated_at
before update on public.challenge_reports
for each row execute function public.touch_updated_at();

create table public.challenge_attachments (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.challenge_reports(id) on delete cascade,
  storage_path text not null unique,
  mime_type text not null,
  size_bytes bigint not null,
  uploaded_at timestamptz not null default now(),
  constraint challenge_attachment_size_check check (size_bytes > 0 and size_bytes <= 10485760),
  constraint challenge_attachment_mime_check check (mime_type in ('image/png', 'image/jpeg', 'image/webp'))
);

create table public.challenge_reviews (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null unique references public.challenge_reports(id) on delete cascade,
  reviewer_user_id uuid not null references auth.users(id) on delete restrict,
  decision text not null,
  feedback text not null,
  correction_confirmed boolean not null default false,
  full_explanation_confirmed boolean not null default false,
  reviewed_at timestamptz not null default now(),
  constraint challenge_reviews_decision_check check (decision in ('approved', 'rejected', 'needs_revision')),
  constraint challenge_reviews_explanation_requires_correction
    check (not full_explanation_confirmed or correction_confirmed)
);

create table public.content_revisions (
  id uuid primary key default gen_random_uuid(),
  content_type text not null,
  content_key text not null,
  previous_value jsonb,
  new_value jsonb not null,
  reason text not null,
  changed_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint content_revisions_type_check check (content_type in ('question', 'explanation', 'ai_prompt', 'consultation_knowledge'))
);

create table public.leaderboard_snapshots (
  id uuid primary key default gen_random_uuid(),
  term_id uuid not null references public.academic_terms(id) on delete restrict,
  leaderboard_type text not null,
  week_start date not null,
  week_end date not null,
  generated_at timestamptz not null default now(),
  unique(term_id, leaderboard_type, week_start),
  constraint leaderboard_snapshot_type_check check (leaderboard_type in ('trade_logistics', 'fashion', 'all')),
  constraint leaderboard_snapshot_dates_check check (week_end = week_start + 7)
);

create table public.leaderboard_entries (
  snapshot_id uuid not null references public.leaderboard_snapshots(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  class_id uuid not null references public.classes(id) on delete restrict,
  rank integer not null,
  points integer not null,
  public_at_snapshot boolean not null,
  nickname_at_snapshot text,
  primary key(snapshot_id, user_id),
  constraint leaderboard_entries_rank_check check (rank > 0),
  constraint leaderboard_entries_points_check check (points >= 0)
);

commit;
