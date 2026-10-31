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
