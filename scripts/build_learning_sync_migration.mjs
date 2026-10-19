import fs from 'node:fs/promises';
import vm from 'node:vm';
import crypto from 'node:crypto';

const source=await fs.readFile(new URL('../question-bank.js',import.meta.url),'utf8');
const context={window:{}};
vm.createContext(context);
vm.runInContext(source,context);
const bank=context.window.QUESTION_BANK;
const rows=[];
for(const [unit,questions] of Object.entries(bank)){
  questions.forEach((q,index)=>{
    const choices=Array.isArray(q[1])?q[1]:['錯誤','正確'];
    const correctIndex=Array.isArray(q[1])?q[2]:q[1];
    const explanation=Array.isArray(q[1])?q[3]:q[2];
    const id='q_'+crypto.createHash('sha256').update(`${unit}\n${q[0]}`).digest('hex').slice(0,24);
    rows.push({id,unit,order:index+1,text:q[0],choices,correctIndex,explanation});
  });
}
const esc=s=>String(s).replaceAll("'","''");
const values=rows.map(r=>`  ('${r.id}','${esc(r.unit)}',${r.order},'${esc(r.text)}','${esc(JSON.stringify(r.choices))}'::jsonb,${r.correctIndex},'${esc(r.explanation)}')`).join(',\n');
const sql=`begin;

create table if not exists public.question_catalog (
  id text primary key,
  unit_code text not null,
  question_order integer not null,
  question_text text not null,
  choices jsonb not null,
  correct_index integer not null,
  explanation text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(unit_code,question_text),
  constraint question_catalog_correct_index_check check (correct_index between 0 and 3)
);

alter table public.question_catalog enable row level security;
create policy "teachers read question catalog"
on public.question_catalog for select to authenticated using (public.is_teacher());
create policy "teachers manage question catalog"
on public.question_catalog for all to authenticated
using (public.is_teacher()) with check (public.is_teacher());

insert into public.question_catalog(id,unit_code,question_order,question_text,choices,correct_index,explanation)
values
${values}
on conflict(id) do update set
  unit_code=excluded.unit_code,
  question_order=excluded.question_order,
  question_text=excluded.question_text,
  choices=excluded.choices,
  correct_index=excluded.correct_index,
  explanation=excluded.explanation,
  active=true,
  updated_at=now();

create or replace function public.record_student_quiz(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  enrolled public.enrollments;
  answer_item jsonb;
  catalog_item public.question_catalog;
  attempt_uuid uuid;
  existing_attempt public.quiz_attempts;
  total_count int := jsonb_array_length(coalesce(payload->'answers','[]'::jsonb));
  correct_total int := 0;
  calculated_score int;
  source_key text;
  local_day date := (now() at time zone 'Asia/Taipei')::date;
  monday date := date_trunc('week',now() at time zone 'Asia/Taipei')::date;
  group_uuid uuid;
  daily_count int;
begin
  select * into enrolled from public.enrollments where user_id=auth.uid() and active limit 1;
  if enrolled.id is null then raise exception 'ENROLLMENT_REQUIRED'; end if;
  if total_count not in (5,10) then raise exception 'INVALID_QUESTION_COUNT'; end if;
  if nullif(payload->>'quizId','') is null then raise exception 'QUIZ_ID_REQUIRED'; end if;
  source_key := 'quiz:'||enrolled.id||':'||(payload->>'quizId');
  select * into existing_attempt from public.quiz_attempts where idempotency_key=source_key;
  if existing_attempt.id is not null then
    return jsonb_build_object('attemptId',existing_attempt.id,'score',existing_attempt.score,'duplicate',true);
  end if;

  insert into public.quiz_attempts(user_id,enrollment_id,unit_code,question_count,status,idempotency_key)
  values(auth.uid(),enrolled.id,left(payload->>'unit',200),total_count,'started',source_key)
  returning id into attempt_uuid;

  for answer_item in select value from jsonb_array_elements(payload->'answers') loop
    select * into catalog_item from public.question_catalog
    where active and unit_code=payload->>'unit' and question_text=answer_item->>'question' limit 1;
    if catalog_item.id is null then raise exception 'QUESTION_NOT_FOUND'; end if;
    if (answer_item->>'studentAnswerIndex')::int=catalog_item.correct_index then correct_total:=correct_total+1; end if;
    insert into public.quiz_answers(attempt_id,question_id,question_order,student_answer,correct_answer,is_correct,explanation)
    values(attempt_uuid,catalog_item.id,(answer_item->>'number')::int,
      jsonb_build_object('index',(answer_item->>'studentAnswerIndex')::int),
      jsonb_build_object('index',catalog_item.correct_index),
      (answer_item->>'studentAnswerIndex')::int=catalog_item.correct_index,
      catalog_item.explanation);
  end loop;
  calculated_score:=round(correct_total*100.0/total_count);
  update public.quiz_attempts set correct_count=correct_total,score=calculated_score,status='completed',completed_at=now()
  where id=attempt_uuid;

  select cga.group_id into group_uuid from public.class_group_assignments cga
  where cga.class_id=enrolled.class_id and cga.valid_to is null limit 1;
  insert into public.point_events(user_id,enrollment_id,term_id,class_id,group_id,event_type,points,rule_version,source_type,source_id,local_date,week_start,idempotency_key)
  values(auth.uid(),enrolled.id,enrolled.term_id,enrolled.class_id,group_uuid,'daily_first_learning',2,1,'quiz',attempt_uuid::text,local_day,monday,'daily:'||enrolled.id||':'||local_day)
  on conflict(idempotency_key) do nothing;
  select count(*) into daily_count from public.point_events where enrollment_id=enrolled.id and local_date=local_day and event_type='quiz_completed' and status='posted';
  if daily_count<3 then
    insert into public.point_events(user_id,enrollment_id,term_id,class_id,group_id,event_type,points,rule_version,source_type,source_id,local_date,week_start,idempotency_key)
    values(auth.uid(),enrolled.id,enrolled.term_id,enrolled.class_id,group_uuid,'quiz_completed',10,1,'quiz',attempt_uuid::text,local_day,monday,'quiz_points:'||attempt_uuid)
    on conflict(idempotency_key) do nothing;
  end if;
  for answer_item in select value from jsonb_array_elements(payload->'answers') loop
    select * into catalog_item from public.question_catalog where active and unit_code=payload->>'unit' and question_text=answer_item->>'question' limit 1;
    if (answer_item->>'studentAnswerIndex')::int=catalog_item.correct_index then
      insert into public.point_events(user_id,enrollment_id,term_id,class_id,group_id,event_type,points,rule_version,source_type,source_id,local_date,week_start,idempotency_key)
      values(auth.uid(),enrolled.id,enrolled.term_id,enrolled.class_id,group_uuid,'question_first_correct',2,1,'quiz_answer',catalog_item.id,local_day,monday,'correct:'||enrolled.id||':'||local_day||':'||catalog_item.id)
      on conflict(idempotency_key) do nothing;
    end if;
  end loop;
  return jsonb_build_object('attemptId',attempt_uuid,'score',calculated_score,'correctCount',correct_total,'duplicate',false);
end;
$$;

create or replace function public.record_student_consultation(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  enrolled public.enrollments;
  consultation_uuid uuid;
  existing_consultation public.consultations;
  source_key text;
  local_day date := (now() at time zone 'Asia/Taipei')::date;
  monday date := date_trunc('week',now() at time zone 'Asia/Taipei')::date;
  group_uuid uuid;
  daily_count int;
begin
  select * into enrolled from public.enrollments where user_id=auth.uid() and active limit 1;
  if enrolled.id is null then raise exception 'ENROLLMENT_REQUIRED'; end if;
  if length(trim(coalesce(payload->>'question','')))<3 or nullif(payload->>'consultId','') is null then raise exception 'INVALID_CONSULTATION'; end if;
  source_key:='consult:'||enrolled.id||':'||(payload->>'consultId');
  select * into existing_consultation from public.consultations where idempotency_key=source_key;
  if existing_consultation.id is not null then return jsonb_build_object('consultationId',existing_consultation.id,'duplicate',true); end if;
  insert into public.consultations(user_id,enrollment_id,topic,question,normalized_question_hash,answer,status,idempotency_key)
  values(auth.uid(),enrolled.id,left(coalesce(payload->>'topic','未分類'),200),payload->>'question',md5(lower(trim(payload->>'question'))),coalesce(payload->>'answer',''),'answered',source_key)
  returning id into consultation_uuid;
  select cga.group_id into group_uuid from public.class_group_assignments cga where cga.class_id=enrolled.class_id and cga.valid_to is null limit 1;
  insert into public.point_events(user_id,enrollment_id,term_id,class_id,group_id,event_type,points,rule_version,source_type,source_id,local_date,week_start,idempotency_key)
  values(auth.uid(),enrolled.id,enrolled.term_id,enrolled.class_id,group_uuid,'daily_first_learning',2,1,'consultation',consultation_uuid::text,local_day,monday,'daily:'||enrolled.id||':'||local_day)
  on conflict(idempotency_key) do nothing;
  select count(*) into daily_count from public.point_events where enrollment_id=enrolled.id and local_date=local_day and event_type='consultation_valid' and status='posted';
  if daily_count<5 then
    insert into public.point_events(user_id,enrollment_id,term_id,class_id,group_id,event_type,points,rule_version,source_type,source_id,local_date,week_start,idempotency_key)
    values(auth.uid(),enrolled.id,enrolled.term_id,enrolled.class_id,group_uuid,'consultation_valid',3,1,'consultation',consultation_uuid::text,local_day,monday,'consult_points:'||consultation_uuid)
    on conflict(idempotency_key) do nothing;
  end if;
  return jsonb_build_object('consultationId',consultation_uuid,'duplicate',false);
end;
$$;

create or replace function public.record_student_consultation_check(payload jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare enrolled public.enrollments; consultation_uuid uuid;
begin
  select * into enrolled from public.enrollments where user_id=auth.uid() and active limit 1;
  if enrolled.id is null then raise exception 'ENROLLMENT_REQUIRED'; end if;
  select id into consultation_uuid from public.consultations
  where enrollment_id=enrolled.id and idempotency_key='consult:'||enrolled.id||':'||(payload->>'consultId');
  if consultation_uuid is null then raise exception 'CONSULTATION_NOT_FOUND'; end if;
  insert into public.consultation_checks(consultation_id,question,choices,student_answer,correct_answer,is_correct,answered_at)
  values(consultation_uuid,payload->>'question',payload->'choices',(payload->>'studentChoice')::int,(payload->>'correctChoice')::int,(payload->>'studentChoice')::int=(payload->>'correctChoice')::int,now())
  on conflict(consultation_id) do update set student_answer=excluded.student_answer,is_correct=excluded.is_correct,answered_at=excluded.answered_at;
  return true;
end;
$$;

revoke all on function public.record_student_quiz(jsonb) from public;
revoke all on function public.record_student_consultation(jsonb) from public;
revoke all on function public.record_student_consultation_check(jsonb) from public;
grant execute on function public.record_student_quiz(jsonb) to authenticated;
grant execute on function public.record_student_consultation(jsonb) to authenticated;
grant execute on function public.record_student_consultation_check(jsonb) to authenticated;

commit;

select unit_code,count(*) as question_count from public.question_catalog where active group by unit_code order by unit_code;
`;
await fs.writeFile(new URL('../supabase/migrations/007_question_catalog_learning_sync.sql',import.meta.url),sql,'utf8');
console.log(JSON.stringify({units:Object.keys(bank).length,questions:rows.length}));
