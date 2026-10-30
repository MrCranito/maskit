-- Archive anonymisée des achats d'un compte supprimé (obligation comptable, aucun lien joueur).
-- La suppression de compte elle-même est faite par l'Edge Function delete_account (service role,
-- API admin Supabase) : elle archive les achats puis supprime l'utilisateur → cascade.
create table if not exists public.purchases_archive (
  id bigint primary key,
  store text not null,
  product_id text not null,
  transaction_id text not null,
  gems_granted integer not null,
  created_at timestamptz not null,
  archived_at timestamptz not null default now()
);
alter table public.purchases_archive enable row level security;

-- Crédit d'un achat vérifié : appelé UNIQUEMENT par l'Edge Function verify_purchase (service role).
-- Idempotent par (store, transaction_id) : un reçu rejoué ne crédite pas deux fois.
create or replace function public.grant_purchase(p_user uuid, p_store text, p_product text, p_transaction text,
    p_gems integer, p_entitlements text[], p_raw jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing public.purchases%rowtype;
  e text;
begin
  select * into existing from public.purchases where store = p_store and transaction_id = p_transaction;
  if found then
    if existing.user_id <> p_user then
      return jsonb_build_object('ok', false, 'reason', 'transaction_owned_by_other_user');
    end if;
    return jsonb_build_object('ok', true, 'duplicate', true, 'gems', 0,
      'entitlements', coalesce(p_entitlements, '{}'));
  end if;
  insert into public.purchases(user_id, store, product_id, transaction_id, gems_granted, raw_receipt)
    values (p_user, p_store, p_product, p_transaction, coalesce(p_gems, 0), p_raw);
  insert into public.wallets(user_id, gems_granted) values (p_user, coalesce(p_gems, 0))
    on conflict (user_id) do update set gems_granted = public.wallets.gems_granted + excluded.gems_granted, updated_at = now();
  foreach e in array coalesce(p_entitlements, '{}') loop
    insert into public.entitlements(user_id, key, source) values (p_user, e, p_store || ':' || p_transaction)
      on conflict (user_id, key) do nothing;
  end loop;
  return jsonb_build_object('ok', true, 'duplicate', false, 'gems', coalesce(p_gems, 0),
    'entitlements', coalesce(p_entitlements, '{}'));
end;
$$;
revoke all on function public.grant_purchase(uuid, text, text, text, integer, text[], jsonb) from public, anon, authenticated;
grant execute on function public.grant_purchase(uuid, text, text, text, integer, text[], jsonb) to service_role;

-- Catalogue des produits (source de vérité serveur : un reçu ne crédite que ce que le catalogue dit).
create table public.products (
  product_id text primary key,
  kind text not null check (kind in ('gems','bundle')),
  gems integer not null default 0,
  entitlements text[] not null default '{}',
  active boolean not null default true
);
alter table public.products enable row level security;
create policy "products: public read" on public.products for select to anon, authenticated using (active);
insert into public.products(product_id, kind, gems, entitlements) values
  ('gems_80','gems',80,'{}'), ('gems_450','gems',450,'{}'), ('gems_1000','gems',1000,'{}'), ('gems_2200','gems',2200,'{}'),
  ('bundle_recrue','bundle',450,'{bundle_recrue}'), ('bundle_commando','bundle',0,'{bundle_commando}'), ('bundle_or_massif','bundle',500,'{bundle_or_massif}');
