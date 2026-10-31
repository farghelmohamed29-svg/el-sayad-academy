-- EL SAYAD ACADEMY: manual WhatsApp verification for student phone registrations.
-- Run this file once in Supabase SQL Editor after taking a database backup.
begin;
create extension if not exists pgcrypto;

alter table public.profiles
  add column if not exists phone_verified boolean not null default true;

-- New student profiles should explicitly start unverified.
create or replace function public.set_new_student_unverified()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if new.role='student' then new.phone_verified := false; end if;
  return new;
end;
$$;
drop trigger if exists trg_set_new_student_unverified on public.profiles;
create trigger trg_set_new_student_unverified
before insert on public.profiles for each row
execute function public.set_new_student_unverified();

create table if not exists public.student_signup_codes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  code_digest text not null,
  expires_at timestamptz not null default (now()+interval '24 hours'),
  attempts integer not null default 0 check (attempts between 0 and 5),
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists student_signup_codes_student_idx
  on public.student_signup_codes(student_id,created_at desc);
alter table public.student_signup_codes enable row level security;
revoke all on public.student_signup_codes from anon, authenticated;

create or replace function public.admin_list_unverified_students()
returns table(student_id uuid, full_name text, phone text, grade text, created_at timestamptz)
language plpgsql security definer set search_path=public
as $$
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
    raise exception 'غير مصرح: هذه العملية للإدارة فقط';
  end if;
  return query select p.id,p.full_name,p.phone,p.grade,p.created_at
    from public.profiles p where p.role='student' and p.phone_verified=false
    order by p.created_at asc;
end;
$$;

create or replace function public.admin_issue_student_signup_code(p_student_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_code text; v_profile public.profiles%rowtype;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
    raise exception 'غير مصرح: هذه العملية للإدارة فقط';
  end if;
  select * into v_profile from public.profiles
    where id=p_student_id and role='student' and phone_verified=false for update;
  if not found then raise exception 'الطالب غير موجود أو تم تأكيده'; end if;
  v_code := lpad(floor(random()*1000000)::bigint::text,6,'0');
  insert into public.student_signup_codes(student_id,code_digest,expires_at)
    values(p_student_id,encode(digest(v_code,'sha256'),'hex'),now()+interval '24 hours');
  return jsonb_build_object('student_id',v_profile.id,'full_name',v_profile.full_name,
    'phone',v_profile.phone,'code',v_code,'expires_at',now()+interval '24 hours');
end;
$$;

create or replace function public.verify_student_signup_code(p_code text)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_id uuid:=auth.uid(); v_row public.student_signup_codes%rowtype;
begin
  if v_id is null then raise exception 'سجل الدخول أولاً'; end if;
  if not exists(select 1 from public.profiles where id=v_id and role='student') then
    raise exception 'الحساب ليس حساب طالب';
  end if;
  if exists(select 1 from public.profiles where id=v_id and phone_verified=true) then
    return jsonb_build_object('verified',true);
  end if;
  select * into v_row from public.student_signup_codes
    where student_id=v_id and used_at is null and expires_at>now() and attempts<5
    order by created_at desc limit 1 for update;
  if not found then raise exception 'لا يوجد كود صالح؛ اطلب كودًا جديدًا من الإدارة'; end if;
  if v_row.code_digest <> encode(digest(btrim(coalesce(p_code,'')),'sha256'),'hex') then
    update public.student_signup_codes set attempts=attempts+1 where id=v_row.id;
    raise exception 'كود التأكيد غير صحيح';
  end if;
  update public.student_signup_codes set used_at=now() where id=v_row.id;
  update public.profiles set phone_verified=true where id=v_id;
  return jsonb_build_object('verified',true);
end;
$$;

revoke all on function public.admin_list_unverified_students() from public;
revoke all on function public.admin_issue_student_signup_code(uuid) from public;
revoke all on function public.verify_student_signup_code(text) from public;
grant execute on function public.admin_list_unverified_students() to authenticated;
grant execute on function public.admin_issue_student_signup_code(uuid) to authenticated;
grant execute on function public.verify_student_signup_code(text) to authenticated;
commit;
