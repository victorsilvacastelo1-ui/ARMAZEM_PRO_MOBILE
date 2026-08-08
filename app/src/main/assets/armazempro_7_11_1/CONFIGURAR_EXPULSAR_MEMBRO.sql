-- ARMAZÉM PRO 6.3 — permitir que o administrador expulse funcionários
-- Execute este arquivo no Supabase: SQL Editor > New query > Run.

create or replace function public.remove_workspace_member(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workspace_id uuid;
  v_target_role text;
begin
  -- Encontra o espaço em que o usuário atual é administrador.
  select wm.workspace_id
    into v_workspace_id
  from public.workspace_members wm
  where wm.user_id = auth.uid()
    and wm.role = 'admin'
  limit 1;

  if v_workspace_id is null then
    raise exception 'Somente o administrador pode remover membros';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'O administrador não pode remover a própria conta';
  end if;

  select wm.role
    into v_target_role
  from public.workspace_members wm
  where wm.workspace_id = v_workspace_id
    and wm.user_id = p_user_id;

  if v_target_role is null then
    raise exception 'Este usuário não pertence à equipe';
  end if;

  if v_target_role = 'admin' then
    raise exception 'Não é permitido remover outro administrador';
  end if;

  delete from public.workspace_members
  where workspace_id = v_workspace_id
    and user_id = p_user_id
    and role <> 'admin';

  return found;
end;
$$;

grant execute on function public.remove_workspace_member(uuid) to authenticated;
