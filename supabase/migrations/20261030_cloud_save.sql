-- RaidersGo : sauvegarde cloud, achats, droits (appliquée le 30/10/2026 sur le projet Supabase).
-- Les joueurs (role authenticated, y compris comptes invités anonymes) ne voient et ne
-- modifient que leur propre ligne. Les achats et droits ne sont écrits que par le serveur
-- (service role / Edge Functions), jamais par le client.

create table public.player_saves (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  save        jsonb not null default '{}'::jsonb,
  version     integer not null default 0,
  device      text,
  client_ver  text,
  updated_at  timestamptz not null default now(),
  created_at  timestamptz not null default now()
);

create table public.purchases (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  store         text not null check (store in ('apple','google','simulated')),
  product_id    text not null,
  transaction_id text not null,
  gems_granted  integer not null default 0,
  raw_receipt   jsonb,
  created_at    timestamptz not null default now(),
  unique (store, transaction_id)
);
create index purchases_user_idx on public.purchases(user_id);

create table public.entitlements (
  user_id    uuid not null references auth.users(id) on delete cascade,
  key        text not null,
  granted_at timestamptz not null default now(),
  source     text,
  primary key (user_id, key)
);

-- Portefeuille serveur : gemmes créditées par le serveur (achats vérifiés). Le client
-- lit ce solde ; il ne peut pas l'augmenter lui-même.
create table public.wallets (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  gems_granted integer not null default 0,
  updated_at   timestamptz not null default now()
);

create table public.raid_logs (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  summary    jsonb not null,
  created_at timestamptz not null default now()
);
create index raid_logs_user_idx on public.raid_logs(user_id, created_at desc);

alter table public.player_saves  enable row level security;
alter table public.purchases     enable row level security;
alter table public.entitlements  enable row level security;
alter table public.wallets       enable row level security;
alter table public.raid_logs     enable row level security;

create policy "own save: read"   on public.player_saves for select to authenticated using ((select auth.uid()) = user_id);
create policy "own save: insert" on public.player_saves for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "own save: update" on public.player_saves for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy "own purchases: read"    on public.purchases    for select to authenticated using ((select auth.uid()) = user_id);
create policy "own entitlements: read" on public.entitlements for select to authenticated using ((select auth.uid()) = user_id);
create policy "own wallet: read"       on public.wallets      for select to authenticated using ((select auth.uid()) = user_id);
create policy "own raid logs: read"    on public.raid_logs    for select to authenticated using ((select auth.uid()) = user_id);
create policy "own raid logs: insert"  on public.raid_logs    for insert to authenticated with check ((select auth.uid()) = user_id);

-- Pousser une sauvegarde avec contrôle de version optimiste.
-- p_base_version = version que le client pense être celle du serveur.
-- Retour : {ok:true, version:n} ou {ok:false, reason:'conflict', version:n, save:{...}, updated_at:...}
create or replace function public.push_save(p_save jsonb, p_base_version integer, p_device text default null, p_client_ver text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  cur public.player_saves%rowtype;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'unauthenticated');
  end if;
  if pg_column_size(p_save) > 1048576 then
    return jsonb_build_object('ok', false, 'reason', 'too_large');
  end if;
  select * into cur from public.player_saves where user_id = uid for update;
  if not found then
    insert into public.player_saves(user_id, save, version, device, client_ver)
      values (uid, p_save, 1, p_device, p_client_ver);
    return jsonb_build_object('ok', true, 'version', 1);
  end if;
  if cur.version <> p_base_version then
    return jsonb_build_object('ok', false, 'reason', 'conflict', 'version', cur.version,
      'save', cur.save, 'updated_at', cur.updated_at, 'device', cur.device);
  end if;
  update public.player_saves
    set save = p_save, version = cur.version + 1, device = p_device, client_ver = p_client_ver, updated_at = now()
    where user_id = uid;
  return jsonb_build_object('ok', true, 'version', cur.version + 1);
end;
$$;

-- Tout ce que le client doit connaître à la connexion, en un seul appel.
create or replace function public.pull_state()
returns jsonb
language sql
security invoker
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'save', (select jsonb_build_object('save', s.save, 'version', s.version, 'updated_at', s.updated_at, 'device', s.device)
             from public.player_saves s where s.user_id = (select auth.uid())),
    'gems_granted', coalesce((select w.gems_granted from public.wallets w where w.user_id = (select auth.uid())), 0),
    'entitlements', coalesce((select jsonb_agg(e.key) from public.entitlements e where e.user_id = (select auth.uid())), '[]'::jsonb)
  );
$$;

revoke all on function public.push_save(jsonb, integer, text, text) from public, anon;
revoke all on function public.pull_state() from public, anon;
grant execute on function public.push_save(jsonb, integer, text, text) to authenticated;
grant execute on function public.pull_state() to authenticated;
