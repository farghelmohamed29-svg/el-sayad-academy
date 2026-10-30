-- EL SAYAD ACADEMY: one-time student/parent code + subscription approvals
-- Apply this migration in Supabase SQL Editor. Do not run against production until reviewed/backed up.

create extension if not exists pgcrypto;

alter table public.profiles
  add column if not exists student_code text,
  add column if not exists parent_linked_at timestamptz;

create unique index if not exists profiles_student_code_unique
  on public.profiles(student_code) where student_code is not null;

-- Generate a unique code for every student profile, without exposing privileged credentials.
create or replace function public.make_student_code()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_code text;
begin
  if new.role='student' and (new.student_code is null or btrim(new.student_code)='') then
    loop
      v_code := upper(encode(gen_random_bytes(5),'hex'));
      exit when not exists(select 1 from public.profiles p where p.student_code=v_code);
    end loop;
    new.student_code := v_code;
  end if;
  return new;
end $$;

drop trigger if exists trg_make_student_code on public.profiles;
create trigger trg_make_student_code before insert on public.profiles
for each row execute function public.make_student_code();

-- Parent account must already exist and have role='parent' (provisioned by an administrator).
-- The student code can be redeemed only once; parent_links.student_id is unique.
create or replace function public.link_parent_with_student_code(p_code text)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_student uuid; v_parent uuid := auth.uid();
begin
  if v_parent is null then raise exception 'يجب تسجيل الدخول أولاً'; end if;
  if not exists(select 1 from public.profiles where id=v_parent and role='parent') then
    raise exception 'هذا الحساب ليس حساب ولي أمر معتمد';
  end if;
  select id into v_student from public.profiles
    where student_code=upper(btrim(p_code)) and role='student'
    for update;
  if v_student is null then raise exception 'كود الطالب غير صحيح'; end if;
  if exists(select 1 from public.parent_links where student_id=v_student) then
    raise exception 'تم استخدام كود هذا الطالب من قبل';
  end if;
  insert into public.parent_links(parent_id,student_id) values(v_parent,v_student);
  update public.profiles set parent_linked_at=now() where id=v_student;
  return jsonb_build_object('linked',true);
end $$;

revoke all on function public.link_parent_with_student_code(text) from public;
grant execute on function public.link_parent_with_student_code(text) to authenticated;

-- Approve payment and start a seven-day term. Admin role is checked inside the database.
create or replace function public.admin_approve_student_subscription(p_subscription_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_student uuid; v_end timestamptz;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
    raise exception 'غير مصرح: هذه العملية للإدارة فقط';
  end if;
  select student_id into v_student from public.academic_subscriptions
    where id=p_subscription_id and status='pending'
    for update;
  if v_student is null then raise exception 'طلب الاشتراك غير موجود أو تمت مراجعته'; end if;

  update public.academic_subscriptions
    set status='active', starts_at=now(), ends_at=now()+interval '7 days',
        reviewed_by=auth.uid(), reviewed_at=now()
    where id=p_subscription_id;
  select ends_at into v_end from public.academic_subscriptions where id=p_subscription_id;
  return jsonb_build_object('approved',true,'student_id',v_student,'ends_at',v_end);
end $$;

revoke all on function public.admin_approve_student_subscription(uuid) from public;
grant execute on function public.admin_approve_student_subscription(uuid) to authenticated;

-- Database-side status helper; all protected content queries must include this check.
create or replace function public.has_active_academy_subscription(p_student_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public
as $$
  select exists(
    select 1 from public.academic_subscriptions s
    where s.student_id=p_student_id and s.status='active'
      and s.starts_at<=now() and s.ends_at>now()
  )
$$;
revoke all on function public.has_active_academy_subscription(uuid) from public;
grant execute on function public.has_active_academy_subscription(uuid) to authenticated;

-- Expired rows are normalized when queried by admin; access must still be denied by ends_at.
update public.academic_subscriptions
set status='expired'
where status='active' and ends_at is not null and ends_at<=now();
