-- Server-side quiz grading. Students cannot write their own score.
drop policy if exists attempts_insert_own on public.academic_quiz_attempts;
create or replace function public.submit_academy_quiz(p_quiz_id uuid,p_answers jsonb)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare total_count integer; correct_count integer; new_id uuid;
begin
 if auth.uid() is null then raise exception 'سجل الدخول أولًا'; end if;
 if not public.has_active_academy_subscription(auth.uid()) then raise exception 'الاشتراك غير مفعل'; end if;
 if not exists(select 1 from public.academic_quizzes where id=p_quiz_id and is_published) then raise exception 'الامتحان غير متاح'; end if;
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
