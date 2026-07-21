-- ============================================================
-- ميزة طلب تبديل نوبة بين فردين
-- نفّذ هذا الملف كامل بمحرر SQL بسوبابيس (SQL Editor)
-- ملاحظة: هاي طلبات منفصلة تمامًا عن طلبات العذر/المرض —
-- الموافقة عليها لا تغيّر حالة الحضور تلقائيًا (القائد هو يلي
-- بيرتب التغطية الفعلية بعد الموافقة).
-- ============================================================

create table if not exists swap_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references members(id) on delete cascade,
  partner_id uuid not null references members(id) on delete cascade,
  swap_date date not null,
  note text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
alter table swap_requests enable row level security;

drop policy if exists "authenticated can manage swap_requests" on swap_requests;
create policy "authenticated can manage swap_requests" on swap_requests
  for all to authenticated using (true) with check (true);
-- بدون أي policy لـ anon — الوصول فقط عبر الدوال الآمنة تحت

-- 1) بحث عن فرد بالاسم (للاختيار كشريك تبديل) — بدون كشف الرمز السري
create or replace function search_members_public(p_query text)
returns table(id uuid, name text, unit_name text, platoon_name text, squad_name text)
language sql
security definer
set search_path = public
as $$
  select m.id, m.name, u.name, p.name, s.name
  from members m
  join units u on u.id = m.unit_id
  left join squads s on s.id = m.squad_id
  left join platoons p on p.id = s.platoon_id
  where m.name ilike '%' || p_query || '%'
  order by m.name
  limit 10;
$$;
grant execute on function search_members_public(text) to anon;

-- 2) تقديم طلب تبديل نوبة (بعد التحقق من هوية مقدّم الطلب)
create or replace function submit_swap_request(p_member_id uuid, p_pin text, p_partner_id uuid, p_date date, p_note text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_valid boolean;
begin
  select exists(select 1 from members where id = p_member_id and pin = p_pin) into v_valid;
  if not v_valid then
    raise exception 'invalid_credentials';
  end if;
  if p_partner_id = p_member_id then
    raise exception 'cannot_swap_with_self';
  end if;
  if not exists(select 1 from members where id = p_partner_id) then
    raise exception 'invalid_partner';
  end if;

  insert into swap_requests (requester_id, partner_id, swap_date, note, status)
    values (p_member_id, p_partner_id, p_date, p_note, 'pending');
  return true;
end;
$$;
grant execute on function submit_swap_request(uuid, text, uuid, date, text) to anon;

-- 3) عرض طلبات التبديل الخاصة بالفرد (سواء هو مقدّم الطلب أو الطرف التاني)
create or replace function member_my_swap_requests(p_member_id uuid, p_pin text)
returns table(id uuid, swap_date date, note text, status text, created_at timestamptz, other_name text, i_am_requester boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_valid boolean;
begin
  select exists(select 1 from members where id = p_member_id and pin = p_pin) into v_valid;
  if not v_valid then
    raise exception 'invalid_credentials';
  end if;

  return query
  select sr.id, sr.swap_date, sr.note, sr.status, sr.created_at,
    case when sr.requester_id = p_member_id then mp.name else mr.name end,
    (sr.requester_id = p_member_id)
  from swap_requests sr
  join members mr on mr.id = sr.requester_id
  join members mp on mp.id = sr.partner_id
  where sr.requester_id = p_member_id or sr.partner_id = p_member_id
  order by sr.created_at desc
  limit 10;
end;
$$;
grant execute on function member_my_swap_requests(uuid, text) to anon;
