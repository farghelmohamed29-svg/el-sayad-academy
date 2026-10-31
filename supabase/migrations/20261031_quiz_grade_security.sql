-- Reapply grade-scoped quiz access after the main migration.
drop policy if exists quizzes_read on public.academic_quizzes;
create policy quizzes_read on public.academic_quizzes for select to authenticated
using(public.is_academy_admin() or (
 is_published and public.has_active_academy_subscription(auth.uid())
 and exists(select 1 from public.academic_lessons l
 join public.academic_units u on u.id=l.unit_id
 join public.academic_subjects s on s.id=u.subject_id
 join public.profiles p on p.id=auth.uid()
 where l.id=academic_quizzes.lesson_id and s.stage=p.stage and s.grade_code=p.grade and s.verification_status='verified')
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
