-- EL SAYAD ACADEMY — قاعدة تأسيسية أولية لـ Supabase
-- راجعها واختبرها على مشروع تجريبي قبل تطبيقها على بيانات حقيقية.
-- لا يحتوي الملف على service_role ولا ينشئ حسابات أو كلمات مرور.

create extension if not exists pgcrypto;

-- الملف الشخصي: يفترض وجود profiles(id uuid primary key references auth.users(id), role text).
alter table public.profiles
  add column if not exists full_name text,
  add column if not exists phone text,
  add column if not exists school_stage text,
  add column if not exists school_grade text,
  add column if not exists school_system text,
  add column if not exists baccalaureate_track text,
  add column if not exists academic_selection_locked_at timestamptz;

create table if not exists public.academic_subjects (
  id uuid primary key default gen_random_uuid(),
  stage text not null check (stage in ('primary','preparatory','secondary')),
  grade_code text not null,
  school_system text not null default 'all' check (school_system in ('all','general','baccalaureate')),
  subject_name text not null,
  academic_year text not null,
  official_source_url text,
  verification_status text not null default 'needs_review' check (verification_status in ('needs_review','verified','retired')),
  verified_at timestamptz,
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
  lesson_type text not null default 'theory' check (lesson_type in ('theory','practical','review')),
  explanation text,
  video_path text,
  model_3d_url text,
  practical_summary text,
  sort_order int not null default 0,
  is_published boolean not null default false
);

create table if not exists public.academic_quizzes (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid references public.academic_lessons(id) on delete cascade,
  title text not null,
  quiz_type text not null default 'lesson' check (quiz_type in ('lesson','unit','comprehensive')),
  is_published boolean not null default false
);

create table if not exists public.academic_questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.academic_quizzes(id) on delete cascade,
  question_text text not null,
  options jsonb not null default '[]'::jsonb,
  sort_order int not null default 0
);

-- مفاتيح الإجابات لا تُعرض على العميل.
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
  status text not null default 'pending' check (status in ('pending','active','expired','rejected')),
  starts_at timestamptz,
  ends_at timestamptz,
  payment_method text check (payment_method in ('cash','vodafone_cash')),
  receipt_path text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create or replace function public.is_academy_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') $$;

-- لا يسمح للطالب بتغيير اختياره الأكاديمي بعد أول تثبيت؛ المسؤول فقط يستطيع التعديل.
create or replace function public.guard_academic_selection()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is not null and auth.uid() = new.id and not public.is_academy_admin() then
    if old.academic_selection_locked_at is not null and
       (new.school_stage is distinct from old.school_stage or
        new.school_grade is distinct from old.school_grade or
        new.school_system is distinct from old.school_system or
        new.baccalaureate_track is distinct from old.baccalaureate_track) then
      raise exception 'تم تثبيت المرحلة والصف. تواصل مع الإدارة لأي تعديل.';
    end if;
    if old.academic_selection_locked_at is null and
       (new.school_stage is not null or new.school_grade is not null) then
      new.academic_selection_locked_at := now();
    end if;
    -- لا تسمح بتغيير الدور أو حالة الإدارة عبر تحديث الملف الشخصي.
    if new.role is distinct from old.role then
      raise exception 'لا يمكن تغيير صلاحية الحساب من ملف الطالب.';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_academic_selection on public.profiles;
create trigger trg_guard_academic_selection before update on public.profiles
for each row execute function public.guard_academic_selection();

alter table public.academic_subjects enable row level security;
alter table public.academic_units enable row level security;
alter table public.academic_lessons enable row level security;
alter table public.academic_quizzes enable row level security;
alter table public.academic_questions enable row level security;
alter table public.academic_answer_keys enable row level security;
alter table public.academic_quiz_attempts enable row level security;
alter table public.academic_subscriptions enable row level security;

-- القراءة العامة للمواد المنشورة المعتمدة فقط لا تتم هنا؛ تتطلب وجود مستخدم مسجل.
 drop policy if exists subjects_read_verified on public.academic_subjects;
create policy subjects_read_verified on public.academic_subjects for select to authenticated
using (verification_status='verified' or public.is_academy_admin());
drop policy if exists subjects_admin_all on public.academic_subjects;
create policy subjects_admin_all on public.academic_subjects for all to authenticated
using (public.is_academy_admin()) with check (public.is_academy_admin());

drop policy if exists units_read on public.academic_units;
create policy units_read on public.academic_units for select to authenticated using (
  public.is_academy_admin() or exists(select 1 from public.academic_subjects s where s.id=subject_id and s.verification_status='verified')
);
drop policy if exists units_admin on public.academic_units;
create policy units_admin on public.academic_units for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());

drop policy if exists lessons_read on public.academic_lessons;
create policy lessons_read on public.academic_lessons for select to authenticated using (
  public.is_academy_admin() or (is_published and exists(select 1 from public.academic_units u join public.academic_subjects s on s.id=u.subject_id where u.id=unit_id and s.verification_status='verified'))
);
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
-- لا توجد سياسة SELECT للطالب على مفاتيح الإجابة.
drop policy if exists answer_keys_admin on public.academic_answer_keys;
create policy answer_keys_admin on public.academic_answer_keys for all to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());

drop policy if exists attempts_student_read on public.academic_quiz_attempts;
create policy attempts_student_read on public.academic_quiz_attempts for select to authenticated using(student_id=auth.uid() or public.is_academy_admin());
drop policy if exists attempts_student_insert on public.academic_quiz_attempts;
create policy attempts_student_insert on public.academic_quiz_attempts for insert to authenticated with check(student_id=auth.uid());
drop policy if exists attempts_admin_update on public.academic_quiz_attempts;
create policy attempts_admin_update on public.academic_quiz_attempts for update to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());

drop policy if exists subscriptions_read_own on public.academic_subscriptions;
create policy subscriptions_read_own on public.academic_subscriptions for select to authenticated using(student_id=auth.uid() or public.is_academy_admin());
drop policy if exists subscriptions_insert_own on public.academic_subscriptions;
create policy subscriptions_insert_own on public.academic_subscriptions for insert to authenticated with check(student_id=auth.uid() and status='pending');
drop policy if exists subscriptions_admin_update on public.academic_subscriptions;
create policy subscriptions_admin_update on public.academic_subscriptions for update to authenticated using(public.is_academy_admin()) with check(public.is_academy_admin());

-- تنبيه: هذه سياسات تأسيسية وليست نظام امتحانات/اشتراكات جاهزًا للإنتاج.
-- يجب إضافة تحقق خادمي من صلاحية الاشتراك قبل تسليم الفيديوهات، وربط Storage policies،
-- وإتمام إجراء آمن لتصحيح الامتحانات دون كشف answer keys، ثم اختبار كل سياسة بحساب طالب وولي أمر وإدارة.
