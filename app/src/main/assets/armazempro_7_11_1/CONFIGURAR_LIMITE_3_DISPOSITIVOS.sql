-- ARMAZÉM PRO 7.1 — LIMITE DE 3 CONVIDADOS POR ASSINATURA
-- Execute este arquivo no SQL Editor do Supabase.
-- O administrador não conta no limite. São permitidos até 3 usuários/dispositivos convidados.

create or replace function public.join_workspace_by_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_workspace public.workspaces%rowtype;
  v_invited_count integer;
begin
  if v_user is null then
    raise exception 'Usuário não autenticado';
  end if;

  select * into v_workspace
  from public.workspaces
  where upper(invite_code) = upper(trim(p_code))
  limit 1;

  if v_workspace.id is null then
    raise exception 'Código de convite inválido';
  end if;

  if exists (
    select 1 from public.workspace_members
    where workspace_id = v_workspace.id and user_id = v_user
  ) then
    return jsonb_build_object('workspace_id', v_workspace.id, 'already_member', true);
  end if;

  select count(*) into v_invited_count
  from public.workspace_members
  where workspace_id = v_workspace.id
    and role <> 'admin';

  if v_invited_count >= 3 then
    raise exception 'Limite de 3 dispositivos convidados atingido';
  end if;

  insert into public.workspace_members(workspace_id,user_id,role)
  values(v_workspace.id,v_user,'employee');

  return jsonb_build_object('workspace_id', v_workspace.id, 'joined', true);
end;
$$;

grant execute on function public.join_workspace_by_code(text) to authenticated;
