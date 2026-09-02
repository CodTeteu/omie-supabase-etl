import os
import requests
from dotenv import load_dotenv

load_dotenv()

url = os.environ.get('SUPABASE_URL').rstrip('/')
key = os.environ.get('SUPABASE_KEY')
sql = """
create or replace view public.painel_contas_pagar as
with
  ClientesUnicos as (
    select distinct on (codigo_cliente_omie, empresa_cnpj) *
    from clientes_grupo
    order by codigo_cliente_omie, empresa_cnpj
  ),
  CategoriasUnicas as (
    select distinct on (codigo, empresa_cnpj) *
    from categorias_omie
    order by codigo, empresa_cnpj
  ),
  DepartamentosUnicos as (
    select distinct on (codigo, empresa_cnpj) *
    from departamentos_omie
    order by codigo, empresa_cnpj
  ),
  base_cp as (
    select
      cp.empresa_nome,
      cp.empresa_cnpj,
      cl.cnpj_cpf as cnpj,
      cl.razao_social,
      cp.data_vencimento,
      cp.data_previsao,
      COALESCE(
        TO_DATE(NULLIF(cp.json_bruto -> 'info' ->> 'dDtPagamento', ''), 'DD/MM/YYYY'),
        TO_DATE(NULLIF(cp.json_bruto -> 'info' ->> 'dDtBaixa', ''), 'DD/MM/YYYY'),
        TO_DATE(NULLIF(cp.json_bruto -> 'resumo' ->> 'dDtBaixa', ''), 'DD/MM/YYYY'),
        TO_DATE(NULLIF(cp.json_bruto ->> 'data_pagamento', ''), 'DD/MM/YYYY'),
        TO_DATE(NULLIF(cp.json_bruto ->> 'data_baixa', ''), 'DD/MM/YYYY'),
        cc.max_data_lancamento, 
        cp.data_vencimento
      ) as data_lancamento,
      cp.codigo_lancamento_omie,
      case
        when cc.id_conta_corrente is not null then 'PAGO (No Banco)'::character varying
        else cp.status_titulo
      end as status_titulo,
      COALESCE(
        cp.codigo_cliente_fornecedor,
        cc.id_cliente_fornecedor
      ) as codigo_cliente_fornecedor,
      cat.descricao as categoria,
      dep_omie.descricao as departamento,
      ROUND(
        (
          case 
            when cc.id_conta_corrente is not null or cp.status_titulo = 'PAGO' then
              -- Quando PAGO na Omie ou no Extrato bancario, extrai O VALOR EXACTO DO PAGAMENTO
              - ( COALESCE(cx.valor, COALESCE(cx.percentual, 100::numeric) / 100.0 * 
                  COALESCE(
                    (cp.json_bruto -> 'resumo' ->> 'nValPago')::numeric, 
                    (cp.json_bruto -> 'resumo' ->> 'nValBaixado')::numeric,
                    (cp.valor_documento + coalesce(cp.valor_juros,0) + coalesce(cp.valor_multa,0) - coalesce(cp.valor_desconto,0))
                  )
                ) )
            else
              -- Quando ABERTO (nao baixado), prevemos a parcela cheia ou o que restou (nValAberto)
              - ( COALESCE(cx.valor, COALESCE(cx.percentual, 100::numeric) / 100.0 * 
                  COALESCE(
                    NULLIF((cp.json_bruto -> 'resumo' ->> 'nValAberto')::numeric, 0),
                    cp.valor_documento
                  )
                ) )
          end
        ) * (
          COALESCE(dx."nPerDep", dx."nPerc", 100::numeric) / 100.0
        ), 
        2
      ) as valor_final,
      ROUND(
        - ( COALESCE(cx.percentual, 100::numeric) / 100.0 * cp.valor_documento )
        * ( COALESCE(dx."nPerDep", dx."nPerc", 100::numeric) / 100.0 ),
        2
      ) as valor_original,
      ROUND(
        - ( COALESCE(cx.percentual, 100::numeric) / 100.0 * COALESCE((cp.json_bruto -> 'resumo' ->> 'nValJuros')::numeric, cp.valor_juros, 0) )
        * ( COALESCE(dx."nPerDep", dx."nPerc", 100::numeric) / 100.0 ),
        2
      ) as valor_juros,
      ROUND(
        - ( COALESCE(cx.percentual, 100::numeric) / 100.0 * COALESCE((cp.json_bruto -> 'resumo' ->> 'nValMulta')::numeric, cp.valor_multa, 0) )
        * ( COALESCE(dx."nPerDep", dx."nPerc", 100::numeric) / 100.0 ),
        2
      ) as valor_multa,
      ROUND(
        ( COALESCE(cx.percentual, 100::numeric) / 100.0 * COALESCE((cp.json_bruto -> 'resumo' ->> 'nValDesconto')::numeric, cp.valor_desconto, 0) )
        * ( COALESCE(dx."nPerDep", dx."nPerc", 100::numeric) / 100.0 ),
        2
      ) as valor_desconto
    from
      contas_pagar cp
      left join (
        select
          conta_corrente.id_origem_pagar,
          conta_corrente.empresa_cnpj,
          max(conta_corrente.data_lancamento) as max_data_lancamento,
          max(conta_corrente.id_conta_corrente) as id_conta_corrente,
          max(conta_corrente.id_cliente_fornecedor) as id_cliente_fornecedor,
          max(conta_corrente.departamentos::text) as json_cc_departamentos
        from
          conta_corrente
        where
          conta_corrente.id_origem_pagar is not null
        group by
          conta_corrente.id_origem_pagar,
          conta_corrente.empresa_cnpj
      ) cc on cc.id_origem_pagar = cp.codigo_lancamento_omie
      and cc.empresa_cnpj = cp.empresa_cnpj::text
      left join lateral jsonb_to_recordset(
        case
          when jsonb_typeof(cp.categorias) = 'array'::text
          and jsonb_array_length(cp.categorias) > 0 then cp.categorias
          else jsonb_build_array(
            jsonb_build_object(
              'codigo_categoria',
              cp.codigo_categoria,
              'percentual',
              100,
              'valor',
              cp.valor_documento
            )
          )
        end
      ) cx (
        codigo_categoria text,
        percentual numeric,
        valor numeric
      ) on true
      left join lateral jsonb_to_recordset(
        case
          when cc.json_cc_departamentos is not null
          and jsonb_typeof(cc.json_cc_departamentos::jsonb) = 'array'::text
          and jsonb_array_length(cc.json_cc_departamentos::jsonb) > 0 then cc.json_cc_departamentos::jsonb
          when jsonb_typeof(cp.distribuicao::jsonb) = 'array'::text
          and jsonb_array_length(cp.distribuicao::jsonb) > 0 then cp.distribuicao::jsonb
          else jsonb_build_array(
            jsonb_build_object(
              'cCodDep',
              null::text,
              'nPerDep',
              100,
              'nPerc',
              100,
              'nValDep',
              null::numeric
            )
          )
        end
      ) dx (
        "cCodDep" text,
        "nPerDep" numeric,
        "nPerc" numeric,
        "nValDep" numeric
      ) on true
      left join ClientesUnicos cl on cl.codigo_cliente_omie = COALESCE(
        cp.codigo_cliente_fornecedor,
        cc.id_cliente_fornecedor
      )
      and cl.empresa_cnpj = cp.empresa_cnpj::text
      left join CategoriasUnicas cat on cat.codigo::text = cx.codigo_categoria
      and cat.empresa_cnpj = cp.empresa_cnpj::text
      left join DepartamentosUnicos dep_omie on dep_omie.codigo::text = dx."cCodDep"
      and dep_omie.empresa_cnpj = cp.empresa_cnpj::text
  ),
  base_cc as (
    select
      cc.empresa_nome,
      cc.empresa_cnpj,
      cl.cnpj_cpf as cnpj,
      COALESCE(
        cl.razao_social,
        'Lançamento Direto (Sem Favorecido)'::text
      ) as razao_social,
      cc.data_lancamento as data_vencimento,
      cc.data_lancamento as data_previsao,
      cc.data_lancamento,
      cc.codigo_lancamento as codigo_lancamento_omie,
      'PAGO (No Banco)'::text as status_titulo,
      cc.id_cliente_fornecedor as codigo_cliente_fornecedor,
      COALESCE(
        cat.descricao,
        'Despesa Bancária / Direta'::character varying
      ) as categoria,
      dep_omie.descricao as departamento,
      ROUND(
        (
          case
            when cc.natureza::text = 'P'::text then '-1'::integer
            else 1
          end::numeric * COALESCE(cx."nValCateg", abs(cc.valor))
        ) * (
          COALESCE(dx."nPerDep", dx."nPerc", 100::numeric) / 100.0
        ), 
        2
      ) as valor_final,
      ROUND(
        (
          case
            when cc.natureza::text = 'P'::text then '-1'::integer
            else 1
          end::numeric * COALESCE(cx."nValCateg", abs(cc.valor))
        ) * (
          COALESCE(dx."nPerDep", dx."nPerc", 100::numeric) / 100.0
        ), 
        2
      ) as valor_original,
      0::numeric as valor_juros,
      0::numeric as valor_multa,
      0::numeric as valor_desconto
    from
      conta_corrente cc
      left join lateral jsonb_to_recordset(
        case
          when jsonb_typeof(cc.categorias) = 'array'::text
          and jsonb_array_length(cc.categorias) > 0 then cc.categorias
          else jsonb_build_array(
            jsonb_build_object(
              'cCodCateg',
              cc.codigo_categoria,
              'nValCateg',
              abs(cc.valor)
            )
          )
        end
      ) cx ("cCodCateg" text, "nValCateg" numeric) on true
      left join lateral jsonb_to_recordset(
        case
          when jsonb_typeof(cc.departamentos) = 'array'::text
          and jsonb_array_length(cc.departamentos) > 0 then cc.departamentos
          else jsonb_build_array(
            jsonb_build_object(
              'cCodDep',
              null::text,
              'nPerDep',
              100,
              'nPerc',
              100,
              'nValDep',
              null::numeric
            )
          )
        end
      ) dx (
        "cCodDep" text,
        "nPerDep" numeric,
        "nPerc" numeric,
        "nValDep" numeric
      ) on true
      left join ClientesUnicos cl on cl.codigo_cliente_omie = cc.id_cliente_fornecedor
      and cl.empresa_cnpj = cc.empresa_cnpj
      left join CategoriasUnicas cat on cat.codigo::text = cx."cCodCateg"
      and cat.empresa_cnpj = cc.empresa_cnpj
      left join DepartamentosUnicos dep_omie on dep_omie.codigo::text = dx."cCodDep"
      and dep_omie.empresa_cnpj = cc.empresa_cnpj
    where
      cc.id_origem_pagar is null
      and (cc.id_origem_receber is null or cc.natureza::text = 'P'::text)
  )
select
  base_cp.empresa_nome,
  base_cp.empresa_cnpj,
  base_cp.cnpj,
  base_cp.razao_social,
  base_cp.data_vencimento,
  base_cp.data_previsao,
  base_cp.data_lancamento,
  base_cp.codigo_lancamento_omie,
  base_cp.status_titulo,
  base_cp.codigo_cliente_fornecedor,
  base_cp.categoria,
  base_cp.departamento,
  base_cp.valor_final,
  base_cp.valor_original,
  base_cp.valor_juros,
  base_cp.valor_multa,
  base_cp.valor_desconto
from
  base_cp
union all
select
  base_cc.empresa_nome,
  base_cc.empresa_cnpj,
  base_cc.cnpj,
  base_cc.razao_social,
  base_cc.data_vencimento,
  base_cc.data_previsao,
  base_cc.data_lancamento,
  base_cc.codigo_lancamento_omie,
  base_cc.status_titulo,
  base_cc.codigo_cliente_fornecedor,
  base_cc.categoria,
  base_cc.departamento,
  base_cc.valor_final,
  base_cc.valor_original,
  base_cc.valor_juros,
  base_cc.valor_multa,
  base_cc.valor_desconto
from
  base_cc;
"""

headers = {'apikey': key, 'Authorization': f'Bearer {key}', 'Content-Type': 'application/json'}
resp = requests.post(f'{url}/rest/v1/rpc/exec_sql', headers=headers, json={'query': sql})
print(resp.status_code)
print(resp.text)
