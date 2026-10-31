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
