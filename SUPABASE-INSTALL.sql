-- EL SAYAD ACADEMY — consolidated installation script
-- Run once in Supabase SQL Editor after taking a backup.
-- Phone auth must be enabled; turn OFF phone confirmation because activation is handled by academy-issued codes.

-- ===== supabase/migrations/20261031_full_academy.sql =====
-- EL SAYAD ACADEMY: full portal migration
-- Run in Supabase SQL Editor AFTER reviewing and backing up the project.
-- Requires Supabase Auth phone provider enabled. For the academy's WhatsApp-issued
-- activation codes, disable Supabase phone OTP confirmation; the app performs its
-- own one-time activation-code check after the admin confirms payment.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'student',
  full_name text,
  phone text,
  stage text,
  grade text,
  secondary_system text,
  student_code text,
  phone_verified boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.profiles add column if not exists role text not null default 'student';
alter table public.profiles add column if not exists full_name text;
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists stage text;
alter table public.profiles add column if not exists grade text;
alter table public.profiles add column if not exists secondary_system text;
alter table public.profiles add column if not exists student_code text;
alter table public.profiles add column if not exists phone_verified boolean not null default false;
alter table public.profiles add column if not exists created_at timestamptz not null default now();
create unique index if not exists profiles_student_code_uq on public.profiles(student_code) where student_code is not null;
create index if not exists profiles_phone_idx on public.profiles(phone);

create table if not exists public.parent_links (
  parent_id uuid not null references public.profiles(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(parent_id,student_id),
  check(parent_id <> student_id)
);
create table if not exists public.student_activation_codes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  code_hash bytea not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists student_activation_codes_student_idx on public.student_activation_codes(student_id);

create table if not exists public.academic_subjects (
  id uuid primary key default gen_random_uuid(),
  stage text not null check(stage in ('primary','preparatory','secondary')),
  grade_code text not null,
  school_system text not null default 'all',
  subject_name text not null,
  academic_year text not null default '2026-2027',
  official_source_url text,
  verification_status text not null default 'needs_review',
  created_at timestamptz not null default now(),
  unique(stage,grade_code,school_system,subject_name,academic_year)
);
create table if not exists public.academic_units (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.academic_subjects(id) on delete cascade,
  title text not null,
  sort_order int not null default 0
);
create table if not exists public.academic_lessons (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.academic_units(id) on delete cascade,
  title text not null,
  lesson_type text not null default 'theory',
  explanation text,
  video_path text,
  model_3d_url text,
  practical_summary text,
  sort_order int not null default 0,
  is_published boolean not null default false
);
create table if not exists public.academic_quizzes (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid references public.academic_lessons(id) on delete set null,
  title text not null,
  quiz_type text not null default 'lesson',
  is_published boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.academic_questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.academic_quizzes(id) on delete cascade,
  question_text text not null,
  options jsonb not null default '[]'::jsonb,
  sort_order int not null default 0
);
create table if not exists public.academic_answer_keys (
  question_id uuid primary key references public.academic_questions(id) on delete cascade,
  correct_value jsonb not null,
  explanation text
);
create table if not exists public.academic_quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  quiz_id uuid not null references public.academic_quizzes(id) on delete cascade,
  answers jsonb not null default '{}'::jsonb,
  score numeric,
  submitted_at timestamptz not null default now()
);
create table if not exists public.academic_subscriptions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','active','expired','rejected')),
  starts_at timestamptz,
  ends_at timestamptz,
  payment_method text,
  receipt_path text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  grade text,
  amount numeric(10,2),
  created_at timestamptz not null default now()
);
alter table public.academic_subscriptions add column if not exists grade text;
alter table public.academic_subscriptions add column if not exists amount numeric(10,2);
create table if not exists public.academic_attendance (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  lesson_id uuid references public.academic_lessons(id) on delete set null,
  attendance_date date not null default current_date,
  status text not null check(status in ('present','absent','late','excused')),
  notes text,
  marked_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create table if not exists public.academic_lesson_progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  lesson_id uuid not null references public.academic_lessons(id) on delete cascade,
  status text not null default 'started' check(status in ('started','completed')),
  watched_seconds integer not null default 0,
  updated_at timestamptz not null default now(),
  unique(student_id,lesson_id)
);
create table if not exists public.academic_weekly_reports (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  week_start date not null,
  summary text not null,
  strengths text,
  improvement_areas text,
  evaluation text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(student_id,week_start)
);

create or replace function public.is_academy_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin') $$;
create or replace function public.is_parent_of(target_student uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.parent_links where parent_id=auth.uid() and student_id=target_student) $$;
create or replace function public.has_active_academy_subscription(p_student_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.academic_subscriptions where student_id=p_student_id and status='active' and ends_at>now()) $$;

-- Safe profile creation. Client metadata can select student/parent, never admin.
create or replace function public.el_sayad_create_profile()
returns trigger language plpgsql security definer set search_path=public
as $$
declare wanted_role text;
begin
  wanted_role := case when new.raw_user_meta_data->>'role'='parent' then 'parent' else 'student' end;
  insert into public.profiles(id,role,full_name,phone,stage,grade,secondary_system)
  values(new.id,wanted_role,new.raw_user_meta_data->>'full_name',coalesce(new.phone,new.raw_user_meta_data->>'phone'),
    new.raw_user_meta_data->>'stage',new.raw_user_meta_data->>'grade',new.raw_user_meta_data->>'secondary_system')
  on conflict(id) do update set
    full_name=coalesce(excluded.full_name,profiles.full_name),
    phone=coalesce(excluded.phone,profiles.phone),
    stage=coalesce(excluded.stage,profiles.stage),
    grade=coalesce(excluded.grade,profiles.grade),
    secondary_system=coalesce(excluded.secondary_system,profiles.secondary_system),
    role=case when profiles.role='admin' then 'admin' else excluded.role end;
  return new;
end $$;
drop trigger if exists el_sayad_auth_profile on auth.users;
create trigger el_sayad_auth_profile after insert on auth.users
for each row execute function public.el_sayad_create_profile();

create or replace function public.admin_approve_student_subscription(p_subscription_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare subrow public.academic_subscriptions; p public.profiles; raw_code text;
begin
  if not public.is_academy_admin() then raise exception 'غير مصرح'; end if;
  select * into subrow from public.academic_subscriptions where id=p_subscription_id for update;
  if not found then raise exception 'طلب الاشتراك غير موجود'; end if;
  update public.academic_subscriptions set status='active',starts_at=now(),ends_at=now()+interval '7 days',
    reviewed_by=auth.uid(),reviewed_at=now() where id=p_subscription_id;
  select * into p from public.profiles where id=subrow.student_id for update;
  raw_code := upper(encode(gen_random_bytes(3),'hex'));
  insert into public.student_activation_codes(student_id,code_hash,expires_at,created_by)
  values(p.id,digest(raw_code,'sha256'),now()+interval '48 hours',auth.uid());
  return jsonb_build_object('code',raw_code,'phone',p.phone,'full_name',p.full_name,'student_id',p.id);
end $$;

create or replace function public.verify_student_signup_code(p_code text)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare c public.student_activation_codes; p public.profiles; student_code_value text;
begin
  select * into c from public.student_activation_codes
  where student_id=auth.uid() and code_hash=digest(upper(trim(p_code)),'sha256')
    and used_at is null and expires_at>now()
  order by created_at desc limit 1 for update;
  if not found then raise exception 'الكود غير صحيح أو انتهت صلاحيته'; end if;
  student_code_value := 'SAYAD-'||upper(encode(gen_random_bytes(4),'hex'));
  update public.student_activation_codes set used_at=now() where id=c.id;
  update public.profiles set phone_verified=true,student_code=coalesce(student_code,student_code_value) where id=auth.uid();
  select * into p from public.profiles where id=auth.uid();
  return jsonb_build_object('verified',true,'student_code',p.student_code);
end $$;

create or replace function public.link_parent_with_student_code(p_code text)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare sid uuid;
begin
  if auth.uid() is null then raise exception 'سجل الدخول أولًا'; end if;
  update public.profiles set role='parent' where id=auth.uid() and role in ('student','parent');
  select id into sid from public.profiles where student_code=upper(trim(p_code)) and role='student';
  if sid is null then raise exception 'كود الطالب غير صحيح'; end if;
  insert into public.parent_links(parent_id,student_id) values(auth.uid(),sid) on conflict do nothing;
  return jsonb_build_object('message','تم ربط الطالب بنجاح');
end $$;

-- Existing admin_list_recent_students() already has the required seven-column return type; keep it unchanged.


-- RLS policies
alter table public.profiles enable row level security;
alter table public.parent_links enable row level security;
alter table public.student_activation_codes enable row level security;
alter table public.academic_subjects enable row level security;
alter table public.academic_units enable row level security;
alter table public.academic_lessons enable row level security;
alter table public.academic_quizzes enable row level security;
alter table public.academic_questions enable row level security;
alter table public.academic_answer_keys enable row level security;
alter table public.academic_quiz_attempts enable row level security;
alter table public.academic_subscriptions enable row level security;
alter table public.academic_attendance enable row level security;
alter table public.academic_lesson_progress enable row level security;
alter table public.academic_weekly_reports enable row level security;

drop policy if exists profiles_read_self_parent_admin on public.profiles;
create policy profiles_read_self_parent_admin on public.profiles for select to authenticated
using(id=auth.uid() or public.is_academy_admin() or public.is_parent_of(id));
drop policy if exists profiles_update_self_safe on public.profiles;
create policy profiles_update_self_safe on public.profiles for update to authenticated
using(id=auth.uid() or public.is_academy_admin()) with check(id=auth.uid() or public.is_academy_admin());
drop policy if exists profiles_admin_all on public.profiles;
create policy profiles_admin_all on public.profiles for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());

drop policy if exists parent_links_read on public.parent_links;
create policy parent_links_read on public.parent_links for select to authenticated using(parent_id=auth.uid() or public.is_academy_admin());
drop policy if exists parent_links_admin on public.parent_links;
create policy parent_links_admin on public.parent_links for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());
drop policy if exists activation_codes_admin on public.student_activation_codes;
create policy activation_codes_admin on public.student_activation_codes for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());

drop policy if exists subjects_read on public.academic_subjects;
create policy subjects_read on public.academic_subjects for select to authenticated using(public.is_academy_admin() or (verification_status='verified' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.stage=stage and p.grade=grade_code)));
drop policy if exists subjects_admin on public.academic_subjects;
create policy subjects_admin on public.academic_subjects for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());
drop policy if exists units_read on public.academic_units;
create policy units_read on public.academic_units for select to authenticated using(public.is_academy_admin() or exists(select 1 from public.academic_subjects s where s.id=subject_id and s.verification_status='verified'));
drop policy if exists units_admin on public.academic_units;
create policy units_admin on public.academic_units for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());
drop policy if exists lessons_read on public.academic_lessons;
create policy lessons_read on public.academic_lessons for select to authenticated using(public.is_academy_admin() or (is_published and exists(select 1 from public.academic_units u join public.academic_subjects s on s.id=u.subject_id where u.id=unit_id and s.verification_status='verified')));
drop policy if exists lessons_admin on public.academic_lessons;
create policy lessons_admin on public.academic_lessons for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());
drop policy if exists quizzes_read on public.academic_quizzes;
create policy quizzes_read on public.academic_quizzes for select to authenticated using(public.is_academy_admin() or is_published);
drop policy if exists quizzes_admin on public.academic_quizzes;
create policy quizzes_admin on public.academic_quizzes for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());
drop policy if exists questions_read on public.academic_questions;
create policy questions_read on public.academic_questions for select to authenticated using(public.is_academy_admin() or exists(select 1 from public.academic_quizzes q where q.id=quiz_id and q.is_published));
drop policy if exists questions_admin on public.academic_questions;
create policy questions_admin on public.academic_questions for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());
drop policy if exists answer_keys_admin on public.academic_answer_keys;
create policy answer_keys_admin on public.academic_answer_keys for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());

drop policy if exists attempts_read_own_parent_admin on public.academic_quiz_attempts;
create policy attempts_read_own_parent_admin on public.academic_quiz_attempts for select to authenticated using(student_id=auth.uid() or public.is_parent_of(student_id) or public.is_academy_admin());
drop policy if exists attempts_insert_own on public.academic_quiz_attempts;
create policy attempts_insert_own on public.academic_quiz_attempts for insert to authenticated with check(student_id=auth.uid() and public.has_active_academy_subscription(student_id));
drop policy if exists attempts_admin_update on public.academic_quiz_attempts;
create policy attempts_admin_update on public.academic_quiz_attempts for update to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());

drop policy if exists subscriptions_read_own_parent_admin on public.academic_subscriptions;
create policy subscriptions_read_own_parent_admin on public.academic_subscriptions for select to authenticated using(student_id=auth.uid() or public.is_parent_of(student_id) or public.is_academy_admin());
drop policy if exists subscriptions_insert_own_pending on public.academic_subscriptions;
create policy subscriptions_insert_own_pending on public.academic_subscriptions for insert to authenticated with check(student_id=auth.uid() and status='pending');
drop policy if exists subscriptions_admin_update on public.academic_subscriptions;
create policy subscriptions_admin_update on public.academic_subscriptions for update to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());

drop policy if exists attendance_read_parent_student_admin on public.academic_attendance;
create policy attendance_read_parent_student_admin on public.academic_attendance for select to authenticated using(student_id=auth.uid() or public.is_parent_of(student_id) or public.is_academy_admin());
drop policy if exists attendance_admin_all on public.academic_attendance;
create policy attendance_admin_all on public.academic_attendance for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());
drop policy if exists progress_read_parent_student_admin on public.academic_lesson_progress;
create policy progress_read_parent_student_admin on public.academic_lesson_progress for select to authenticated using(student_id=auth.uid() or public.is_parent_of(student_id) or public.is_academy_admin());
drop policy if exists progress_insert_own on public.academic_lesson_progress;
create policy progress_insert_own on public.academic_lesson_progress for insert to authenticated with check(student_id=auth.uid() and public.has_active_academy_subscription(student_id));
drop policy if exists progress_update_own on public.academic_lesson_progress;
create policy progress_update_own on public.academic_lesson_progress for update to authenticated using(student_id=auth.uid() and public.has_active_academy_subscription(student_id)) with check(student_id=auth.uid());
drop policy if exists progress_admin_all on public.academic_lesson_progress;
create policy progress_admin_all on public.academic_lesson_progress for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());

drop policy if exists reports_read_parent_admin on public.academic_weekly_reports;
create policy reports_read_parent_admin on public.academic_weekly_reports for select to authenticated using(public.is_parent_of(student_id) or public.is_academy_admin() or student_id=auth.uid());
drop policy if exists reports_admin_all on public.academic_weekly_reports;
create policy reports_admin_all on public.academic_weekly_reports for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());

grant execute on function public.admin_approve_student_subscription(uuid) to authenticated;
grant execute on function public.verify_student_signup_code(text) to authenticated;
grant execute on function public.link_parent_with_student_code(text) to authenticated;
grant execute on function public.admin_list_recent_students() to authenticated;

-- IMPORTANT: Create the first admin account in Supabase Auth, then set its profile role
-- to admin manually from the SQL editor. Never expose the service_role key in browser code.


-- ===== supabase/migrations/20261031_admin_security.sql =====
-- Security and admin RPC completion for EL SAYAD ACADEMY
create or replace function public.guard_academy_profile_changes()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is not null and auth.uid()=old.id and not public.is_academy_admin() then
    if new.role is distinct from old.role
      or new.phone_verified is distinct from old.phone_verified
      or new.student_code is distinct from old.student_code then
      raise exception 'هذه البيانات لا يمكن تعديلها من الحساب الشخصي';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_guard_academy_profile_changes on public.profiles;
create trigger trg_guard_academy_profile_changes before update on public.profiles
for each row execute function public.guard_academy_profile_changes();

create or replace function public.admin_list_unverified_students()
returns table(student_id uuid,full_name text,phone text,grade text,created_at timestamptz)
language sql security definer set search_path=public
as $$
 select p.id,p.full_name,p.phone,p.grade,p.created_at
 from public.profiles p
 where public.is_academy_admin() and p.role='student' and not p.phone_verified
 order by p.created_at desc limit 100
$$;

create or replace function public.admin_issue_student_signup_code(p_student_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare raw_code text; p public.profiles;
begin
 if not public.is_academy_admin() then raise exception 'غير مصرح'; end if;
 select * into p from public.profiles where id=p_student_id and role='student' for update;
 if not found then raise exception 'الطالب غير موجود'; end if;
 raw_code:=lpad((floor(random()*1000000))::int::text,6,'0');
 insert into public.student_activation_codes(student_id,code_hash,expires_at,created_by)
 values(p_student_id,digest(raw_code,'sha256'),now()+interval '24 hours',auth.uid());
 return jsonb_build_object('code',raw_code,'phone',p.phone,'full_name',p.full_name);
end $$;

grant execute on function public.admin_list_unverified_students() to authenticated;
grant execute on function public.admin_issue_student_signup_code(uuid) to authenticated;

-- Parents may only link a student after signing in with a parent account.
create or replace function public.link_parent_with_student_code(p_code text)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare sid uuid;
begin
 if auth.uid() is null then raise exception 'سجل الدخول أولًا'; end if;
 if not exists(select 1 from public.profiles where id=auth.uid() and role='parent') then
   raise exception 'يجب استخدام حساب ولي الأمر';
 end if;
 select id into sid from public.profiles where student_code=upper(trim(p_code)) and role='student' and phone_verified;
 if sid is null then raise exception 'كود الطالب غير صحيح أو لم يتم تفعيله'; end if;
 insert into public.parent_links(parent_id,student_id) values(auth.uid(),sid) on conflict do nothing;
 return jsonb_build_object('message','تم ربط الطالب بنجاح');
end $$;
grant execute on function public.link_parent_with_student_code(text) to authenticated;


-- ===== supabase/migrations/20261031_subscription_access.sql =====
-- Enforce subscription access and lock student academic selection.
create or replace function public.guard_academy_profile_changes()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 if auth.uid() is not null and auth.uid()=old.id and not public.is_academy_admin() then
   if new.role is distinct from old.role
     or new.phone_verified is distinct from old.phone_verified
     or new.student_code is distinct from old.student_code then
     raise exception 'هذه البيانات لا يمكن تعديلها من الحساب الشخصي';
   end if;
   if old.stage is not null and
     (new.stage is distinct from old.stage or new.grade is distinct from old.grade or new.secondary_system is distinct from old.secondary_system) then
     raise exception 'تم تثبيت المرحلة والصف. تواصل مع الإدارة للتعديل.';
   end if;
 end if;
 return new;
end $$;

drop policy if exists subjects_read on public.academic_subjects;
create policy subjects_read on public.academic_subjects for select to authenticated
using(public.is_academy_admin() or (
 verification_status='verified'
 and exists(select 1 from public.profiles p where p.id=auth.uid() and p.stage=academic_subjects.stage and p.grade=academic_subjects.grade_code)
 and public.has_active_academy_subscription(auth.uid())
));

drop policy if exists lessons_read on public.academic_lessons;
create policy lessons_read on public.academic_lessons for select to authenticated
using(public.is_academy_admin() or (
 is_published
 and exists(select 1 from public.academic_units u join public.academic_subjects s on s.id=u.subject_id
   where u.id=academic_lessons.unit_id and s.verification_status='verified'
   and s.stage=(select p.stage from public.profiles p where p.id=auth.uid())
   and s.grade_code=(select p.grade from public.profiles p where p.id=auth.uid()))
 and public.has_active_academy_subscription(auth.uid())
));

drop policy if exists quizzes_read on public.academic_quizzes;
create policy quizzes_read on public.academic_quizzes for select to authenticated
using(public.is_academy_admin() or (is_published and public.has_active_academy_subscription(auth.uid())));
drop policy if exists questions_read on public.academic_questions;
create policy questions_read on public.academic_questions for select to authenticated
using(public.is_academy_admin() or (
 exists(select 1 from public.academic_quizzes q where q.id=academic_questions.quiz_id and q.is_published)
 and public.has_active_academy_subscription(auth.uid())
));


-- ===== supabase/migrations/20261031_secure_quiz_grading.sql =====
-- Server-side quiz grading. Students cannot write their own score.
drop policy if exists attempts_insert_own on public.academic_quiz_attempts;
create or replace function public.submit_academy_quiz(p_quiz_id uuid,p_answers jsonb)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare total_count integer; correct_count integer; new_id uuid;
begin
 if auth.uid() is null then raise exception 'سجل الدخول أولًا'; end if;
 if not public.has_active_academy_subscription(auth.uid()) then raise exception 'الاشتراك غير مفعل'; end if;
 if not exists(
   select 1 from public.academic_quizzes q
   join public.academic_lessons l on l.id=q.lesson_id
   join public.academic_units u on u.id=l.unit_id
   join public.academic_subjects s on s.id=u.subject_id
   join public.profiles p on p.id=auth.uid()
   where q.id=p_quiz_id and q.is_published
     and p.role='student' and p.phone_verified
     and s.stage=p.stage and s.grade_code=p.grade
     and s.verification_status='verified'
 ) then raise exception 'الامتحان غير متاح لهذا الحساب أو الصف'; end if;
 select count(*) into total_count from public.academic_questions where quiz_id=p_quiz_id;
 if total_count=0 then raise exception 'لا توجد أسئلة في الامتحان'; end if;
 select count(*) into correct_count
 from public.academic_questions q
 join public.academic_answer_keys k on k.question_id=q.id
 where q.quiz_id=p_quiz_id and p_answers->>q.id::text is not null
   and (p_answers->q.id::text)=k.correct_value;
 insert into public.academic_quiz_attempts(student_id,quiz_id,answers,score)
 values(auth.uid(),p_quiz_id,coalesce(p_answers,'{}'::jsonb),round((correct_count::numeric/total_count)*100,2))
 returning id into new_id;
 return jsonb_build_object('attempt_id',new_id,'score',round((correct_count::numeric/total_count)*100,2),'correct',correct_count,'total',total_count);
end $$;
grant execute on function public.submit_academy_quiz(uuid,jsonb) to authenticated;


-- ===== supabase/migrations/20261031_admin_bootstrap_and_quiz_scope.sql =====
-- Bootstrap the named academy admin and scope quizzes to the learner's grade.
update public.profiles p set role='admin'
where p.id in (select u.id from auth.users u where lower(u.email)=lower('modyfarghel200@gmail.com'));

create or replace function public.el_sayad_create_profile()
returns trigger language plpgsql security definer set search_path=public
as $$
declare wanted_role text;
begin
 wanted_role := case
   when lower(coalesce(new.email,''))=lower('modyfarghel200@gmail.com') then 'admin'
   when new.raw_user_meta_data->>'role'='parent' then 'parent'
   else 'student'
 end;
 insert into public.profiles(id,role,full_name,phone,stage,grade,secondary_system)
 values(new.id,wanted_role,new.raw_user_meta_data->>'full_name',coalesce(new.phone,new.raw_user_meta_data->>'phone'),
   new.raw_user_meta_data->>'stage',new.raw_user_meta_data->>'grade',new.raw_user_meta_data->>'secondary_system')
 on conflict(id) do update set
   full_name=coalesce(excluded.full_name,profiles.full_name),
   phone=coalesce(excluded.phone,profiles.phone),
   stage=coalesce(excluded.stage,profiles.stage),
   grade=coalesce(excluded.grade,profiles.grade),
   secondary_system=coalesce(excluded.secondary_system,profiles.secondary_system),
   role=case when lower(coalesce(new.email,''))=lower('modyfarghel200@gmail.com') then 'admin'
     when profiles.role='admin' then 'admin' else excluded.role end;
 return new;
end $$;

drop policy if exists quizzes_read on public.academic_quizzes;
create policy quizzes_read on public.academic_quizzes for select to authenticated
using(public.is_academy_admin() or (
 is_published and public.has_active_academy_subscription(auth.uid())
 and exists(select 1 from public.academic_lessons l
   join public.academic_units u on u.id=l.unit_id
   join public.academic_subjects s on s.id=u.subject_id
   join public.profiles p on p.id=auth.uid()
   where l.id=academic_quizzes.lesson_id and s.stage=p.stage and s.grade_code=p.grade
     and s.verification_status='verified')
));
drop policy if exists questions_read on public.academic_questions;
create policy questions_read on public.academic_questions for select to authenticated
using(public.is_academy_admin() or (
 public.has_active_academy_subscription(auth.uid())
 and exists(select 1 from public.academic_quizzes q
   join public.academic_lessons l on l.id=q.lesson_id
   join public.academic_units u on u.id=l.unit_id
   join public.academic_subjects s on s.id=u.subject_id
   join public.profiles p on p.id=auth.uid()
   where q.id=academic_questions.quiz_id and q.is_published
     and s.stage=p.stage and s.grade_code=p.grade and s.verification_status='verified')
));
