CREATE OR REPLACE VIEW public.painel_contas_pagar AS
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
  base_cp_raw as (
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
        when cc.id_origem_pagar is not null then 'PAGO (No Banco)'::character varying
        else cp.status_titulo
      end as status_titulo,
      COALESCE(
        cp.codigo_cliente_fornecedor,
        cc.id_cliente_fornecedor
      ) as codigo_cliente_fornecedor,
      cat.descricao as categoria,
      dep_omie.descricao as departamento,
      
      case when REGEXP_REPLACE(cl.cnpj_cpf, '\D', '', 'g') = any (
          array[
            '12340921000182'::text, '62700834000167'::text, '44158057000199'::text, '01501108000120'::text, '23382154000190'::text,
            '42622192000118'::text, '56378880000199'::text, '36657397000136'::text, '39287808000137'::text, '36480461000156'::text,
            '27057563000172'::text, '36530240000145'::text, '39484812000195'::text, '37852789000119'::text, '42380661000130'::text,
            '14723195000102'::text, '34349108000106'::text, '42275720000100'::text, '08865854000142'::text, '36685910000100'::text,
            '47244267053'::text, '57341084000144'::text, '23448109000191'::text, '11863345000195'::text, '39349860000170'::text,
            '58420510000106'::text, '48552493000107'::text, '44189727000134'::text, '53192862000120'::text
          ]
      ) then true else false end as is_intercompany,

      -- Helper columns for logic
      COALESCE(cx.percentual, 100::numeric) / 100.0 as pct_cat,
      COALESCE(dx."nPerDep", dx."nPerc", (dx."nValDep" / NULLIF(cp.valor_documento, 0)) * 100, 100::numeric) / 100.0 as pct_dep,
      cc.soma_valor_banco,
      case 
        when (jsonb_typeof(cp.categorias) = 'array' and jsonb_array_length(cp.categorias) > 1)
          or (jsonb_typeof(cp.distribuicao::jsonb) = 'array' and jsonb_array_length(cp.distribuicao::jsonb) > 1)
        then true else false 
      end as tem_rateio,
      case 
        when cc.soma_valor_banco > (cp.valor_documento * 1.2) then true 
        else false 
      end as is_lote,

      ROUND(
        - ( COALESCE(cx.percentual, 100::numeric) / 100.0 * cp.valor_documento )
        * ( COALESCE(dx."nPerDep", dx."nPerc", (dx."nValDep" / NULLIF(cp.valor_documento, 0)) * 100, 100::numeric) / 100.0 ),
        2
      ) as valor_original,
      ROUND(
        - ( COALESCE(cx.percentual, 100::numeric) / 100.0 * 
            COALESCE(
              NULLIF((cp.json_bruto -> 'resumo' ->> 'nValJuros')::numeric, 0), 
              NULLIF((cp.json_bruto -> 'lista_recibos' -> 0 ->> 'nValJuros')::numeric, 0),
              NULLIF((cp.json_bruto -> 'titulos_baixados' -> 0 ->> 'nValJuros')::numeric, 0),
              NULLIF(cp.valor_juros, 0), 
              0 
            )
          )
        * ( COALESCE(dx."nPerDep", dx."nPerc", (dx."nValDep" / NULLIF(cp.valor_documento, 0)) * 100, 100::numeric) / 100.0 ),
        2
      ) as valor_juros,
      ROUND(
        - ( COALESCE(cx.percentual, 100::numeric) / 100.0 * 
            COALESCE(
              NULLIF((cp.json_bruto -> 'resumo' ->> 'nValMulta')::numeric, 0), 
              NULLIF((cp.json_bruto -> 'lista_recibos' -> 0 ->> 'nValMulta')::numeric, 0),
              NULLIF((cp.json_bruto -> 'titulos_baixados' -> 0 ->> 'nValMulta')::numeric, 0),
              NULLIF(cp.valor_multa, 0), 
              0 
            )
          )
        * ( COALESCE(dx."nPerDep", dx."nPerc", (dx."nValDep" / NULLIF(cp.valor_documento, 0)) * 100, 100::numeric) / 100.0 ),
        2
      ) as valor_multa,
      ROUND(
        ( COALESCE(cx.percentual, 100::numeric) / 100.0 * 
            COALESCE(
              NULLIF((cp.json_bruto -> 'resumo' ->> 'nValDesconto')::numeric, 0), 
              NULLIF((cp.json_bruto -> 'lista_recibos' -> 0 ->> 'nValDesconto')::numeric, 0),
              NULLIF((cp.json_bruto -> 'titulos_baixados' -> 0 ->> 'nValDesconto')::numeric, 0),
              NULLIF(cp.valor_desconto, 0), 
              0
            )
        )
        * ( COALESCE(dx."nPerDep", dx."nPerc", (dx."nValDep" / NULLIF(cp.valor_documento, 0)) * 100, 100::numeric) / 100.0 ),
        2
      ) as valor_desconto
    from
      contas_pagar cp
      left join (
        select
          conta_corrente.id_origem_pagar,
          conta_corrente.empresa_cnpj,
          max(conta_corrente.data_lancamento) as max_data_lancamento,
          max(conta_corrente.id_cliente_fornecedor) as id_cliente_fornecedor,
          sum(abs(conta_corrente.valor)) as soma_valor_banco
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
  base_cp as (
    select 
      empresa_nome,
      empresa_cnpj,
      cnpj,
      razao_social,
      data_vencimento,
      data_previsao,
      data_lancamento,
      codigo_lancamento_omie,
      status_titulo,
      codigo_cliente_fornecedor,
      categoria,
      departamento,
      is_intercompany,
      case
        when status_titulo = 'PAGO' or status_titulo = 'PAGO (No Banco)' then
          case
            -- Se for pagamento em lote e possuir rateio, usa o valor do documento CP
            when tem_rateio = true and is_lote = true then
              valor_original + valor_juros + valor_multa + valor_desconto
            -- Caso contrário (sem rateio ou pagamento individual), usa a soma da CC
            else
              ROUND( - (COALESCE(soma_valor_banco, abs(valor_original + valor_juros + valor_multa + valor_desconto))) * pct_cat * pct_dep, 2)
          end
        else
          valor_original
      end as valor_final,
      case
        when status_titulo = 'PAGO' or status_titulo = 'PAGO (No Banco)' then
          case
            when tem_rateio = true and is_lote = true then
              valor_original + valor_juros + valor_multa + valor_desconto
            else
              ROUND( - (COALESCE(soma_valor_banco, abs(valor_original + valor_juros + valor_multa + valor_desconto))) * pct_cat * pct_dep, 2)
          end
        else
          0::numeric
      end as valor_pago,
      valor_original,
      valor_juros,
      valor_multa,
      valor_desconto
    from base_cp_raw
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
      case when REGEXP_REPLACE(cl.cnpj_cpf, '\D', '', 'g') = any (
          array[
            '12340921000182'::text, '62700834000167'::text, '44158057000199'::text, '01501108000120'::text, '23382154000190'::text,
            '42622192000118'::text, '56378880000199'::text, '36657397000136'::text, '39287808000137'::text, '36480461000156'::text,
            '27057563000172'::text, '36530240000145'::text, '39484812000195'::text, '37852789000119'::text, '42380661000130'::text,
            '14723195000102'::text, '34349108000106'::text, '42275720000100'::text, '08865854000142'::text, '36685910000100'::text,
            '47244267053'::text, '57341084000144'::text, '23448109000191'::text, '11863345000195'::text, '39349860000170'::text,
            '58420510000106'::text, '48552493000107'::text, '44189727000134'::text, '53192862000120'::text
          ]
      ) then true else false end as is_intercompany,
      ROUND(
        (
          case
            when cc.natureza::text IN ('P', 'S', 'D') then '-1'::integer
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
            when cc.natureza::text IN ('P', 'S', 'D') then '-1'::integer
            else 1
          end::numeric * COALESCE(cx."nValCateg", abs(cc.valor))
        ) * (
          COALESCE(dx."nPerDep", dx."nPerc", 100::numeric) / 100.0
        ), 
        2
      ) as valor_pago,
      ROUND(
        (
          case
            when cc.natureza::text IN ('P', 'S', 'D') then '-1'::integer
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
      and (cc.id_origem_receber is null or cc.natureza::text IN ('P', 'S', 'D'))
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
  base_cp.is_intercompany,
  base_cp.valor_final,
  base_cp.valor_pago,
  base_cp.valor_original,
  base_cp.valor_juros,
  base_cp.valor_multa,
  base_cp.valor_desconto
from
  base_cp
where base_cp.valor_final <= 0
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
  base_cc.is_intercompany,
  base_cc.valor_final,
  base_cc.valor_pago,
  base_cc.valor_original,
  base_cc.valor_juros,
  base_cc.valor_multa,
  base_cc.valor_desconto
from
  base_cc
where base_cc.valor_final <= 0;
