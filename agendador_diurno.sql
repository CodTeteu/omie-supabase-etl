-- Agendador das 11h/15h no banco principal. Aplicar operacao_etl.sql antes.
-- O token existente do GitHub e guardado separadamente no Vault, nunca neste arquivo.
do $$ begin
  if not exists (select 1 from pg_extension where extname = 'http') then
    create extension http with schema extensions;
  end if;
end $$;

create table if not exists etl_operacao.configuracao (
  id boolean primary key default true check (id),
  ativo boolean not null default false,
  inicio_em date not null
);
insert into etl_operacao.configuracao(id, inicio_em)
  values (true, ((now() at time zone 'America/Sao_Paulo')::date + 1))
  on conflict (id) do nothing;

create table if not exists etl_operacao.disparos (
  id bigserial primary key,
  em timestamptz not null default now(),
  ciclo text not null,
  referencia date not null,
  status integer,
  detalhe text
);
alter table etl_operacao.configuracao enable row level security;
alter table etl_operacao.disparos enable row level security;
revoke all on etl_operacao.configuracao, etl_operacao.disparos from public, anon, authenticated;

create or replace function etl_operacao.chamar_github(p_metodo text, p_caminho text, p_corpo text default null)
returns extensions.http_response language plpgsql security invoker
set search_path = pg_catalog, etl_operacao as $$
declare token text;
begin
  select decrypted_secret into token from vault.decrypted_secrets where name = 'github_token_rotina_diurna';
  if token is null then raise exception 'Token do agendador diurno ausente no Vault'; end if;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '30');
  return extensions.http((p_metodo,
    'https://api.github.com/repos/CodTeteu/omie-supabase-etl' || p_caminho,
    array[extensions.http_header('Authorization', 'Bearer ' || token),
          extensions.http_header('Accept', 'application/vnd.github+json'),
          extensions.http_header('User-Agent', 'agendador-omie-diurno')],
    'application/json', p_corpo)::extensions.http_request);
end $$;
revoke all on function etl_operacao.chamar_github(text, text, text) from public, anon, authenticated, service_role;

create or replace function etl_operacao.disparar(p_ciclo text)
returns text language plpgsql security invoker
set search_path = pg_catalog, etl_operacao as $$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  hora integer := extract(hour from now() at time zone 'America/Sao_Paulo');
  resposta extensions.http_response;
begin
  if p_ciclo not in ('manha', 'tarde') then raise exception 'Ciclo invalido'; end if;
  if not exists (select 1 from etl_operacao.configuracao where ativo and inicio_em <= hoje)
     or extract(isodow from hoje) > 5 then return 'fora do calendario ativo'; end if;
  if (p_ciclo = 'manha' and (hora < 11 or hora >= 15))
     or (p_ciclo = 'tarde' and (hora < 15 or hora >= 22)) then return 'fora da janela'; end if;
  if exists (select 1 from etl_operacao.execucoes
             where ciclo = p_ciclo and referencia = hoje and estado in ('executando', 'concluido')) then
    return 'ciclo ja iniciado';
  end if;
  if exists (select 1 from etl_operacao.disparos
             where ciclo = p_ciclo and referencia = hoje and status between 200 and 299
               and em > now() - interval '20 minutes') then
    return 'disparo ja aceito';
  end if;
  resposta := etl_operacao.chamar_github('POST', '/actions/workflows/schedule.yml/dispatches',
    jsonb_build_object('ref', 'main', 'inputs',
      jsonb_build_object('agendador', 'true', 'ciclo', p_ciclo))::text);
  insert into etl_operacao.disparos(ciclo, referencia, status, detalhe)
    values(p_ciclo, hoje, resposta.status,
           case when resposta.status >= 300 then left(resposta.content, 400) end);
  return resposta.status::text;
exception when others then
  insert into etl_operacao.disparos(ciclo, referencia, detalhe)
    values(p_ciclo, hoje, 'Falha no disparo: SQLSTATE ' || sqlstate);
  return 'falha no disparo';
end $$;
revoke all on function etl_operacao.disparar(text) from public, anon, authenticated, service_role;

-- pg_cron usa UTC. Brasilia = UTC-3. As reservas so repetem se o HTTP nao foi aceito.
select cron.schedule('rotina-omie-11h', '0 14 * * 1-5', $$select etl_operacao.disparar('manha')$$);
select cron.schedule('rotina-omie-11h10', '10 14 * * 1-5', $$select etl_operacao.disparar('manha')$$);
select cron.schedule('rotina-omie-15h', '0 18 * * 1-5', $$select etl_operacao.disparar('tarde')$$);
select cron.schedule('rotina-omie-15h10', '10 18 * * 1-5', $$select etl_operacao.disparar('tarde')$$);
