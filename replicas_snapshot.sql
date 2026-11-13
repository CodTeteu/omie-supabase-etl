-- Aplicar SOMENTE no espelho Audit. Metadados tecnicos da replicacao.
-- As gravacoes de negocio invalidam o snapshot na mesma transacao.
create table if not exists public.omie_replica_snapshot (
  id boolean primary key default true check (id),
  geracao bigint not null default 0,
  estado text not null default 'aguardando' check (estado in ('aguardando','pronto')),
  run_id bigint,
  tentativa integer,
  ciclo text,
  referencia date,
  origem_finalizado_em timestamptz,
  alterado_em timestamptz not null default now(),
  publicado_em timestamptz
);
insert into public.omie_replica_snapshot(id) values(true) on conflict do nothing;
alter table public.omie_replica_snapshot enable row level security;
revoke all on public.omie_replica_snapshot from public,anon,authenticated;
grant select,update on public.omie_replica_snapshot to service_role;

create or replace function public.omie_replica_invalidar()
returns trigger language plpgsql security definer
set search_path=pg_catalog as $$
begin
  update public.omie_replica_snapshot
     set geracao=geracao+1,estado='aguardando',alterado_em=clock_timestamp()
   where id;
  return null;
end $$;
revoke all on function public.omie_replica_invalidar() from public,anon,authenticated;

do $$ declare nome text;
begin
  foreach nome in array array['categorias_omie','departamentos_omie','clientes_grupo',
    'contas_receber_grupo','conta_corrente','movimentos_financeiros','contas_pagar','extrato_bancario']
  loop
    if not exists(select 1 from pg_trigger where tgrelid=format('public.%I',nome)::regclass
                  and tgname='omie_replica_invalidar_snapshot' and not tgisinternal) then
      execute format('create trigger omie_replica_invalidar_snapshot after insert or update or delete or truncate on public.%I for each statement execute function public.omie_replica_invalidar()',nome);
    end if;
  end loop;
end $$;

create or replace function public.publicar_snapshot_omie(p_dados jsonb)
returns jsonb language plpgsql security invoker
set search_path=pg_catalog as $$
declare atual public.omie_replica_snapshot;
begin
  if coalesce(p_dados->>'ciclo','') not in ('noturna','manha','tarde')
     or coalesce((p_dados->>'run_id')::bigint,0)<=0
     or coalesce((p_dados->>'tentativa')::int,0)<=0
     or p_dados->>'estado' is distinct from 'concluido' or p_dados->>'finalizado_em' is null
     or p_dados->>'referencia' is null or p_dados->>'geracao' is null then
    raise exception 'Publicacao exige carga completa validada';
  end if;
  select * into atual from public.omie_replica_snapshot where id for update;
  if atual.geracao<>(p_dados->>'geracao')::bigint then
    raise exception 'A origem mudou durante a publicacao';
  end if;
  if atual.run_id is not null and (atual.run_id,atual.tentativa)>
     ((p_dados->>'run_id')::bigint,(p_dados->>'tentativa')::int) then
    raise exception 'Publicacao de ciclo antigo recusada';
  end if;
  update public.omie_replica_snapshot set estado='pronto',
    run_id=(p_dados->>'run_id')::bigint,tentativa=(p_dados->>'tentativa')::int,
    ciclo=p_dados->>'ciclo',referencia=(p_dados->>'referencia')::date,
    origem_finalizado_em=(p_dados->>'finalizado_em')::timestamptz,publicado_em=clock_timestamp()
    where id;
  return jsonb_build_object('publicado',true,'run_id',(p_dados->>'run_id')::bigint,'geracao',atual.geracao);
end $$;
revoke all on function public.publicar_snapshot_omie(jsonb) from public,anon,authenticated;
grant execute on function public.publicar_snapshot_omie(jsonb) to service_role;
notify pgrst,'reload schema';
