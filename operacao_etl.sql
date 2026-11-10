-- Aplicar no banco PRINCIPAL. O espelho recebe somente os dados do Omie.
-- Controle privado. A RPC publica usa SECURITY INVOKER e so a service_role a executa.
create schema if not exists etl_operacao;
revoke all on schema etl_operacao from public, anon, authenticated;
grant usage on schema etl_operacao to service_role;

create table if not exists etl_operacao.configuracao (
  id boolean primary key default true check (id),
  ativo boolean not null default false,
  inicio_em date not null
);
insert into etl_operacao.configuracao(id, inicio_em)
  values (true, ((now() at time zone 'America/Sao_Paulo')::date + 1))
  on conflict (id) do nothing;
alter table etl_operacao.configuracao enable row level security;
revoke all on etl_operacao.configuracao from public, anon, authenticated;
grant select on etl_operacao.configuracao to service_role;

create table if not exists etl_operacao.execucoes (
  run_id bigint not null,
  tentativa integer not null default 1,
  ciclo text not null check (ciclo in ('noturna', 'manha', 'tarde')),
  referencia date not null,
  estado text not null check (estado in ('executando', 'concluido', 'falhou')),
  iniciado_em timestamptz not null default now(),
  finalizado_em timestamptz,
  primary key (run_id, tentativa)
);
create index if not exists execucoes_ciclo_referencia
  on etl_operacao.execucoes(ciclo, referencia, iniciado_em desc);

create table if not exists etl_operacao.powerbi (
  ciclo text not null check (ciclo in ('manha', 'tarde')),
  referencia date not null,
  modelo_id uuid not null,
  nome text not null,
  estado text not null,
  dados jsonb not null,
  atualizado_em timestamptz not null default now(),
  primary key (ciclo, referencia, modelo_id)
);
alter table etl_operacao.execucoes enable row level security;
alter table etl_operacao.powerbi enable row level security;
revoke all on all tables in schema etl_operacao from public, anon, authenticated;
grant select, insert, update on etl_operacao.execucoes, etl_operacao.powerbi to service_role;

create or replace function public.etl_operacao(p_acao text, p_dados jsonb default '{}')
returns jsonb language plpgsql security invoker
set search_path = pg_catalog, etl_operacao as $$
declare
  resultado jsonb;
  carga jsonb;
  ultima jsonb;
  modelos jsonb;
  pendentes jsonb;
  agenda jsonb;
begin
  if p_acao = 'validar' then
    return jsonb_build_object('versao', 1);
  elsif p_acao = 'consulta' then
    select to_jsonb(e) into carga from etl_operacao.execucoes e
      where ciclo = p_dados->>'ciclo' and referencia = (p_dados->>'referencia')::date
      order by iniciado_em desc, run_id desc, tentativa desc limit 1;
    select to_jsonb(e) into ultima from etl_operacao.execucoes e
      order by iniciado_em desc, run_id desc, tentativa desc limit 1;
    select coalesce(jsonb_agg(to_jsonb(p)), '[]') into modelos from etl_operacao.powerbi p
      where ciclo = p_dados->>'ciclo' and referencia = (p_dados->>'referencia')::date;
    select coalesce(jsonb_agg(to_jsonb(p)), '[]') into pendentes from etl_operacao.powerbi p
      where estado in ('executando', 'submetendo', 'incerta');
    select to_jsonb(c) into agenda from etl_operacao.configuracao c where id;
    return jsonb_build_object('execucao', carga, 'ultima_carga', ultima,
                             'powerbi', modelos, 'powerbi_pendentes', pendentes, 'agenda', agenda);
  elsif p_acao = 'iniciar' then
    insert into etl_operacao.execucoes(run_id, tentativa, ciclo, referencia, estado)
      values ((p_dados->>'run_id')::bigint, (p_dados->>'tentativa')::int,
              p_dados->>'ciclo', (p_dados->>'referencia')::date, 'executando')
      on conflict (run_id, tentativa) do nothing;
    return jsonb_build_object('registrado', true);
  elsif p_acao = 'finalizar' then
    if p_dados->>'estado' not in ('concluido', 'falhou') then
      raise exception 'Estado final invalido';
    end if;
    update etl_operacao.execucoes set estado = p_dados->>'estado', finalizado_em = now()
      where run_id = (p_dados->>'run_id')::bigint and tentativa = (p_dados->>'tentativa')::int
        and ciclo = p_dados->>'ciclo' and referencia = (p_dados->>'referencia')::date;
    if not found then raise exception 'Inicio desta carga nao registrado'; end if;
    return jsonb_build_object('registrado', true);
  elsif p_acao = 'powerbi' then
    insert into etl_operacao.powerbi(ciclo, referencia, modelo_id, nome, estado, dados)
      values (p_dados->>'ciclo', (p_dados->>'referencia')::date,
              (p_dados->>'modelo_id')::uuid, p_dados->>'nome', p_dados->>'estado',
              p_dados->'dados')
      on conflict (ciclo, referencia, modelo_id) do update
      set nome = excluded.nome, estado = excluded.estado, dados = excluded.dados,
          atualizado_em = now();
    return jsonb_build_object('registrado', true);
  end if;
  raise exception 'Operacao de controle desconhecida';
end $$;
revoke all on function public.etl_operacao(text, jsonb) from public, anon, authenticated;
grant execute on function public.etl_operacao(text, jsonb) to service_role;
notify pgrst, 'reload schema';
