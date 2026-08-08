-- ARMAZÉM PRO 7.7 — CONVITES REUTILIZÁVEIS DE EQUIPE SEM ASSINATURA EXTRA
-- Execute todo este arquivo no Supabase > SQL Editor > Run.
-- Permite 1 administrador + até 3 convidados usando a assinatura do mesmo espaço.

create extension if not exists pgcrypto;

-- Compatibilidade com os perfis usados pelo sistema.
alter table public.workspace_members
  drop constraint if exists workspace_members_role_check;
alter table public.workspace_members
  add constraint workspace_members_role_check
  check (role in ('admin','employee','manager','operator'));


create table if not exists public.workspace_invites (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  email text not null,
  name text,
  role text not null default 'operator' check (role in ('manager','operator')),
  token uuid not null default gen_random_uuid() unique,
  status text not null default 'pending' check (status in ('pending','accepted','cancelled','expired')),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_at timestamptz
);

create index if not exists workspace_invites_workspace_idx on public.workspace_invites(workspace_id);
create index if not exists workspace_invites_email_idx on public.workspace_invites(lower(email));

alter table public.workspace_invites enable row level security;

-- O acesso direto fica bloqueado. As operações são feitas pelas funções seguras abaixo.
revoke all on public.workspace_invites from anon, authenticated;

create or replace function public.create_workspace_invite(
  p_email text,
  p_name text default null,
  p_role text default 'operator'
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_workspace_id uuid;
  v_member_count integer;
  v_pending_count integer;
  v_token uuid;
  v_email text := lower(trim(p_email));
begin
  if v_user is null then raise exception 'Usuário não autenticado'; end if;
  if v_email is null or v_email = '' then raise exception 'Informe o e-mail'; end if;
  if p_role not in ('manager','operator') then raise exception 'Perfil inválido'; end if;

  select wm.workspace_id into v_workspace_id
  from public.workspace_members wm
  where wm.user_id = v_user and wm.role = 'admin'
  order by wm.created_at asc
  limit 1;

  if v_workspace_id is null then raise exception 'Somente o administrador pode convidar usuários'; end if;

  if exists (
    select 1 from public.workspace_members wm
    join public.profiles p on p.user_id = wm.user_id
    where wm.workspace_id = v_workspace_id and lower(p.email) = v_email
  ) then
    raise exception 'Este e-mail já faz parte da equipe';
  end if;

  -- Substitui qualquer convite anterior do mesmo e-mail antes de contar as vagas.
  -- Assim o administrador pode gerar um novo link quantas vezes precisar.
  update public.workspace_invites
  set status = 'cancelled'
  where workspace_id = v_workspace_id
    and lower(email) = v_email
    and status = 'pending';

  select count(*) into v_member_count
  from public.workspace_members
  where workspace_id = v_workspace_id and role <> 'admin';

  select count(*) into v_pending_count
  from public.workspace_invites
  where workspace_id = v_workspace_id
    and status = 'pending'
    and expires_at > now();

  if (v_member_count + v_pending_count) >= 3 then
    raise exception 'Limite de 3 convidados atingido';
  end if;

  insert into public.workspace_invites(workspace_id,email,name,role,created_by)
  values(v_workspace_id,v_email,nullif(trim(p_name),''),p_role,v_user)
  returning token into v_token;

  return v_token::text;
end;
$$;

create or replace function public.accept_workspace_invite(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_auth_email text;
  v_invite public.workspace_invites%rowtype;
  v_member_count integer;
begin
  if v_user is null then raise exception 'Usuário não autenticado'; end if;

  select lower(email) into v_auth_email from auth.users where id = v_user;

  select * into v_invite
  from public.workspace_invites
  where token = p_token::uuid
  limit 1;

  if v_invite.id is null then raise exception 'Convite inválido'; end if;
  if lower(v_invite.email) <> v_auth_email then
    raise exception 'Entre ou crie a conta usando o e-mail convidado: %', v_invite.email;
  end if;

  -- Aceite idempotente: abrir o mesmo link novamente não gera erro
  -- quando o usuário já entrou nesse espaço.
  if exists(
    select 1 from public.workspace_members
    where workspace_id=v_invite.workspace_id and user_id=v_user
  ) then
    update public.workspace_invites
    set status='accepted', accepted_at=coalesce(accepted_at,now())
    where id=v_invite.id and status <> 'cancelled';
    return jsonb_build_object('workspace_id',v_invite.workspace_id,'already_member',true);
  end if;

  if v_invite.status = 'cancelled' then
    raise exception 'Este convite foi cancelado. Peça ao administrador para gerar um novo link';
  end if;
  if v_invite.status = 'expired' or v_invite.expires_at <= now() then
    update public.workspace_invites set status='expired' where id=v_invite.id;
    raise exception 'Este convite expirou. Peça um novo convite ao administrador';
  end if;
  if v_invite.status = 'accepted' then
    -- Recupera convites marcados como aceitos por versões antigas, mas sem membro criado.
    update public.workspace_invites set status='pending', accepted_at=null where id=v_invite.id;
  elsif v_invite.status <> 'pending' then
    raise exception 'Este convite não está disponível';
  end if;

  select count(*) into v_member_count
  from public.workspace_members
  where workspace_id=v_invite.workspace_id and role <> 'admin';
  if v_member_count >= 3 then raise exception 'Limite de 3 convidados atingido'; end if;

  insert into public.workspace_members(workspace_id,user_id,role)
  values(v_invite.workspace_id,v_user,v_invite.role)
  on conflict (workspace_id,user_id) do update set role=excluded.role;

  insert into public.profiles(user_id,name,email)
  values(v_user,coalesce(nullif(v_invite.name,''),split_part(v_auth_email,'@',1)),v_auth_email)
  on conflict(user_id) do update set
    name=coalesce(excluded.name,public.profiles.name),
    email=excluded.email;

  -- O convite só é consumido após membro e perfil terem sido gravados com sucesso.
  update public.workspace_invites
  set status='accepted',accepted_at=now()
  where id=v_invite.id;

  return jsonb_build_object('workspace_id',v_invite.workspace_id,'joined',true,'role',v_invite.role);
end;
$$;

grant execute on function public.create_workspace_invite(text,text,text) to authenticated;
grant execute on function public.accept_workspace_invite(text) to authenticated;

-- ARMAZÉM PRO 7.5 — LISTAR E CANCELAR CONVITES PENDENTES
create or replace function public.list_workspace_invites()
returns table(
  id uuid,
  email text,
  name text,
  role text,
  token uuid,
  status text,
  created_at timestamptz,
  expires_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select wi.id, wi.email, wi.name, wi.role, wi.token, wi.status, wi.created_at, wi.expires_at
  from public.workspace_invites wi
  join public.workspace_members wm on wm.workspace_id = wi.workspace_id
  where wm.user_id = auth.uid()
    and wm.role = 'admin'
    and wi.status = 'pending'
    and wi.expires_at > now()
  order by wi.created_at desc;
$$;

create or replace function public.cancel_workspace_invite(p_invite_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workspace_id uuid;
begin
  select wi.workspace_id into v_workspace_id
  from public.workspace_invites wi
  where wi.id = p_invite_id;

  if v_workspace_id is null then raise exception 'Convite não encontrado'; end if;
  if not exists (
    select 1 from public.workspace_members wm
    where wm.workspace_id = v_workspace_id
      and wm.user_id = auth.uid()
      and wm.role = 'admin'
  ) then raise exception 'Somente o administrador pode cancelar convites'; end if;

  update public.workspace_invites
  set status = 'cancelled'
  where id = p_invite_id and status = 'pending';
  return found;
end;
$$;

grant execute on function public.list_workspace_invites() to authenticated;
grant execute on function public.cancel_workspace_invite(uuid) to authenticated;
