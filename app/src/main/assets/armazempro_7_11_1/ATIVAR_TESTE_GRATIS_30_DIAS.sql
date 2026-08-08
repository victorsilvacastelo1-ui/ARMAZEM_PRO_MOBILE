-- ARMAZÉM PRO — TESTE GRATUITO AUTOMÁTICO DE 30 DIAS
-- Execute este arquivo UMA VEZ no Supabase:
-- SQL Editor > New query > cole todo o conteúdo > Run.
--
-- Esta configuração:
-- 1. libera 30 dias grátis para espaços novos;
-- 2. não altera assinaturas mensais, anuais, vitalícias ou legadas já existentes;
-- 3. permite que contas pendentes e ainda não pagas iniciem o teste ao entrar;
-- 4. mantém todos os dados salvos quando o teste terminar.

create or replace function public.ensure_my_trial()
returns public.subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workspace_id uuid;
  v_subscription public.subscriptions;
begin
  select wm.workspace_id
    into v_workspace_id
  from public.workspace_members wm
  where wm.user_id = auth.uid()
  order by case when wm.role = 'admin' then 0 else 1 end, wm.created_at
  limit 1;

  if v_workspace_id is null then
    raise exception 'Usuário ainda não possui espaço de trabalho';
  end if;

  -- Cria o teste apenas quando ainda não há assinatura.
  insert into public.subscriptions (workspace_id, plan, status, expires_at, updated_at)
  values (v_workspace_id, 'trial', 'trial', now() + interval '30 days', now())
  on conflict (workspace_id) do nothing;

  -- Converte somente registros pendentes, sem plano pago e sem vencimento.
  update public.subscriptions
     set plan = 'trial',
         status = 'trial',
         expires_at = now() + interval '30 days',
         updated_at = now()
   where workspace_id = v_workspace_id
     and coalesce(status, 'pending') = 'pending'
     and coalesce(plan, 'none') in ('none', 'pending', '')
     and expires_at is null;

  select * into v_subscription
  from public.subscriptions
  where workspace_id = v_workspace_id;

  return v_subscription;
end;
$$;

revoke all on function public.ensure_my_trial() from public;
grant execute on function public.ensure_my_trial() to authenticated;

-- Também aplica automaticamente o teste quando um novo espaço é criado.
create or replace function public.create_trial_for_new_workspace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.subscriptions (workspace_id, plan, status, expires_at, updated_at)
  values (new.id, 'trial', 'trial', now() + interval '30 days', now())
  on conflict (workspace_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_create_trial_for_new_workspace on public.workspaces;
create trigger trg_create_trial_for_new_workspace
after insert on public.workspaces
for each row execute function public.create_trial_for_new_workspace();

-- Ativa o teste para espaços existentes que ainda estejam pendentes e nunca tiveram plano pago.
update public.subscriptions
   set plan = 'trial',
       status = 'trial',
       expires_at = now() + interval '30 days',
       updated_at = now()
 where coalesce(status, 'pending') = 'pending'
   and coalesce(plan, 'none') in ('none', 'pending', '')
   and expires_at is null;
