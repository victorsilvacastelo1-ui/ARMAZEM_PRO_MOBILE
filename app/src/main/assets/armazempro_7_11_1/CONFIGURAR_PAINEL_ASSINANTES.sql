-- ARMAZÉM PRO 6.3 — CONFIGURAÇÃO COMPLETA DO PAINEL DE ASSINANTES
-- Execute TODO este arquivo no Supabase: SQL Editor > New query > Run.
-- Não apaga clientes, estoques, assinaturas ou pagamentos.

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.platform_admins enable row level security;

-- Define automaticamente como administrador da plataforma o usuário mais antigo
-- do projeto. Normalmente é a conta do proprietário que criou o sistema.
insert into public.platform_admins (user_id)
select id
from auth.users
order by created_at asc
limit 1
on conflict (user_id) do nothing;

create or replace function public.is_platform_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.platform_admins pa
    where pa.user_id = auth.uid()
  );
$$;

revoke all on function public.is_platform_admin() from public;
grant execute on function public.is_platform_admin() to authenticated;

create or replace function public.admin_list_subscriptions()
returns table (
  workspace_id uuid,
  workspace_name text,
  invite_code text,
  owner_name text,
  owner_email text,
  status text,
  plan text,
  expires_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  last_payment_at timestamptz,
  last_payment_amount numeric,
  total_paid numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Acesso administrativo não autorizado';
  end if;

  return query
  select
    w.id,
    w.name,
    w.invite_code,
    coalesce(p.name,'Usuário')::text,
    coalesce(p.email,'E-mail não informado')::text,
    coalesce(s.status,'pending')::text,
    coalesce(s.plan,'pending')::text,
    s.expires_at,
    s.created_at,
    s.updated_at,
    pay.last_payment_at,
    coalesce(pay.last_payment_amount,0)::numeric,
    coalesce(pay.total_paid,0)::numeric
  from public.workspaces w
  left join public.subscriptions s on s.workspace_id=w.id
  left join lateral (
    select pr.name,pr.email
    from public.workspace_members wm
    left join public.profiles pr on pr.user_id=wm.user_id
    where wm.workspace_id=w.id
    order by case when wm.role='admin' then 0 else 1 end, wm.created_at
    limit 1
  ) p on true
  left join lateral (
    select
      max(mp.created_at) filter (where mp.status='approved') as last_payment_at,
      (array_agg(mp.amount order by mp.created_at desc) filter (where mp.status='approved'))[1] as last_payment_amount,
      sum(case when mp.status='approved' then mp.amount else 0 end) as total_paid
    from public.mercado_pago_payments mp
    where mp.workspace_id=w.id
  ) pay on true
  order by coalesce(pay.last_payment_at,s.updated_at,s.created_at,w.created_at) desc nulls last;
end;
$$;

revoke all on function public.admin_list_subscriptions() from public;
grant execute on function public.admin_list_subscriptions() to authenticated;

create or replace function public.admin_set_subscription(
  p_workspace_id uuid,
  p_plan text,
  p_status text,
  p_days integer default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expires timestamptz;
begin
  if not public.is_platform_admin() then
    raise exception 'Acesso administrativo não autorizado';
  end if;

  if coalesce(p_days,0) > 0 then
    v_expires := now() + make_interval(days => p_days);
  elsif p_plan in ('legacy','lifetime') then
    v_expires := null;
  else
    v_expires := null;
  end if;

  insert into public.subscriptions (workspace_id, plan, status, expires_at, updated_at)
  values (p_workspace_id, coalesce(p_plan,'none'), p_status, v_expires, now())
  on conflict (workspace_id) do update
  set plan = coalesce(excluded.plan, public.subscriptions.plan),
      status = excluded.status,
      expires_at = excluded.expires_at,
      updated_at = now();
end;
$$;

revoke all on function public.admin_set_subscription(uuid,text,text,integer) from public;
grant execute on function public.admin_set_subscription(uuid,text,text,integer) to authenticated;
