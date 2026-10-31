-- EL SAYAD ACADEMY: subscription request fields used by the student/admin dashboard
begin;
alter table public.academic_subscriptions
  add column if not exists amount numeric(10,2),
  add column if not exists grade text;
create index if not exists academic_subscriptions_pending_idx
  on public.academic_subscriptions(status,created_at)
  where status='pending';
commit;
