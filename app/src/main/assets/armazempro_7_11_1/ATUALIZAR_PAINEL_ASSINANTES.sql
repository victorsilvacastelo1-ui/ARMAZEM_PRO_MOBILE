-- ARMAZÉM PRO 6.3 — ATUALIZAÇÃO DO PAINEL DE ASSINANTES
-- Execute no Supabase: Database > SQL Editor > New query > Run.
-- Não apaga clientes nem pagamentos antigos.

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
      max(mp.created_at) as last_payment_at,
      (array_agg(mp.amount order by mp.created_at desc))[1] as last_payment_amount,
      sum(case when mp.status='approved' then mp.amount else 0 end) as total_paid
    from public.mercado_pago_payments mp
    where mp.workspace_id=w.id
  ) pay on true
  order by coalesce(pay.last_payment_at,s.updated_at,s.created_at,w.created_at) desc nulls last;
end;
$$;

revoke all on function public.admin_list_subscriptions() from public;
grant execute on function public.admin_list_subscriptions() to authenticated;
