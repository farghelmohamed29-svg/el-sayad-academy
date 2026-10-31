-- EL SAYAD ACADEMY: parent phone sync and admin new-student notifications
begin;
alter table public.profiles add column if not exists parent_phone text;
create or replace function public.link_parent_with_student_code(p_code text)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_student uuid; v_parent uuid:=auth.uid(); v_parent_phone text;
begin
 if v_parent is null then raise exception 'يجب تسجيل الدخول أولاً'; end if;
 select phone into v_parent_phone from public.profiles where id=v_parent and role='parent';
 if not found then raise exception 'هذا الحساب ليس حساب ولي أمر معتمد'; end if;
 select id into v_student from public.profiles where student_code=upper(btrim(p_code)) and role='student' for update;
 if v_student is null then raise exception 'كود الطالب غير صحيح'; end if;
 if exists(select 1 from public.parent_links where student_id=v_student) then raise exception 'تم ربط هذا الطالب بحساب ولي أمر بالفعل'; end if;
 insert into public.parent_links(parent_id,student_id) values(v_parent,v_student);
 update public.profiles set parent_linked_at=now(), parent_phone=v_parent_phone where id=v_student;
 return jsonb_build_object('linked',true,'parent_phone',v_parent_phone);
end $$;
create or replace function public.admin_list_recent_students()
returns table(student_id uuid,full_name text,phone text,student_code text,stage text,grade text,created_at timestamptz)
language plpgsql security definer set search_path=public
as $$
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then raise exception 'غير مصرح: هذه العملية للإدارة فقط'; end if;
 return query select p.id,p.full_name,p.phone,p.student_code,p.stage,p.grade,p.created_at
 from public.profiles p where p.role='student' order by p.created_at desc limit 100;
end $$;
revoke all on function public.admin_list_recent_students() from public;
grant execute on function public.admin_list_recent_students() to authenticated;
commit;