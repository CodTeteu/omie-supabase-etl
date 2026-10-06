-- Agendador da Rotina Noturna Omie ETL, no Supabase da Audit (projeto omie-supabase-etl).
--
-- O agendamento do GitHub atrasa horas (ver decidir_execucao.py). Aqui o pg_cron do banco
-- chama a API do GitHub as 22:00 de Brasilia e a rotina comeca em segundos. A tentativa
-- das 22:30 so dispara se a das 22:00 nao foi aceita. Quem decide se a carga roda continua
-- sendo o job "decidir": com o input agendador=true ele segue as regras da noite (nao
-- repete a carga nem atropela uma execucao em andamento).
--
-- Pre-requisito: um token fine-grained do GitHub so para este repositorio, com
-- "Actions: Read and write", no Vault do Supabase com o nome github_token_rotina
-- (painel > Integrations > Vault). O token nunca fica neste arquivo.
--
-- Acompanhar:               select * from agendador.disparos order by id desc limit 20;
-- Testar o token (sem carga): select agendador.testar_token();      -- 200 = ok
-- Disparar agora:            select agendador.disparar_rotina(true);  -- segue as regras da noite
--
-- Idempotente: pode rodar de novo para recriar ou atualizar.

create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

create schema if not exists agendador;
revoke all on schema agendador from public;

create table if not exists agendador.disparos (
  id      bigserial primary key,
  em      timestamptz not null default now(),
  tipo    text not null,  -- 'disparo' ou 'teste'
  status  int,            -- resposta HTTP do GitHub; nulo = nao chegou a chamar
  detalhe text
);

-- Chamada autenticada a API do GitHub, no repositorio da rotina.
create or replace function agendador.chamar_github(metodo text, caminho text, corpo text default null)
returns extensions.http_response
language plpgsql
as $$
declare
  token text;
begin
  select decrypted_secret into token from vault.decrypted_secrets where name = 'github_token_rotina';
  if token is null then
    raise exception 'sem o secret github_token_rotina no Vault';
  end if;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '30');
  return extensions.http((
    metodo,
    'https://api.github.com/repos/CodTeteu/omie-supabase-etl' || caminho,
    array[
      extensions.http_header('Authorization', 'Bearer ' || token),
      extensions.http_header('Accept', 'application/vnd.github+json'),
      extensions.http_header('X-GitHub-Api-Version', '2022-11-28'),
      extensions.http_header('User-Agent', 'agendador-rotina-omie')
    ],
    'application/json',
    corpo
  )::extensions.http_request);
end
$$;

-- Dispara a rotina (workflow_dispatch com agendador=true). Sem forcar, nao dispara de novo
-- se um disparo foi aceito nas ultimas 3 horas. O GitHub responde 204 quando aceita.
create or replace function agendador.disparar_rotina(forcar boolean default false)
returns text
language plpgsql
as $$
declare
  resp extensions.http_response;
begin
  if not forcar and exists (
    select 1 from agendador.disparos
    where tipo = 'disparo' and status between 200 and 299 and em > now() - interval '3 hours'
  ) then
    insert into agendador.disparos (tipo, detalhe) values ('disparo', 'ja aceito nas ultimas 3 h: nada a fazer');
    return 'ja disparado';
  end if;
  resp := agendador.chamar_github('POST', '/actions/workflows/schedule.yml/dispatches',
                                  '{"ref": "main", "inputs": {"agendador": "true"}}');
  insert into agendador.disparos (tipo, status, detalhe)
  values ('disparo', resp.status, nullif(left(resp.content, 500), ''));
  return resp.status::text;
exception when others then
  insert into agendador.disparos (tipo, detalhe) values ('disparo', 'erro: ' || sqlerrm);
  return 'erro: ' || sqlerrm;
end
$$;

-- Confere o token sem disparar nada (le os dados do workflow).
create or replace function agendador.testar_token()
returns text
language plpgsql
as $$
declare
  resp extensions.http_response;
begin
  resp := agendador.chamar_github('GET', '/actions/workflows/schedule.yml');
  insert into agendador.disparos (tipo, status, detalhe)
  values ('teste', resp.status,
          case when resp.status = 200 then 'token valido' else nullif(left(resp.content, 500), '') end);
  return resp.status::text;
exception when others then
  insert into agendador.disparos (tipo, detalhe) values ('teste', 'erro: ' || sqlerrm);
  return 'erro: ' || sqlerrm;
end
$$;

revoke all on all tables in schema agendador from public, anon, authenticated;
revoke all on all sequences in schema agendador from public, anon, authenticated;
revoke all on all functions in schema agendador from public, anon, authenticated;

-- pg_cron trabalha em UTC: 01:00 UTC = 22:00 em Brasilia (sem horario de verao desde 2019).
select cron.schedule('rotina-omie-22h', '0 1 * * *', 'select agendador.disparar_rotina()');
select cron.schedule('rotina-omie-22h30', '30 1 * * *', 'select agendador.disparar_rotina()');
