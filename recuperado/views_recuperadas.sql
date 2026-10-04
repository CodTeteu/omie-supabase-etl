-- =============================================================================
-- VIEWS RECUPERADAS DO BANCO PERDIDO
--
-- Origem: historico git de chrislopes2/omie-supabase-etl, arquivo
-- fix_supabase.sql, commit af5b3c2 (depois revertido e removido do repo).
--
-- Recuperado em 04/10/2026. Sao as views do proprio Supabase do ETL,
-- portanto compativeis com o schema atual sem adaptacao: referenciam
-- apenas categorias_omie, clientes_grupo, conta_corrente, contas_pagar,
-- contas_receber_grupo, departamentos_omie e movimentos_financeiros.
--
-- Os DROP sao apenas de views (IF EXISTS / CASCADE) e os ALTER TABLE
-- para bigint ja estao aplicados no schema atual - sao inocuos.
--
-- Views contidas: vw_contas_receber_detalhada, view_contas_receber,
-- view_contas_pagar, view_faturamento_rateado, view_inadimplencia, metas.
-- =============================================================================

-- 1. Excluindo TODAS as views conflitantes em cascata
DROP VIEW IF EXISTS public.view_faturamento_rateado CASCADE;
DROP VIEW IF EXISTS public.metas CASCADE;
DROP VIEW IF EXISTS public.view_inadimplencia CASCADE;
DROP VIEW IF EXISTS public.view_contas_receber CASCADE;
DROP VIEW IF EXISTS public.view_contas_pagar CASCADE;
DROP VIEW IF EXISTS public.vw_contas_receber_detalhada CASCADE;

-- 2. Alterando o limite do numero do cliente para suportar bigints
ALTER TABLE public.clientes_grupo ALTER COLUMN codigo_cliente_omie TYPE bigint;
ALTER TABLE public.contas_receber_grupo ALTER COLUMN codigo_cliente_fornecedor TYPE bigint;
ALTER TABLE public.contas_pagar ALTER COLUMN codigo_cliente_fornecedor TYPE bigint;

-- 3. Recriando as Views

-- Recriando vw_contas_receber_detalhada
CREATE OR REPLACE VIEW public.vw_contas_receber_detalhada AS 
 SELECT cr.empresa_cnpj,
    cr.empresa_nome,
    cr.codigo_lancamento_omie,
    cr.codigo_cliente_fornecedor,
    cr.numero_documento,
    cr.data_emissao,
    cr.data_vencimento,
    cr.valor_documento,
    cr.status_titulo,
    cr.codigo_categoria,
    (d.value ->> 'cCodDep'::text) AS dist_departamento_id,
    (d.value ->> 'cDesDep'::text) AS dist_departamento_nome,
    ((d.value ->> 'nValDep'::text))::numeric AS dist_valor,
    ((d.value ->> 'nPerDep'::text))::numeric AS dist_porcentagem
   FROM (contas_receber_grupo cr
     LEFT JOIN LATERAL json_array_elements(
        CASE
            WHEN (json_typeof(cr.distribuicao) = 'string'::text) THEN ((cr.distribuicao #>> '{}'::text[]))::json
            WHEN (json_typeof(cr.distribuicao) = 'array'::text) THEN cr.distribuicao
            ELSE '[]'::json
        END) d(value) ON (true));

-- Recriando view_contas_receber
CREATE OR REPLACE VIEW public.view_contas_receber AS 
 SELECT (row_number() OVER ())::integer AS id,
    cr.codigo_lancamento_omie,
    NULL::text AS codigo_lancamento_integracao,
    cr.codigo_cliente_fornecedor AS codigo_cliente_omie,
    cg.cnpj_cpf,
    cg.razao_social,
    cg.nome_fantasia,
    NULL::text AS tags,
    (cr.data_emissao)::text AS data_emissao,
    (cr.data_vencimento)::text AS data_vencimento,
    NULL::text AS data_conciliacao,
    NULL::text AS data_inclusao,
    NULL::text AS data_lancamento,
    NULL::numeric AS valor_conta_corrente,
    cr.numero_documento,
    NULL::text AS numero_parcela,
    cr.status_titulo,
    NULL::numeric AS valor_pis,
    NULL::numeric AS valor_cofins,
    NULL::numeric AS valor_csll,
    NULL::numeric AS valor_ir,
    NULL::numeric AS valor_iss,
    NULL::numeric AS valor_inss,
    cr.valor_documento AS valor_contas_receber,
    NULL::text AS boleto,
    cr.codigo_categoria AS codigo,
    cat.descricao,
    (cat.bandeiras)::text AS bandeira,
    NULL::bigint AS codigo_lancamento_conta_corrente,
    NULL::text AS situacao,
    NULL::text AS data_previsao,
    NULL::text AS departamentos
   FROM ((contas_receber_grupo cr
     LEFT JOIN clientes_grupo cg ON ((cg.codigo_cliente_omie = cr.codigo_cliente_fornecedor)))
     LEFT JOIN categorias_omie cat ON ((((cat.codigo)::text = cr.codigo_categoria) AND (cat.empresa_cnpj = cr.empresa_cnpj))));

-- Recriando view_contas_pagar
CREATE OR REPLACE VIEW public.view_contas_pagar AS 

select
  row_number() over (
    order by
      cp.codigo_lancamento_omie
  ) as id,
  cp.empresa_nome as bandeira,
  cp.bandeira_id,
  COALESCE(cl.cnpj_cpf, cp.empresa_cnpj::text) as cnpj_cpf,
  COALESCE(cl.razao_social, cp.empresa_nome::text) as razao_social,
  cp.codigo_categoria as codigo,
  COALESCE(
    cp.data_registro,
    cp.data_emissao,
    cp.data_entrada
  ) as data_lancamento,
  cp.data_vencimento,
  cp.data_entrada as data_pagamento,
  cat.descricao as descricao_cat,
  (cp.distribuicao -> 0) ->> 'cCodDep'::text as ccoddep,
  (cp.distribuicao -> 0) ->> 'cDesDep'::text as descricao_dept,
  round(cp.valor_documento, 2) as valor_num,
  replace(
    round(cp.valor_documento, 2)::text,
    '.'::text,
    ','::text
  ) as valor,
  cp.status_titulo
from
  contas_pagar cp
  left join categorias_omie cat on cat.codigo::text = cp.codigo_categoria::text
  and cat.empresa_cnpj = cp.empresa_cnpj::text
  left join clientes_grupo cl on cl.codigo_cliente_omie = cp.codigo_cliente_fornecedor
  and cl.empresa_cnpj = cp.empresa_cnpj::text;


-- Recriando view_faturamento_rateado
CREATE OR REPLACE VIEW public.view_faturamento_rateado AS 
 WITH contas_receber_sb AS (
         SELECT cr.codigo_lancamento_omie,
            cr.empresa_nome AS bandeira_nome,
            cr.empresa_cnpj,
            cr.codigo_cliente_fornecedor,
            cr.data_emissao,
            cr.data_vencimento,
            cr.valor_documento,
            cr.numero_documento,
            cr.codigo_categoria,
            cr.status_titulo,
            cr.categorias,
            cc.departamentos,
            cc.data_lancamento,
            oc.cnpj_cpf,
            oc.razao_social,
            COALESCE((cat.elem ->> 'codigo_categoria'::text), cr.codigo_categoria) AS codigo_categoria_expl,
            COALESCE(((cat.elem ->> 'percentual'::text))::numeric, (100)::numeric) AS percentual_categoria,
            COALESCE(cc.valor, (0)::numeric) AS valor_conta
           FROM (((contas_receber_grupo cr
             LEFT JOIN conta_corrente cc ON (((cr.codigo_lancamento_omie = cc.id_origem_receber) AND (cr.empresa_cnpj = cc.empresa_cnpj))))
             LEFT JOIN clientes_grupo oc ON (((cr.codigo_cliente_fornecedor = oc.codigo_cliente_omie) AND (cr.empresa_cnpj = oc.empresa_cnpj))))
             LEFT JOIN LATERAL ( SELECT elem.value AS elem
                   FROM jsonb_array_elements(
                        CASE
                            WHEN ((cr.categorias IS NOT NULL) AND (jsonb_typeof(cr.categorias) = 'array'::text) AND (jsonb_array_length(cr.categorias) > 0)) THEN cr.categorias
                            ELSE '[{}]'::jsonb
                        END) elem(value)) cat ON (true))
        ), abrindo_valores AS (
         SELECT cr.codigo_lancamento_omie,
            cr.data_emissao,
            cr.data_lancamento,
            cr.data_vencimento,
            cr.empresa_cnpj,
            cr.bandeira_nome AS bandeira,
            cr.cnpj_cpf,
            cr.razao_social,
            cr.codigo_categoria_expl,
            cr.percentual_categoria,
            co.descricao AS descricao_cat,
            cr.valor_conta,
            (dep.elem ->> 'cCodDep'::text) AS ccoddep,
            ((dep.elem ->> 'nPerDep'::text))::numeric AS percentual_departamento
           FROM ((contas_receber_sb cr
             LEFT JOIN categorias_omie co ON ((((co.codigo)::text = cr.codigo_categoria_expl) AND (co.empresa_cnpj = cr.empresa_cnpj))))
             LEFT JOIN LATERAL ( SELECT elem.value AS elem
                   FROM jsonb_array_elements(
                        CASE
                            WHEN ((cr.departamentos IS NOT NULL) AND (jsonb_typeof(cr.departamentos) = 'array'::text) AND (jsonb_array_length(cr.departamentos) > 0)) THEN cr.departamentos
                            ELSE '[{}]'::jsonb
                        END) elem(value)) dep ON (true))
        ), agrupando_valores AS (
         SELECT av.codigo_lancamento_omie,
            av.data_emissao,
            av.data_lancamento,
            av.data_vencimento,
            av.empresa_cnpj,
            av.bandeira,
            av.cnpj_cpf,
            av.razao_social,
            av.codigo_categoria_expl,
            av.percentual_categoria,
            av.descricao_cat,
            sum(av.valor_conta) AS valor_conta,
            av.ccoddep,
            av.percentual_departamento
           FROM abrindo_valores av
          GROUP BY av.codigo_lancamento_omie, av.data_emissao, av.data_lancamento, av.data_vencimento, av.empresa_cnpj, av.bandeira, av.cnpj_cpf, av.razao_social, av.codigo_categoria_expl, av.percentual_categoria, av.descricao_cat, av.ccoddep, av.percentual_departamento
        ), departamentos AS (
         SELECT av.codigo_lancamento_omie,
            av.data_emissao,
            av.data_lancamento,
            av.data_vencimento,
            av.bandeira,
            av.cnpj_cpf,
            av.razao_social,
            av.descricao_cat,
            av.percentual_categoria,
            av.ccoddep,
            av.percentual_departamento,
            d.descricao AS descricao_dept,
            ((av.valor_conta * (av.percentual_departamento / (100)::numeric)) * (av.percentual_categoria / (100)::numeric)) AS valor_cat_dept
           FROM (agrupando_valores av
             LEFT JOIN departamentos_omie d ON ((((d.codigo)::text = av.ccoddep) AND (d.empresa_cnpj = av.empresa_cnpj))))
          WHERE (av.ccoddep IS NOT NULL)
        ), sem_departamento AS (
         SELECT av.codigo_lancamento_omie,
            av.data_emissao,
            av.data_lancamento,
            av.data_vencimento,
            av.bandeira,
            av.cnpj_cpf,
            av.razao_social,
            av.descricao_cat,
            av.percentual_categoria,
            NULL::text AS ccoddep,
            NULL::numeric AS percentual_departamento,
            NULL::text AS descricao_dept,
            av.valor_conta
           FROM abrindo_valores av
          WHERE (NOT (av.codigo_lancamento_omie IN ( SELECT DISTINCT departamentos.codigo_lancamento_omie
                   FROM departamentos)))
        ), agrupando AS (
         SELECT d.codigo_lancamento_omie,
            d.data_emissao,
            d.data_lancamento,
            d.data_vencimento,
            d.bandeira,
            d.cnpj_cpf,
            d.razao_social,
            d.descricao_cat,
            d.percentual_categoria,
            d.ccoddep,
            d.percentual_departamento,
            d.descricao_dept,
            d.valor_cat_dept
           FROM departamentos d
        UNION ALL
         SELECT sd.codigo_lancamento_omie,
            sd.data_emissao,
            sd.data_lancamento,
            sd.data_vencimento,
            sd.bandeira,
            sd.cnpj_cpf,
            sd.razao_social,
            sd.descricao_cat,
            sd.percentual_categoria,
            sd.ccoddep,
            sd.percentual_departamento,
            sd.descricao_dept,
            sd.valor_conta
           FROM sem_departamento sd
        ), classificando AS (
         SELECT a.codigo_lancamento_omie,
            a.data_emissao,
            a.data_lancamento,
            a.data_vencimento,
            a.bandeira,
            a.cnpj_cpf,
            a.razao_social,
            a.descricao_cat,
            a.percentual_categoria,
            a.ccoddep,
            a.percentual_departamento,
            a.descricao_dept,
            a.valor_cat_dept,
                CASE
                    WHEN ((TRIM(BOTH FROM upper((a.descricao_cat)::text)) ~~ '%RECEITA DE CONTABILIDADE RECORRENTE%'::text) OR (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE MERCADO LIVRE DE ENERGIA'::text]))) THEN 'CORPORATE'::text
                    WHEN (a.cnpj_cpf = ANY (ARRAY['12340921000182'::text, '62700834000167'::text, '44158057000199'::text, '01501108000120'::text, '23382154000190'::text, '42622192000118'::text, '56378880000199'::text, '36657397000136'::text, '39287808000137'::text, '36480461000156'::text, '27057563000172'::text, '36530240000145'::text, '39484812000195'::text, '37852789000119'::text, '42380661000130'::text, '14723195000102'::text, '34349108000106'::text, '42275720000100'::text, '08865854000142'::text, '36685910000100'::text, '47244267053'::text, '57341084000144'::text, '23448109000191'::text, '11863345000195'::text, '39349860000170'::text, '58420510000106'::text, '48552493000107'::text, '44189727000134'::text, '53192862000120'::text])) THEN 'INTER COMPANY'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['TAXAS DE FRANQUIA/ALIANÇA'::text, 'ROYALTIES/CRM'::text, 'RECEITA DE ROYALTIES/CRM'::text, 'ROYALTIES VARIÁVEIS'::text, 'RECEITA DE ROYALTIES VARIÁVEIS'::text, 'ROYALTIES ANTECIPADO'::text, 'RECEITA DE ROYALTIES ANTECIPADOS'::text, 'RECEITA DE ROYALTIES'::text, 'FRANCHISING - ROYALTIES'::text, 'RECEITA DE CRM'::text, 'FRANCHISING - CRM'::text])) THEN 'FRANCHISING'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE TAXAS DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE ROYALTIES ANTECIPADO'::text, 'RECEITA DE TREINAMENTO INTERNO'::text, 'EXPANSÃO - TAXA DE LICENCIAMENTO'::text, 'RECEITA DE TAXA DE FRANQUIA/ALIANÇA'::text, 'EXPANSÃO - TAXA DE FRANQUIA'::text, 'RECEITA DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE IMPLANTAÇÃO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS PJ360'::text])) THEN 'EXPANSÃO'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE TREINAMENTO EXTERNO'::text, 'RECEITA DE TREINAMENTOS'::text])) THEN 'EDUCAÇÃO'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE SERVIÇOS JURÍDICOS'::text, 'RECEITA DE RESTITUIÇÃO'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRI'::text, 'RECEITA DE RETIFICAÇÃO'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LOW)'::text, 'RECEITA DE TESES TRIBUTÁRIAS'::text, 'RECEITA DE TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE PRT'::text, 'RECEITA DE PROJETOS ESPECIAIS'::text, 'RECEITA DE TESES'::text, 'RECEITA DE PONTOS QUALIFICADOS'::text, 'RECEITA DE OPERAÇÃO DE JOBS (ÊXITO)'::text, 'CLIENTES - TRIBUTÁRIO'::text, 'CLIENTES - TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE COMPENSAÇÃO'::text, 'RECEITA DE PONTO QUALIFICADOS'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRIA'::text, 'RECEITA DE MAPA FISCAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LAW)'::text, 'RECEITA DE GESTÃO DO PASSIVO TRIBUTÁRIO'::text, 'RECEITA DE AJE - ASSESSORIA JURÍDICA EMPRESARIAL'::text, 'RECEITA DE LIQUIDAÇÃO'::text, 'RECEITA DE AJUIZAMENTO'::text, 'RECEITA DE AJUIZAMENTOS TRIBUTÁRIOS'::text, 'RECEITA DE LIQUIDAÇÃO TRIBUTÁRIO'::text, 'CLIENTES - INTERMEDIAÇÕES DE NEGÓCIOS (JOBS)'::text])) THEN 'TAX'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DA SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OFFSHORE'::text, 'RECEITA DE CONSULTORIA ESTRATÉGICA'::text, 'RECEITA DE AJUIZAMENTOS CÍVEIS'::text, 'RECEITA DE GESTÃO DE CARTEIRA DE INVESTIMENTOS'::text, 'RECEITA DE RENEGOCIAÇÃO DE DÍVIDAS'::text, 'RECEITA DE FINANCIAMENTO DE FRANQUIA'::text, 'RECEITA DE FINANCIAMENTO DE FRANQUIA'::text, 'RECEITA DE HOLDING GOVERNANÇA'::text, 'RECEITA DE ASSESSORIA JURÍDICA MENSAL'::text, 'ASSESSORIA JURÍDICA MENSAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OPERAÇÃO DE JOBS (RECORRENTE)'::text, 'RECEITA DE OPERAÇÃO DE JOBS - SPACEW'::text, 'RECEITA DE OPERAÇÃO DE JOBS - AGRO'::text, 'RECEITA DE OPERAÇÃO DE JOBS'::text, 'RECEITA DE MERCADO LIVRE'::text, 'RECEITA DE HOLDING'::text, 'RECEITA DA SERVIÇOS JURÍDICOS'::text, 'CLIENTES - HOLDING'::text, 'RECEITA DE CESSÃO/NEGOCIAÇÃO DE PRECATÓRIOS'::text, 'RECEITA DE OPERAÇÃO DE JOB'::text, 'RECEITA DE CAPTAÇÃO DE RECURSOS'::text, 'RECEITA DE SEGUROS'::text, 'RECEITA DE MEA'::text, 'BPO FINANCEIRO'::text, 'RECEITA DE VALUATION'::text, 'RECEITA DE ASSINATURA DE ENERGIA'::text, 'RECEITA DE ENERGY GERAÇÃO - GD'::text, 'RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE SERVIÇOS CONTÁBEIS'::text, 'RECEITA DE HOLDING ITBI'::text, 'RECEITA DE SERVIÇOS JURIDICOS'::text, 'RECEITA DE AVALIAÇÃO PATRIMONIAL'::text, 'RECEITA DE ENERGY ASSESSORIA - RCE'::text, 'RECEITA DE FINANCIAMENTO - AMORTIZAÇÃO DE CRÉDITO'::text])) THEN 'CORPORATE'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE SUPORTE E CONSULTORIA EM TI'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITACARD'::text, 'CLIENTES - LOCAÇÃO DE EQUIPAMENTOS E SUPORTE TI'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS GS'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS EXTERNO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITATAX'::text, 'RECEITA AUDITACARD'::text])) THEN 'TECNOLOGIA'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['SERVIÇOS ADMINISTRATIVOS'::text, 'REPASSE'::text, 'REEMBOLSO DE DESPESAS'::text, 'RECEITA IMPRESSÕES'::text, 'RECEITA IMPORTAÇÃO FINANCEIRO GS'::text, 'RECEITA DE MARKETING'::text, 'RECEITA DE LOJA'::text, 'RECEITA A IDENTIFICAR'::text, 'PRODUTOS/LOJA'::text, 'DISTRIBUIÇÃO DE LUCROS'::text, 'DEVOLUÇÃO PAGAMENTO EFETUADO'::text, 'DEVOLUÇÃO DE SERVIÇO PRESTADO'::text, 'DEVOLUÇÃO DE PAGAMENTO FEITO'::text, 'DEVOLUÇÃO DE PAGAMENTOS FEITOS'::text, 'APLICAÇÃO PARA EMPRÉSTIMOS'::text, '<DISPONÍVEL>'::text, 'RENDIMENTO DE APLICAÇÃO FINANCEIRA'::text, 'RECEITA DE VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text, 'RECEITA DHO'::text, 'VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text])) THEN 'OUTRAS RECEITAS'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE TRANSFERÊNCIA ENTRE EMPRESAS DO GRUPO'::text, 'APORTE DE CAPITAL'::text, 'RECEITA DE EMPRÉSTIMOS ENTRE EMPRESAS'::text, 'TRANSFERÊNCIA ENTRE CONTAS'::text])) THEN 'INTER COMPANY'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE LOCAÇÃO DE ESPAÇO E ESTACIONAMENTO'::text, 'RECEITA DE LOCAÇÃO DE ESPAÇO'::text, 'RECEITA DE ESTACIONAMENTO'::text, 'RECEITA DE COWORKING'::text])) THEN 'ADMINISTRAÇÃO'::text
                    ELSE 'SEM CATEGORIA'::text
                END AS categoria
           FROM agrupando a
          WHERE (a.data_lancamento >= '2026-01-01'::date)
        )
 SELECT row_number() OVER () AS id,
    codigo_lancamento_omie,
    data_emissao,
    data_lancamento,
    data_vencimento,
    bandeira,
    cnpj_cpf,
    razao_social,
    descricao_cat,
    percentual_categoria,
    ccoddep,
    percentual_departamento,
    descricao_dept,
    round(valor_cat_dept, 2) AS valor_conta,
    categoria
   FROM classificando c;

-- Recriando view_inadimplencia
CREATE OR REPLACE VIEW public.view_inadimplencia AS 
 WITH base_mf AS (
         SELECT mf.id_movimento AS codigo_lancamento_omie,
            mf.empresa_cnpj AS bandeira,
            mf.empresa_nome AS nome,
            mf.categoria_codigo AS codigo_categoria,
            mf.numero_titulo AS numero_documento,
            mf.cpf_cnpj AS cnpj_cpf,
            oc.razao_social,
            mf.data_vencimento,
            mf.data_emissao,
            COALESCE(mf.data_previsao, mf.data_vencimento) AS data_previsao,
            mf.valor_titulo AS valor_documento,
            mf.valor_pago,
            mf.valor_desconto,
            mf.valor_aberto AS inadimplencia,
            co.descricao AS descricao_categoria
           FROM ((movimentos_financeiros mf
             LEFT JOIN clientes_grupo oc ON (((oc.codigo_cliente_omie = mf.id_cliente_fornecedor) AND (oc.empresa_cnpj = (mf.empresa_cnpj)::text))))
             LEFT JOIN categorias_omie co ON ((((co.codigo)::text = (mf.categoria_codigo)::text) AND (co.empresa_cnpj = (mf.empresa_cnpj)::text))))
          WHERE (((mf.natureza)::text = 'R'::text) AND (mf.data_vencimento >= '2010-01-01'::date) AND (mf.data_vencimento <= '2035-01-01'::date) AND ((mf.status)::text <> 'CANCELADO'::text) AND ((mf.cstatus)::text <> 'CANCELADO'::text) AND (NOT ((mf.cpf_cnpj)::text IN ( SELECT DISTINCT movimentos_financeiros.empresa_cnpj
                   FROM movimentos_financeiros
                  WHERE (movimentos_financeiros.empresa_cnpj IS NOT NULL)))))
        )
 SELECT row_number() OVER () AS id,
    codigo_lancamento_omie,
    bandeira,
    nome,
    codigo_categoria,
    descricao_categoria,
    numero_documento,
    cnpj_cpf,
    razao_social,
    data_vencimento,
    data_emissao,
    data_previsao,
    valor_documento,
    valor_pago,
    valor_desconto,
    inadimplencia,
        CASE
            WHEN ((TRIM(BOTH FROM upper((descricao_categoria)::text)) ~~ '%RECEITA DE CONTABILIDADE RECORRENTE%'::text) OR (upper((descricao_categoria)::text) = ANY (ARRAY['RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE MERCADO LIVRE DE ENERGIA'::text]))) THEN 'CORPORATE'::text
            WHEN ((cnpj_cpf)::text = ANY (ARRAY['12340921000182'::text, '62700834000167'::text, '44158057000199'::text, '01501108000120'::text, '23382154000190'::text, '42622192000118'::text, '56378880000199'::text, '36657397000136'::text, '39287808000137'::text, '36480461000156'::text, '27057563000172'::text, '36530240000145'::text, '39484812000195'::text, '37852789000119'::text, '42380661000130'::text, '14723195000102'::text, '34349108000106'::text, '42275720000100'::text, '08865854000142'::text, '36685910000100'::text, '47244267053'::text, '57341084000144'::text, '23448109000191'::text, '11863345000195'::text, '39349860000170'::text, '58420510000106'::text, '48552493000107'::text, '44189727000134'::text, '53192862000120'::text])) THEN 'INTER COMPANY'::text
            WHEN (upper((descricao_categoria)::text) = ANY (ARRAY['TAXAS DE FRANQUIA/ALIANÇA'::text, 'ROYALTIES/CRM'::text, 'RECEITA DE ROYALTIES/CRM'::text, 'ROYALTIES VARIÁVEIS'::text, 'RECEITA DE ROYALTIES VARIÁVEIS'::text, 'ROYALTIES ANTECIPADO'::text, 'RECEITA DE ROYALTIES ANTECIPADOS'::text, 'RECEITA DE ROYALTIES'::text, 'FRANCHISING - ROYALTIES'::text, 'RECEITA DE CRM'::text, 'FRANCHISING - CRM'::text])) THEN 'FRANCHISING'::text
            WHEN (upper((descricao_categoria)::text) = ANY (ARRAY['RECEITA DE TAXAS DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE ROYALTIES ANTECIPADO'::text, 'RECEITA DE TREINAMENTO INTERNO'::text, 'EXPANSÃO - TAXA DE LICENCIAMENTO'::text, 'RECEITA DE TAXA DE FRANQUIA/ALIANÇA'::text, 'EXPANSÃO - TAXA DE FRANQUIA'::text, 'RECEITA DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE IMPLANTAÇÃO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS PJ360'::text])) THEN 'EXPANSÃO'::text
            WHEN (upper((descricao_categoria)::text) = ANY (ARRAY['RECEITA DE TREINAMENTO EXTERNO'::text, 'RECEITA DE TREINAMENTOS'::text])) THEN 'EDUCAÇÃO'::text
            WHEN (upper((descricao_categoria)::text) = ANY (ARRAY['RECEITA DE SERVIÇOS JURÍDICOS'::text, 'RECEITA DE RESTITUIÇÃO'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRI'::text, 'RECEITA DE RETIFICAÇÃO'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LOW)'::text, 'RECEITA DE TESES TRIBUTÁRIAS'::text, 'RECEITA DE TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE PRT'::text, 'RECEITA DE PROJETOS ESPECIAIS'::text, 'RECEITA DE TESES'::text, 'RECEITA DE PONTOS QUALIFICADOS'::text, 'RECEITA DE OPERAÇÃO DE JOBS (ÊXITO)'::text, 'CLIENTES - TRIBUTÁRIO'::text, 'CLIENTES - TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE COMPENSAÇÃO'::text, 'RECEITA DE PONTO QUALIFICADOS'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRIA'::text, 'RECEITA DE MAPA FISCAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LAW)'::text, 'RECEITA DE GESTÃO DO PASSIVO TRIBUTÁRIO'::text, 'RECEITA DE AJE - ASSESSORIA JURÍDICA EMPRESARIAL'::text, 'RECEITA DE LIQUIDAÇÃO'::text, 'RECEITA DE AJUIZAMENTO'::text, 'RECEITA DE AJUIZAMENTOS TRIBUTÁRIOS'::text, 'RECEITA DE LIQUIDAÇÃO TRIBUTÁRIO'::text, 'CLIENTES - INTERMEDIAÇÕES DE NEGÓCIOS (JOBS)'::text])) THEN 'TAX'::text
            WHEN (upper((descricao_categoria)::text) = ANY (ARRAY['RECEITA DA SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OFFSHORE'::text, 'RECEITA DE CONSULTORIA ESTRATÉGICA'::text, 'RECEITA DE AJUIZAMENTOS CÍVEIS'::text, 'RECEITA DE GESTÃO DE CARTEIRA DE INVESTIMENTOS'::text, 'RECEITA DE RENEGOCIAÇÃO DE DÍVIDAS'::text, 'RECEITA DE FINANCIAMENTO DE FRANQUIA'::text, 'RECEITA DE HOLDING GOVERNANÇA'::text, 'RECEITA DE ASSESSORIA JURÍDICA MENSAL'::text, 'ASSESSORIA JURÍDICA MENSAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OPERAÇÃO DE JOBS (RECORRENTE)'::text, 'RECEITA DE OPERAÇÃO DE JOBS - SPACEW'::text, 'RECEITA DE OPERAÇÃO DE JOBS - AGRO'::text, 'RECEITA DE OPERAÇÃO DE JOBS'::text, 'RECEITA DE MERCADO LIVRE'::text, 'RECEITA DE HOLDING'::text, 'RECEITA DA SERVIÇOS JURÍDICOS'::text, 'CLIENTES - HOLDING'::text, 'RECEITA DE CESSÃO/NEGOCIAÇÃO DE PRECATÓRIOS'::text, 'RECEITA DE OPERAÇÃO DE JOB'::text, 'RECEITA DE CAPTAÇÃO DE RECURSOS'::text, 'RECEITA DE SEGUROS'::text, 'RECEITA DE MEA'::text, 'BPO FINANCEIRO'::text, 'RECEITA DE VALUATION'::text, 'RECEITA DE ASSINATURA DE ENERGIA'::text, 'RECEITA DE ENERGY GERAÇÃO - GD'::text, 'RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE SERVIÇOS CONTÁBEIS'::text, 'RECEITA DE HOLDING ITBI'::text, 'RECEITA DE SERVIÇOS JURIDICOS'::text, 'RECEITA DE AVALIAÇÃO PATRIMONIAL'::text, 'RECEITA DE ENERGY ASSESSORIA - RCE'::text, 'RECEITA DE FINANCIAMENTO - AMORTIZAÇÃO DE CRÉDITO'::text])) THEN 'CORPORATE'::text
            WHEN (upper((descricao_categoria)::text) = ANY (ARRAY['RECEITA DE SUPORTE E CONSULTORIA EM TI'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITACARD'::text, 'CLIENTES - LOCAÇÃO DE EQUIPAMENTOS E SUPORTE TI'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS GS'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS EXTERNO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITATAX'::text, 'RECEITA AUDITACARD'::text])) THEN 'TECNOLOGIA'::text
            WHEN (upper((descricao_categoria)::text) = ANY (ARRAY['SERVIÇOS ADMINISTRATIVOS'::text, 'REPASSE'::text, 'REEMBOLSO DE DESPESAS'::text, 'RECEITA IMPRESSÕES'::text, 'RECEITA IMPORTAÇÃO FINANCEIRO GS'::text, 'RECEITA DE MARKETING'::text, 'RECEITA DE LOJA'::text, 'RECEITA A IDENTIFICAR'::text, 'PRODUTOS/LOJA'::text, 'DISTRIBUIÇÃO DE LUCROS'::text, 'DEVOLUÇÃO PAGAMENTO EFETUADO'::text, 'DEVOLUÇÃO DE SERVIÇO PRESTADO'::text, 'DEVOLUÇÃO DE PAGAMENTO FEITO'::text, 'DEVOLUÇÃO DE PAGAMENTOS FEITOS'::text, 'APLICAÇÃO PARA EMPRÉSTIMOS'::text, '<DISPONÍVEL>'::text, 'RENDIMENTO DE APLICAÇÃO FINANCEIRA'::text, 'RECEITA DE VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text, 'RECEITA DHO'::text, 'VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text])) THEN 'OUTRAS RECEITAS'::text
            WHEN (upper((descricao_categoria)::text) = ANY (ARRAY['RECEITA DE TRANSFERÊNCIA ENTRE EMPRESAS DO GRUPO'::text, 'APORTE DE CAPITAL'::text, 'RECEITA DE EMPRÉSTIMOS ENTRE EMPRESAS'::text, 'TRANSFERÊNCIA ENTRE CONTAS'::text])) THEN 'INTER COMPANY'::text
            WHEN (upper((descricao_categoria)::text) = ANY (ARRAY['RECEITA DE LOCAÇÃO DE ESPAÇO E ESTACIONAMENTO'::text, 'RECEITA DE LOCAÇÃO DE ESPAÇO'::text, 'RECEITA DE ESTACIONAMENTO'::text, 'RECEITA DE COWORKING'::text])) THEN 'ADMINISTRAÇÃO'::text
            ELSE 'SEM CATEGORIA'::text
        END AS categoria
   FROM base_mf
  WHERE (data_vencimento < CURRENT_DATE);

-- Recriando metas
CREATE OR REPLACE VIEW public.metas AS 
 WITH contas_receber_sb AS (
         SELECT cr.codigo_lancamento_omie,
            cr.empresa_nome AS bandeira_nome,
            cr.empresa_cnpj,
            cr.codigo_cliente_fornecedor,
            cr.data_emissao,
            cr.data_vencimento,
            cr.valor_documento,
            cr.numero_documento,
            cr.codigo_categoria,
            cr.status_titulo,
            cr.categorias,
            cc.departamentos,
            cc.data_lancamento,
            oc.cnpj_cpf,
            oc.razao_social,
            COALESCE((cat.elem ->> 'codigo_categoria'::text), cr.codigo_categoria) AS codigo_categoria_expl,
            COALESCE(((cat.elem ->> 'percentual'::text))::numeric, (100)::numeric) AS percentual_categoria,
            COALESCE(cc.valor, (0)::numeric) AS valor_conta
           FROM (((contas_receber_grupo cr
             LEFT JOIN conta_corrente cc ON (((cr.codigo_lancamento_omie = cc.id_origem_receber) AND (cr.empresa_cnpj = cc.empresa_cnpj))))
             LEFT JOIN clientes_grupo oc ON (((cr.codigo_cliente_fornecedor = oc.codigo_cliente_omie) AND (cr.empresa_cnpj = oc.empresa_cnpj))))
             LEFT JOIN LATERAL ( SELECT elem.value AS elem
                   FROM jsonb_array_elements(
                        CASE
                            WHEN ((cr.categorias IS NOT NULL) AND (jsonb_typeof(cr.categorias) = 'array'::text) AND (jsonb_array_length(cr.categorias) > 0)) THEN cr.categorias
                            ELSE '[{}]'::jsonb
                        END) elem(value)) cat ON (true))
        ), abrindo_valores AS (
         SELECT cr.codigo_lancamento_omie,
            cr.data_emissao,
            cr.data_lancamento,
            cr.data_vencimento,
            cr.empresa_cnpj,
            cr.bandeira_nome AS bandeira,
            cr.cnpj_cpf,
            cr.razao_social,
            cr.codigo_categoria_expl,
            cr.percentual_categoria,
            co.descricao AS descricao_cat,
            cr.valor_conta,
            (dep.elem ->> 'cCodDep'::text) AS ccoddep,
            ((dep.elem ->> 'nPerDep'::text))::numeric AS percentual_departamento
           FROM ((contas_receber_sb cr
             LEFT JOIN categorias_omie co ON ((((co.codigo)::text = cr.codigo_categoria_expl) AND (co.empresa_cnpj = cr.empresa_cnpj))))
             LEFT JOIN LATERAL ( SELECT elem.value AS elem
                   FROM jsonb_array_elements(
                        CASE
                            WHEN ((cr.departamentos IS NOT NULL) AND (jsonb_typeof(cr.departamentos) = 'array'::text) AND (jsonb_array_length(cr.departamentos) > 0)) THEN cr.departamentos
                            ELSE '[{}]'::jsonb
                        END) elem(value)) dep ON (true))
        ), agrupando_valores AS (
         SELECT av.codigo_lancamento_omie,
            av.data_emissao,
            av.data_lancamento,
            av.data_vencimento,
            av.empresa_cnpj,
            av.bandeira,
            av.cnpj_cpf,
            av.razao_social,
            av.codigo_categoria_expl,
            av.percentual_categoria,
            av.descricao_cat,
            sum(av.valor_conta) AS valor_conta,
            av.ccoddep,
            av.percentual_departamento
           FROM abrindo_valores av
          GROUP BY av.codigo_lancamento_omie, av.data_emissao, av.data_lancamento, av.data_vencimento, av.empresa_cnpj, av.bandeira, av.cnpj_cpf, av.razao_social, av.codigo_categoria_expl, av.percentual_categoria, av.descricao_cat, av.ccoddep, av.percentual_departamento
        ), departamentos AS (
         SELECT av.codigo_lancamento_omie,
            av.data_emissao,
            av.data_lancamento,
            av.data_vencimento,
            av.bandeira,
            av.cnpj_cpf,
            av.razao_social,
            av.descricao_cat,
            av.percentual_categoria,
            av.ccoddep,
            av.percentual_departamento,
            d.descricao AS descricao_dept,
            ((av.valor_conta * (av.percentual_departamento / (100)::numeric)) * (av.percentual_categoria / (100)::numeric)) AS valor_cat_dept
           FROM (agrupando_valores av
             LEFT JOIN departamentos_omie d ON ((((d.codigo)::text = av.ccoddep) AND (d.empresa_cnpj = av.empresa_cnpj))))
          WHERE (av.ccoddep IS NOT NULL)
        ), sem_departamento AS (
         SELECT av.codigo_lancamento_omie,
            av.data_emissao,
            av.data_lancamento,
            av.data_vencimento,
            av.bandeira,
            av.cnpj_cpf,
            av.razao_social,
            av.descricao_cat,
            av.percentual_categoria,
            NULL::text AS ccoddep,
            NULL::numeric AS percentual_departamento,
            NULL::text AS descricao_dept,
            av.valor_conta
           FROM abrindo_valores av
          WHERE (NOT (av.codigo_lancamento_omie IN ( SELECT DISTINCT departamentos.codigo_lancamento_omie
                   FROM departamentos)))
        ), agrupando AS (
         SELECT d.codigo_lancamento_omie,
            d.data_emissao,
            d.data_lancamento,
            d.data_vencimento,
            d.bandeira,
            d.cnpj_cpf,
            d.razao_social,
            d.descricao_cat,
            d.percentual_categoria,
            d.ccoddep,
            d.percentual_departamento,
            d.descricao_dept,
            d.valor_cat_dept
           FROM departamentos d
        UNION ALL
         SELECT sd.codigo_lancamento_omie,
            sd.data_emissao,
            sd.data_lancamento,
            sd.data_vencimento,
            sd.bandeira,
            sd.cnpj_cpf,
            sd.razao_social,
            sd.descricao_cat,
            sd.percentual_categoria,
            sd.ccoddep,
            sd.percentual_departamento,
            sd.descricao_dept,
            sd.valor_conta
           FROM sem_departamento sd
        ), classificando AS (
         SELECT a.codigo_lancamento_omie,
            a.data_emissao,
            a.data_lancamento,
            a.data_vencimento,
            a.bandeira,
            a.cnpj_cpf,
            a.razao_social,
            a.descricao_cat,
            a.percentual_categoria,
            a.ccoddep,
            a.percentual_departamento,
            a.descricao_dept,
            a.valor_cat_dept,
                CASE
                    WHEN ((TRIM(BOTH FROM upper((a.descricao_cat)::text)) ~~ '%RECEITA DE CONTABILIDADE RECORRENTE%'::text) OR (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE MERCADO LIVRE DE ENERGIA'::text]))) THEN 'CORPORATE'::text
                    WHEN (a.cnpj_cpf = ANY (ARRAY['12340921000182'::text, '62700834000167'::text, '44158057000199'::text, '01501108000120'::text, '23382154000190'::text, '42622192000118'::text, '56378880000199'::text, '36657397000136'::text, '39287808000137'::text, '36480461000156'::text, '27057563000172'::text, '36530240000145'::text, '39484812000195'::text, '37852789000119'::text, '42380661000130'::text, '14723195000102'::text, '34349108000106'::text, '42275720000100'::text, '08865854000142'::text, '36685910000100'::text, '47244267053'::text, '57341084000144'::text, '23448109000191'::text, '11863345000195'::text, '39349860000170'::text, '58420510000106'::text, '48552493000107'::text, '44189727000134'::text, '53192862000120'::text])) THEN 'INTER COMPANY'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['TAXAS DE FRANQUIA/ALIANÇA'::text, 'ROYALTIES/CRM'::text, 'RECEITA DE ROYALTIES/CRM'::text, 'ROYALTIES VARIÁVEIS'::text, 'RECEITA DE ROYALTIES VARIÁVEIS'::text, 'ROYALTIES ANTECIPADO'::text, 'RECEITA DE ROYALTIES ANTECIPADOS'::text, 'RECEITA DE ROYALTIES'::text, 'FRANCHISING - ROYALTIES'::text, 'RECEITA DE CRM'::text, 'FRANCHISING - CRM'::text])) THEN 'FRANCHISING'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE TAXAS DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE ROYALTIES ANTECIPADO'::text, 'RECEITA DE TREINAMENTO INTERNO'::text, 'EXPANSÃO - TAXA DE LICENCIAMENTO'::text, 'RECEITA DE TAXA DE FRANQUIA/ALIANÇA'::text, 'EXPANSÃO - TAXA DE FRANQUIA'::text, 'RECEITA DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE IMPLANTAÇÃO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS PJ360'::text, 'RECEITA DE PRODUTOS/LOJA'::text])) THEN 'EXPANSÃO'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE TREINAMENTO EXTERNO'::text, 'RECEITA DE TREINAMENTOS'::text])) THEN 'EDUCAÇÃO'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE SERVIÇOS JURÍDICOS'::text, 'RECEITA DE RESTITUIÇÃO'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRI'::text, 'RECEITA DE RETIFICAÇÃO'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LOW)'::text, 'RECEITA DE TESES TRIBUTÁRIAS'::text, 'RECEITA DE TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE PRT'::text, 'RECEITA DE PROJETOS ESPECIAIS'::text, 'RECEITA DE TESES'::text, 'RECEITA DE PONTOS QUALIFICADOS'::text, 'RECEITA DE OPERAÇÃO DE JOBS (ÊXITO)'::text, 'CLIENTES - TRIBUTÁRIO'::text, 'CLIENTES - TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE COMPENSAÇÃO'::text, 'RECEITA DE PONTO QUALIFICADOS'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRIA'::text, 'RECEITA DE MAPA FISCAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LAW)'::text, 'RECEITA DE GESTÃO DO PASSIVO TRIBUTÁRIO'::text, 'RECEITA DE AJE - ASSESSORIA JURÍDICA EMPRESARIAL'::text, 'RECEITA DE LIQUIDAÇÃO'::text, 'RECEITA DE AJUIZAMENTO'::text, 'RECEITA DE AJUIZAMENTOS TRIBUTÁRIOS'::text, 'RECEITA DE LEI DO BEM'::text, 'RECEITA DE LIQUIDAÇÃO TRIBUTÁRIO'::text, 'CLIENTES - INTERMEDIAÇÕES DE NEGÓCIOS (JOBS)'::text])) THEN 'TAX'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DA SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OFFSHORE'::text, 'RECEITA DE CONSULTORIA ESTRATÉGICA'::text, 'RECEITA DE AJUIZAMENTOS CÍVEIS'::text, 'RECEITA DE GESTÃO DE CARTEIRA DE INVESTIMENTOS'::text, 'RECEITA DE RENEGOCIAÇÃO DE DÍVIDAS'::text, 'RECEITA DE FINANCIAMENTO DE FRANQUIA'::text, 'RECEITA DE FINANCIAMENTO DE FRANQUIA'::text, 'RECEITA DE HOLDING GOVERNANÇA'::text, 'RECEITA DE ASSESSORIA JURÍDICA MENSAL'::text, 'ASSESSORIA JURÍDICA MENSAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OPERAÇÃO DE JOBS (RECORRENTE)'::text, 'RECEITA DE OPERAÇÃO DE JOBS - SPACEW'::text, 'RECEITA DE OPERAÇÃO DE JOBS - AGRO'::text, 'RECEITA DE OPERAÇÃO DE JOBS'::text, 'RECEITA DE MERCADO LIVRE'::text, 'RECEITA DE HOLDING'::text, 'RECEITA DA SERVIÇOS JURÍDICOS'::text, 'CLIENTES - HOLDING'::text, 'RECEITA DE CESSÃO/NEGOCIAÇÃO DE PRECATÓRIOS'::text, 'RECEITA DE OPERAÇÃO DE JOB'::text, 'RECEITA DE CAPTAÇÃO DE RECURSOS'::text, 'RECEITA DE SEGUROS'::text, 'RECEITA DE MEA'::text, 'BPO FINANCEIRO'::text, 'RECEITA DE VALUATION'::text, 'RECEITA DE ASSINATURA DE ENERGIA'::text, 'RECEITA DE ENERGY GERAÇÃO - GD'::text, 'RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE SERVIÇOS CONTÁBEIS'::text, 'RECEITA DE HOLDING ITBI'::text, 'RECEITA DE SERVIÇOS JURIDICOS'::text, 'RECEITA DE AVALIAÇÃO PATRIMONIAL'::text, 'RECEITA DE ENERGY ASSESSORIA - RCE'::text, 'RECEITA DE FINANCIAMENTO - AMORTIZAÇÃO DE CRÉDITO'::text, 'RECEITA DE FINANCIAMENTO - RENDIMENTO DE FINANCIAMENTO'::text])) THEN 'CORPORATE'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE SUPORTE E CONSULTORIA EM TI'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITACARD'::text, 'CLIENTES - LOCAÇÃO DE EQUIPAMENTOS E SUPORTE TI'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS GS'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS EXTERNO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITATAX'::text, 'RECEITA AUDITACARD'::text])) THEN 'TECNOLOGIA'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['SERVIÇOS ADMINISTRATIVOS'::text, 'REPASSE'::text, 'REEMBOLSO DE DESPESAS'::text, 'RECEITA IMPRESSÕES'::text, 'RECEITA IMPORTAÇÃO FINANCEIRO GS'::text, 'RECEITA DE MARKETING'::text, 'RECEITA DE LOJA'::text, 'RECEITA A IDENTIFICAR'::text, 'PRODUTOS/LOJA'::text, 'DISTRIBUIÇÃO DE LUCROS'::text, 'DEVOLUÇÃO PAGAMENTO EFETUADO'::text, 'DEVOLUÇÃO DE SERVIÇO PRESTADO'::text, 'DEVOLUÇÃO DE PAGAMENTO FEITO'::text, 'DEVOLUÇÃO DE PAGAMENTOS FEITOS'::text, 'APLICAÇÃO PARA EMPRÉSTIMOS'::text, '<DISPONÍVEL>'::text, 'RENDIMENTO DE APLICAÇÃO FINANCEIRA'::text, 'RECEITA DE VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text, 'RECEITA DHO'::text, 'VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text, 'RECEITA SOCIAL MÍDIA DE ALTA PERFORMANCE'::text, 'RESGATE DE APLICAÇÃO FINANCEIRA'::text])) THEN 'OUTRAS RECEITAS'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE TRANSFERÊNCIA ENTRE EMPRESAS DO GRUPO'::text, 'APORTE DE CAPITAL'::text, 'RECEITA DE EMPRÉSTIMOS ENTRE EMPRESAS'::text, 'TRANSFERÊNCIA ENTRE CONTAS'::text, 'CAPITAL DE GIRO'::text, 'ADIANTAMENTO RECEBIDO REPASSES FUTUROS'::text])) THEN 'INTER COMPANY'::text
                    WHEN (upper((a.descricao_cat)::text) = ANY (ARRAY['RECEITA DE LOCAÇÃO DE ESPAÇO E ESTACIONAMENTO'::text, 'RECEITA DE LOCAÇÃO DE ESPAÇO'::text, 'RECEITA DE ESTACIONAMENTO'::text, 'RECEITA DE COWORKING'::text])) THEN 'ADMINISTRAÇÃO'::text
                    ELSE 'SEM CATEGORIA'::text
                END AS categoria
           FROM agrupando a
          WHERE (a.data_lancamento >= '2026-01-01'::date)
        )
 SELECT row_number() OVER () AS id,
    codigo_lancamento_omie,
    data_emissao,
    data_lancamento,
    data_vencimento,
    bandeira,
    cnpj_cpf,
    razao_social,
    descricao_cat,
    percentual_categoria,
    ccoddep,
    percentual_departamento,
    descricao_dept,
    round(valor_cat_dept, 2) AS valor_conta,
    categoria
   FROM classificando c;
