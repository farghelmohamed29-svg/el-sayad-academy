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
returns text language plpgsql security definer set search_path=public
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
 return 'تم ربط الطالب بنجاح';
end $$;
grant execute on function public.link_parent_with_student_code(text) to authenticated;
