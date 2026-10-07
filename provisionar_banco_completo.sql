-- =============================================================================
-- PROVISIONAMENTO COMPLETO - ETL Omie -> Supabase
-- Gerado em 04/10/2026. Idempotente: pode rodar mais de uma vez.
--
-- Cria o ambiente inteiro do zero: 1 extensao, 8 tabelas, 8 primary keys,
-- 7 indices por empresa e 8 views. Nenhuma view depende de outra - todas
-- leem apenas tabelas.
--
-- PROCEDENCIA
--   Tabelas, PKs e as views metas, metas_bruto e painel_contas_pagar foram
--   extraidas do banco de producao antigo (pg_get_viewdef, 02/09/2026),
--   antes de ele ser removido.
--
--   view_contas_pagar, view_contas_receber, view_faturamento_rateado,
--   view_inadimplencia e vw_contas_receber_detalhada foram recuperadas do
--   historico git de chrislopes2/omie-supabase-etl: arquivo fix_supabase.sql,
--   commit af5b3c2, que foi revertido e apagado do repositorio.
--
--   'metas' existia nas duas fontes. Usou-se a de PRODUCAO; a do commit
--   af5b3c2 foi descartada porque aquele commit foi revertido e nunca rodou.
--
-- AUSENTES DE PROPOSITO
--   view_extrato, view_movimentos_gerencial, painel_faturamento,
--   painel_contas_pagar_rateado e contas_pagar_new. A varredura dos 155 blobs
--   do repositorio de origem nao encontrou definicao de nenhuma delas, e
--   nenhum dos 52 arquivos Power BI auditados as consome.
-- =============================================================================

-- =============================================================================
-- SETUP DO BANCO - ETL Omie -> Supabase
--
-- Gerado por engenharia reversa do banco de producao (projeto tnbxmrathdctzkadekqa)
-- em 02/09/2026. Aplicar no SQL Editor do projeto novo (avgadtgnhsqvyqwkjuvp).
--
-- Ordem: extensoes -> tabelas -> primary keys -> indices -> views.
-- Idempotente: pode rodar mais de uma vez sem erro.
-- =============================================================================

-- extrato_bancario.id usa uuid_generate_v4()
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;


-- ============================ TABELAS ============================

CREATE TABLE IF NOT EXISTS public.categorias_omie (
  codigo character varying(100) NOT NULL,
  empresa_nome text,
  empresa_cnpj text NOT NULL,
  descricao character varying(500),
  descricao_padrao character varying(500),
  categoria_superior character varying(500),
  conta_despesa character varying(100),
  conta_receita character varying(100),
  conta_inativa character varying(100),
  definida_pelo_usuario character varying(100),
  nao_exibir character varying(100),
  totalizadora character varying(100),
  transferencia character varying(100),
  codigo_dre character varying(500),
  id_conta_contabil character varying(1000),
  tag_conta_contabil character varying(500),
  natureza character varying(500),
  tipo_categoria character varying(100),
  dados_dre jsonb,
  last_update timestamp with time zone,
  codigo_valores_unidades integer,
  bandeiras integer
);

CREATE TABLE IF NOT EXISTS public.clientes_grupo (
  codigo_cliente_omie bigint NOT NULL,
  empresa_nome text,
  empresa_cnpj text NOT NULL,
  cnpj_cpf text,
  razao_social text,
  nome_fantasia text,
  data_integracao timestamp with time zone DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS public.conta_corrente (
  codigo_lancamento bigint NOT NULL,
  empresa_nome text,
  empresa_cnpj text NOT NULL,
  id_conta_corrente bigint,
  data_lancamento date,
  valor numeric(15,2),
  codigo_categoria character varying(50),
  numero_documento character varying(50),
  tipo_documento character varying(10),
  observacao text,
  id_cliente_fornecedor bigint,
  id_projeto bigint,
  natureza character varying(5),
  origem character varying(10),
  data_conciliacao date,
  id_origem_receber bigint,
  id_origem_pagar bigint,
  data_inclusao date,
  usuario_inclusao character varying(50),
  last_update timestamp without time zone,
  departamentos jsonb,
  bandeira_id integer,
  categorias jsonb
);

CREATE TABLE IF NOT EXISTS public.contas_pagar (
  empresa_cnpj character varying(20),
  empresa_nome character varying(100),
  codigo_lancamento_integracao character varying(50),
  codigo_cliente_fornecedor bigint,
  data_emissao date,
  data_vencimento date,
  data_previsao date,
  data_registro date,
  data_entrada date,
  valor_documento numeric(15,2),
  numero_documento character varying(50),
  numero_parcela character varying(20),
  numero_pedido character varying(50),
  chave_nfe character varying(100),
  codigo_barras_ficha_compensacao character varying(100),
  codigo_categoria character varying(50),
  codigo_projeto bigint,
  codigo_vendedor bigint,
  id_origem character varying(10),
  id_conta_corrente bigint,
  status_titulo character varying(50),
  codigo_tipo_documento character varying(10),
  operacao character varying(10),
  situacao character varying(100),
  retem_pis character varying(1),
  retem_cofins character varying(1),
  retem_csll character varying(1),
  retem_ir character varying(1),
  retem_iss character varying(1),
  retem_inss character varying(1),
  baixa_bloqueada character varying(1),
  bloqueado character varying(1),
  last_update timestamp without time zone,
  codigo_cmc7_cheque character varying(100),
  numero_documento_fiscal character varying(100),
  nsu character varying(100),
  boleto_gerado character varying(1),
  pix_gerado character varying(1),
  valor_cofins numeric,
  valor_csll numeric,
  valor_ir numeric,
  valor_inss numeric,
  valor_pis numeric,
  valor_iss numeric,
  distribuicao json,
  info json,
  codigo_lancamento_omie bigint NOT NULL,
  bandeira_id integer NOT NULL,
  categorias jsonb,
  valor_juros numeric DEFAULT 0,
  valor_multa numeric DEFAULT 0,
  valor_desconto numeric DEFAULT 0,
  resumo jsonb,
  json_bruto jsonb
);

CREATE TABLE IF NOT EXISTS public.contas_receber_grupo (
  codigo_lancamento_omie bigint NOT NULL,
  empresa_nome text,
  empresa_cnpj text NOT NULL,
  codigo_cliente_fornecedor bigint,
  numero_documento text,
  data_vencimento date,
  valor_documento numeric(15,2),
  status_titulo text,
  codigo_categoria text,
  data_integracao timestamp with time zone DEFAULT timezone('utc'::text, now()),
  data_emissao date,
  categorias jsonb,
  distribuicao json,
  numero_contrato text,
  numero_documento_fiscal text
);

CREATE TABLE IF NOT EXISTS public.departamentos_omie (
  codigo character varying(50) NOT NULL,
  descricao character varying(255),
  estrutura character varying(50),
  inativo character(1),
  bandeira_id bigint,
  empresa_nome text,
  empresa_cnpj text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.extrato_bancario (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  empresa_cnpj character varying(20),
  empresa_nome character varying(255),
  id_conta_corrente bigint,
  descricao_conta character varying(255),
  data_lancamento date,
  id_lancamento bigint,
  id_lancamento_relacionado bigint,
  situacao character varying(100),
  nome_fantasia_cliente character varying(255),
  tipo_documento character varying(100),
  numero_documento character varying(100),
  valor_documento numeric(15,2),
  saldo_realizado numeric(15,2),
  codigo_categoria character varying(50),
  descricao_categoria character varying(255),
  numero_documento_fiscal character varying(100),
  parcela character varying(20),
  nosso_numero character varying(100),
  origem character varying(100),
  vendedor character varying(255),
  projeto character varying(255),
  id_cliente_fornecedor bigint,
  razao_social_cliente character varying(255),
  last_update timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.movimentos_financeiros (
  id_movimento bigint NOT NULL,
  empresa_nome character varying(255) NOT NULL,
  empresa_cnpj character varying(20) NOT NULL,
  id_conta_corrente bigint,
  id_cliente_fornecedor bigint,
  id_titulo_origem bigint,
  grupo character varying(50),
  natureza character varying(5),
  tipo character varying(10),
  origem character varying(10),
  categoria_codigo character varying(50),
  numero_titulo character varying(50),
  numero_parcela character varying(20),
  chave_nfe character varying(50),
  cpf_cnpj character varying(20),
  codigo_barras character varying(100),
  data_emissao date,
  data_vencimento date,
  data_previsao date,
  data_pagamento date,
  data_registro date,
  valor_titulo numeric(15,2),
  valor_pago numeric(15,2),
  valor_liquido numeric(15,2),
  valor_aberto numeric(15,2),
  valor_juros numeric(15,2),
  valor_multa numeric(15,2),
  valor_desconto numeric(15,2),
  status character varying(50),
  liquidado character varying(1),
  last_update timestamp without time zone DEFAULT now(),
  cstatus character varying(100),
  valor_pis numeric(15,2),
  valor_cofins numeric(15,2),
  valor_csll numeric(15,2),
  valor_ir numeric(15,2),
  valor_iss numeric(15,2),
  valor_inss numeric(15,2)
);


-- ========================== PRIMARY KEYS ==========================

DO $$ BEGIN
  ALTER TABLE public.categorias_omie ADD CONSTRAINT categorias_omie_pkey PRIMARY KEY (codigo, empresa_cnpj);
EXCEPTION WHEN duplicate_table OR invalid_table_definition THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.clientes_grupo ADD CONSTRAINT clientes_grupo_pkey PRIMARY KEY (codigo_cliente_omie, empresa_cnpj);
EXCEPTION WHEN duplicate_table OR invalid_table_definition THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.conta_corrente ADD CONSTRAINT conta_corrente_pkey PRIMARY KEY (codigo_lancamento, empresa_cnpj);
EXCEPTION WHEN duplicate_table OR invalid_table_definition THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.contas_pagar ADD CONSTRAINT contas_pagar_pkey PRIMARY KEY (codigo_lancamento_omie, bandeira_id);
EXCEPTION WHEN duplicate_table OR invalid_table_definition THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.contas_receber_grupo ADD CONSTRAINT contas_receber_grupo_pkey PRIMARY KEY (codigo_lancamento_omie, empresa_cnpj);
EXCEPTION WHEN duplicate_table OR invalid_table_definition THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.departamentos_omie ADD CONSTRAINT departamentos_omie_pkey PRIMARY KEY (codigo, empresa_cnpj);
EXCEPTION WHEN duplicate_table OR invalid_table_definition THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.extrato_bancario ADD CONSTRAINT extrato_bancario_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_table OR invalid_table_definition THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.movimentos_financeiros ADD CONSTRAINT movimentos_financeiros_pkey PRIMARY KEY (id_movimento, empresa_cnpj);
EXCEPTION WHEN duplicate_table OR invalid_table_definition THEN NULL;
END $$;


-- ======================= INDICES POR EMPRESA =======================
-- A carga apaga e regrava cada empresa (DELETE ... WHERE empresa_cnpj = ...).
-- Sem indice, cada limpeza percorre a tabela inteira; com varias ao mesmo
-- tempo, estourava o limite de 8 s da API do Supabase (07/10/2026).

CREATE INDEX IF NOT EXISTS categorias_omie_empresa_cnpj_idx ON public.categorias_omie (empresa_cnpj);
CREATE INDEX IF NOT EXISTS clientes_grupo_empresa_cnpj_idx ON public.clientes_grupo (empresa_cnpj);
CREATE INDEX IF NOT EXISTS conta_corrente_empresa_cnpj_idx ON public.conta_corrente (empresa_cnpj);
CREATE INDEX IF NOT EXISTS contas_pagar_empresa_cnpj_idx ON public.contas_pagar (empresa_cnpj);
CREATE INDEX IF NOT EXISTS contas_receber_grupo_empresa_cnpj_idx ON public.contas_receber_grupo (empresa_cnpj);
CREATE INDEX IF NOT EXISTS departamentos_omie_empresa_cnpj_idx ON public.departamentos_omie (empresa_cnpj);
CREATE INDEX IF NOT EXISTS movimentos_financeiros_empresa_cnpj_idx ON public.movimentos_financeiros (empresa_cnpj);




-- ================================ VIEWS ================================


-- metas
-- origem: producao (banco vivo, 02/09/2026)
DROP VIEW IF EXISTS public.metas CASCADE;
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
            cr.numero_contrato,
            cr.codigo_categoria,
            cr.status_titulo,
            cr.categorias,
            cc.departamentos,
            cc.data_lancamento,
            oc.cnpj_cpf,
            oc.razao_social,
            COALESCE(cat.elem ->> 'codigo_categoria'::text, cr.codigo_categoria) AS codigo_categoria_expl,
            COALESCE((cat.elem ->> 'percentual'::text)::numeric, 100::numeric) AS percentual_categoria,
            COALESCE(cc.valor, 0::numeric) AS valor_conta
           FROM contas_receber_grupo cr
             LEFT JOIN conta_corrente cc ON cr.codigo_lancamento_omie = cc.id_origem_receber AND cr.empresa_cnpj = cc.empresa_cnpj
             LEFT JOIN clientes_grupo oc ON cr.codigo_cliente_fornecedor = oc.codigo_cliente_omie AND cr.empresa_cnpj = oc.empresa_cnpj
             LEFT JOIN LATERAL ( SELECT elem.value AS elem
                   FROM jsonb_array_elements(
                        CASE
                            WHEN cr.categorias IS NOT NULL AND jsonb_typeof(cr.categorias) = 'array'::text AND jsonb_array_length(cr.categorias) > 0 THEN cr.categorias
                            ELSE '[{}]'::jsonb
                        END) elem(value)) cat ON true
        ), abrindo_valores AS (
         SELECT cr.codigo_lancamento_omie,
            cr.data_emissao,
            cr.data_lancamento,
            cr.data_vencimento,
            cr.empresa_cnpj,
            cr.bandeira_nome AS bandeira,
            cr.cnpj_cpf,
            cr.razao_social,
            cr.numero_contrato,
            cr.codigo_categoria_expl,
            cr.percentual_categoria,
            co.descricao AS descricao_cat,
            cr.valor_conta,
            dep.elem ->> 'cCodDep'::text AS ccoddep,
            (dep.elem ->> 'nPerDep'::text)::numeric AS percentual_departamento
           FROM contas_receber_sb cr
             LEFT JOIN categorias_omie co ON co.codigo::text = cr.codigo_categoria_expl AND co.empresa_cnpj = cr.empresa_cnpj
             LEFT JOIN LATERAL ( SELECT elem.value AS elem
                   FROM jsonb_array_elements(
                        CASE
                            WHEN cr.departamentos IS NOT NULL AND jsonb_typeof(cr.departamentos) = 'array'::text AND jsonb_array_length(cr.departamentos) > 0 THEN cr.departamentos
                            ELSE '[{}]'::jsonb
                        END) elem(value)) dep ON true
        ), agrupando_valores AS (
         SELECT av.codigo_lancamento_omie,
            av.data_emissao,
            av.data_lancamento,
            av.data_vencimento,
            av.empresa_cnpj,
            av.bandeira,
            av.cnpj_cpf,
            av.razao_social,
            av.numero_contrato,
            av.codigo_categoria_expl,
            av.percentual_categoria,
            av.descricao_cat,
            sum(av.valor_conta) AS valor_conta,
            av.ccoddep,
            av.percentual_departamento
           FROM abrindo_valores av
          GROUP BY av.codigo_lancamento_omie, av.data_emissao, av.data_lancamento, av.data_vencimento, av.empresa_cnpj, av.bandeira, av.cnpj_cpf, av.razao_social, av.numero_contrato, av.codigo_categoria_expl, av.percentual_categoria, av.descricao_cat, av.ccoddep, av.percentual_departamento
        ), departamentos AS (
         SELECT av.codigo_lancamento_omie,
            av.data_emissao,
            av.data_lancamento,
            av.data_vencimento,
            av.bandeira,
            av.cnpj_cpf,
            av.razao_social,
            av.numero_contrato,
            av.descricao_cat,
            av.percentual_categoria,
            av.ccoddep,
            av.percentual_departamento,
            d.descricao AS descricao_dept,
            av.valor_conta * (av.percentual_departamento / 100::numeric) * (av.percentual_categoria / 100::numeric) AS valor_cat_dept
           FROM agrupando_valores av
             LEFT JOIN departamentos_omie d ON d.codigo::text = av.ccoddep AND d.empresa_cnpj = av.empresa_cnpj
          WHERE av.ccoddep IS NOT NULL
        ), sem_departamento AS (
         SELECT av.codigo_lancamento_omie,
            av.data_emissao,
            av.data_lancamento,
            av.data_vencimento,
            av.bandeira,
            av.cnpj_cpf,
            av.razao_social,
            av.numero_contrato,
            av.descricao_cat,
            av.percentual_categoria,
            NULL::text AS ccoddep,
            NULL::numeric AS percentual_departamento,
            NULL::text AS descricao_dept,
            av.valor_conta
           FROM abrindo_valores av
          WHERE NOT (av.codigo_lancamento_omie IN ( SELECT DISTINCT departamentos.codigo_lancamento_omie
                   FROM departamentos))
        ), agrupando AS (
         SELECT d.codigo_lancamento_omie,
            d.data_emissao,
            d.data_lancamento,
            d.data_vencimento,
            d.bandeira,
            d.cnpj_cpf,
            d.razao_social,
            d.numero_contrato,
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
            sd.numero_contrato,
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
            a.numero_contrato,
            a.descricao_cat,
            a.percentual_categoria,
            a.ccoddep,
            a.percentual_departamento,
            a.descricao_dept,
            a.valor_cat_dept,
                CASE
                    WHEN TRIM(BOTH FROM upper(a.descricao_cat::text)) ~~ '%RECEITA DE CONTABILIDADE RECORRENTE%'::text OR (upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE HOLDING'::text, 'RECEITA DE SERVIÇOS CONTÁBEIS'::text])) THEN 'CORPORATE'::text
                    WHEN regexp_replace(a.cnpj_cpf, '\D'::text, ''::text, 'g'::text) = ANY (ARRAY['12340921000182'::text, '62700834000167'::text, '44158057000199'::text, '01501108000120'::text, '23382154000190'::text, '42622192000118'::text, '56378880000199'::text, '36657397000136'::text, '39287808000137'::text, '36480461000156'::text, '27057563000172'::text, '36530240000145'::text, '39484812000195'::text, '37852789000119'::text, '42380661000130'::text, '14723195000102'::text, '34349108000106'::text, '42275720000100'::text, '08865854000142'::text, '36685910000100'::text, '47244267053'::text, '57341084000144'::text, '23448109000191'::text, '11863345000195'::text, '39349860000170'::text, '58420510000106'::text, '48552493000107'::text, '44189727000134'::text, '53192862000120'::text]) THEN 'INTER COMPANY'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['TAXAS DE FRANQUIA/ALIANÇA'::text, 'ROYALTIES/CRM'::text, 'RECEITA DE ROYALTIES/CRM'::text, 'ROYALTIES VARIÁVEIS'::text, 'RECEITA DE ROYALTIES VARIÁVEIS'::text, 'ROYALTIES ANTECIPADO'::text, 'RECEITA DE ROYALTIES ANTECIPADOS'::text, 'RECEITA DE ROYALTIES'::text, 'FRANCHISING - ROYALTIES'::text, 'RECEITA DE CRM'::text, 'FRANCHISING - CRM'::text]) THEN 'FRANCHISING'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE TAXAS DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE ROYALTIES ANTECIPADO'::text, 'RECEITA DE TREINAMENTO INTERNO'::text, 'EXPANSÃO - TAXA DE LICENCIAMENTO'::text, 'RECEITA DE TAXA DE FRANQUIA/ALIANÇA'::text, 'EXPANSÃO - TAXA DE FRANQUIA'::text, 'RECEITA DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE IMPLANTAÇÃO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS PJ360'::text, 'RECEITA DE LICENÇAS DE SOFWARES - PJ360'::text, 'RECEITA DE LICENÇAS DE SOFTWARES - PJ360'::text, 'RECEITA DE PRODUTOS/LOJA'::text]) THEN 'EXPANSÃO'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE TREINAMENTO EXTERNO'::text, 'RECEITA DE TREINAMENTOS'::text]) THEN 'EDUCAÇÃO'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE SERVIÇOS JURÍDICOS'::text, 'RECEITA DE RESTITUIÇÃO'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRI'::text, 'RECEITA DE RETIFICAÇÃO'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LOW)'::text, 'RECEITA DE TESES TRIBUTÁRIAS'::text, 'RECEITA DE TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE PRT'::text, 'RECEITA DE PROJETOS ESPECIAIS'::text, 'RECEITA DE TESES'::text, 'RECEITA DE PONTOS QUALIFICADOS'::text, 'RECEITA DE OPERAÇÃO DE JOBS (ÊXITO)'::text, 'CLIENTES - TRIBUTÁRIO'::text, 'CLIENTES - TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE COMPENSAÇÃO'::text, 'RECEITA DE PONTO QUALIFICADOS'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRIA'::text, 'RECEITA DE MAPA FISCAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LAW)'::text, 'RECEITA DE GESTÃO DO PASSIVO TRIBUTÁRIO'::text, 'RECEITA DE AJE - ASSESSORIA JURÍDICA EMPRESARIAL'::text, 'RECEITA DE LIQUIDAÇÃO'::text, 'RECEITA DE AJUIZAMENTO'::text, 'RECEITA DE AJUIZAMENTOS TRIBUTÁRIOS'::text, 'RECEITA DE LEI DO BEM'::text, 'RECEITA DE LIQUIDAÇÃO TRIBUTÁRIO'::text, 'CLIENTES - INTERMEDIAÇÕES DE NEGÓCIOS (JOBS)'::text, 'RECEITA DE SUBVENÇÃO FINEP'::text, 'RECEITA DE SUPPLY TAX'::text, 'RECEITA DE RENEGOCIAÇÃO DE DÍVIDAS'::text]) THEN 'TAX'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DA SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OFFSHORE'::text, 'RECEITA DE CONSULTORIA ESTRATÉGICA'::text, 'RECEITA DE AJUIZAMENTOS CÍVEIS'::text, 'RECEITA DE GESTÃO DE CARTEIRA DE INVESTIMENTOS'::text, 'RECEITA DE FINANCIAMENTO DE FRANQUIA'::text, 'RECEITA DE FINANCIAMENTO DE FRANQUIA'::text, 'RECEITA DE HOLDING GOVERNANÇA'::text, 'RECEITA DE ASSESSORIA JURÍDICA MENSAL'::text, 'ASSESSORIA JURÍDICA MENSAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OPERAÇÃO DE JOBS (RECORRENTE)'::text, 'RECEITA DE OPERAÇÃO DE JOBS - SPACEW'::text, 'RECEITA DE OPERAÇÃO DE JOBS - AGRO'::text, 'RECEITA DE OPERAÇÃO DE JOBS'::text, 'RECEITA DE MERCADO LIVRE'::text, 'RECEITA DE HOLDING'::text, 'RECEITA DA SERVIÇOS JURÍDICOS'::text, 'CLIENTES - HOLDING'::text, 'RECEITA DE CESSÃO/NEGOCIAÇÃO DE PRECATÓRIOS'::text, 'RECEITA DE OPERAÇÃO DE JOB'::text, 'RECEITA DE CAPTAÇÃO DE RECURSOS'::text, 'RECEITA DE SEGUROS'::text, 'RECEITA DE MEA'::text, 'BPO FINANCEIRO'::text, 'RECEITA DE VALUATION'::text, 'RECEITA DE ASSINATURA DE ENERGIA'::text, 'RECEITA DE ENERGY GERAÇÃO - GD'::text, 'RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE SERVIÇOS CONTÁBEIS'::text, 'RECEITA DE HOLDING ITBI'::text, 'RECEITA DE SERVIÇOS JURIDICOS'::text, 'RECEITA DE AVALIAÇÃO PATRIMONIAL'::text, 'RECEITA DE ENERGY ASSESSORIA - RCE'::text, 'RECEITA DE FINANCIAMENTO - AMORTIZAÇÃO DE CRÉDITO'::text, 'RECEITA DE FINANCIAMENTO - RENDIMENTO DE FINANCIAMENTO'::text, 'RECEITA DE RECUPERA ENERGIA'::text, 'RECEITA DE ANTEPICAÇÃO DE RECEBÍVEIS'::text, 'RECEITA DE ANTECIPAÇÃO DE RECEBÍVEIS'::text]) THEN 'CORPORATE'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE SUPORTE E CONSULTORIA EM TI'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITACARD'::text, 'CLIENTES - LOCAÇÃO DE EQUIPAMENTOS E SUPORTE TI'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS GS'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS EXTERNO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITATAX'::text, 'RECEITA AUDITACARD'::text]) THEN 'TECNOLOGIA'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['SERVIÇOS ADMINISTRATIVOS'::text, 'REPASSE'::text, 'REEMBOLSO DE DESPESAS'::text, 'RECEITA IMPRESSÕES'::text, 'RECEITA IMPORTAÇÃO FINANCEIRO GS'::text, 'RECEITA DE MARKETING'::text, 'RECEITA DE LOJA'::text, 'RECEITA A IDENTIFICAR'::text, 'PRODUTOS/LOJA'::text, 'DISTRIBUIÇÃO DE LUCROS'::text, 'DEVOLUÇÃO PAGAMENTO EFETUADO'::text, 'DEVOLUÇÃO DE SERVIÇO PRESTADO'::text, 'DEVOLUÇÃO DE PAGAMENTO FEITO'::text, 'DEVOLUÇÃO DE PAGAMENTOS FEITOS'::text, 'APLICAÇÃO PARA EMPRÉSTIMOS'::text, '<DISPONÍVEL>'::text, 'RENDIMENTO DE APLICAÇÃO FINANCEIRA'::text, 'RECEITA DE VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text, 'RECEITA DHO'::text, 'VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text, 'RECEITA SOCIAL MÍDIA DE ALTA PERFORMANCE'::text, 'RESGATE DE APLICAÇÃO FINANCEIRA'::text, 'RESGATE DE APLICAÇÕES FINANCEIRAS'::text, 'RECEITA DIVERSA'::text, 'RECEITA DE SERVIÇO DE IMPRESSÃO'::text, 'DEVOLUÇÃO DE CAPITAL DE GIRO'::text, 'DESCONTOS OBTIDOS'::text, 'RECEITA DE SERVIÇOS DE IMPRESSÃO'::text, 'RESTITUIÇÃO E RECUPERAÇÃO DE TRIBUTOS'::text, 'TAXAS BANCÁRIAS'::text, 'RECUPERAÇÃO DE DEPÓSITOS JUDICIAIS'::text]) THEN 'OUTRAS RECEITAS'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE TRANSFERÊNCIA ENTRE EMPRESAS DO GRUPO'::text, 'APORTE DE CAPITAL'::text, 'RECEITA DE EMPRÉSTIMOS ENTRE EMPRESAS'::text, 'TRANSFERÊNCIA ENTRE CONTAS'::text, 'CAPITAL DE GIRO'::text, 'ADIANTAMENTO RECEBIDO REPASSES FUTUROS'::text, 'RECEITA INTERCOMPANY'::text, 'RECEITA DE FUNDO DE MARKETING/ADMINISTRATIVO'::text, 'ENTRADA DE TRANSFERÊNCIAS'::text, 'ANTECIPAÇÃO DE LUCROS'::text]) THEN 'INTER COMPANY'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE LOCAÇÃO DE ESPAÇO E ESTACIONAMENTO'::text, 'RECEITA DE LOCAÇÃO DE ESPAÇO'::text, 'RECEITA DE ESTACIONAMENTO'::text, 'RECEITA DE COWORKING'::text, 'RECEITA DE CESSÃO DE USO DE IMÓVEL'::text]) THEN 'ADMINISTRAÇÃO'::text
                    ELSE 'SEM CATEGORIA'::text
                END AS categoria
           FROM agrupando a
          WHERE a.data_lancamento >= '2026-01-01'::date
        )
 SELECT row_number() OVER () AS id,
    codigo_lancamento_omie,
    data_emissao,
    data_lancamento,
    data_vencimento,
    bandeira,
    cnpj_cpf,
    razao_social,
    numero_contrato,
    descricao_cat,
    percentual_categoria,
    ccoddep,
    percentual_departamento,
    descricao_dept,
    round(valor_cat_dept, 2) AS valor_conta,
    categoria
   FROM classificando c;


-- metas_bruto
-- origem: producao (banco vivo, 02/09/2026)
DROP VIEW IF EXISTS public.metas_bruto CASCADE;
CREATE OR REPLACE VIEW public.metas_bruto AS
 WITH base_cc_ajustada AS (
         SELECT cc.id_origem_receber,
            cc.empresa_cnpj,
            cc.id_conta_corrente,
            cc.data_lancamento,
            cc.departamentos,
            cc.valor AS cc_valor,
            COALESCE(sum(cc.valor) OVER (PARTITION BY cc.id_origem_receber, cc.empresa_cnpj), 0::numeric) AS sum_total_cc
           FROM conta_corrente cc
        ), contas_receber_sb AS (
         SELECT cr.codigo_lancamento_omie,
            cr.empresa_nome AS bandeira_nome,
            cr.empresa_cnpj,
            cr.codigo_cliente_fornecedor,
            cr.data_emissao,
            cr.data_vencimento,
            cr.valor_documento,
            cr.numero_documento,
            cr.numero_documento_fiscal,
            cr.numero_contrato,
            cr.codigo_categoria,
            cr.status_titulo,
            cr.categorias,
            cc.departamentos,
            cc.data_lancamento,
            oc.cnpj_cpf,
            oc.razao_social,
            COALESCE(cat.elem ->> 'codigo_categoria'::text, cr.codigo_categoria) AS codigo_categoria_expl,
            COALESCE((cat.elem ->> 'percentual'::text)::numeric, 100::numeric) AS percentual_categoria,
                CASE
                    WHEN cc.cc_valor IS NULL OR cc.cc_valor = 0::numeric THEN COALESCE(cr.valor_documento, 0::numeric)
                    WHEN cr.status_titulo = 'RECEBIDO'::text THEN round(cc.cc_valor * (COALESCE(cr.valor_documento, 0::numeric) / NULLIF(cc.sum_total_cc, 0::numeric)), 2)
                    ELSE COALESCE(cc.cc_valor, 0::numeric)
                END AS valor_conta,
                CASE
                    WHEN cr.status_titulo ~~* '%PARCIAL%'::text THEN 'SIM'::text
                    ELSE 'NÃO'::text
                END AS pagamento_parcial
           FROM contas_receber_grupo cr
             LEFT JOIN base_cc_ajustada cc ON cr.codigo_lancamento_omie = cc.id_origem_receber AND cr.empresa_cnpj = cc.empresa_cnpj
             LEFT JOIN clientes_grupo oc ON cr.codigo_cliente_fornecedor = oc.codigo_cliente_omie AND cr.empresa_cnpj = oc.empresa_cnpj
             LEFT JOIN LATERAL ( SELECT elem.value AS elem
                   FROM jsonb_array_elements(
                        CASE
                            WHEN cr.categorias IS NOT NULL AND jsonb_typeof(cr.categorias) = 'array'::text AND jsonb_array_length(cr.categorias) > 0 THEN cr.categorias
                            ELSE '[{}]'::jsonb
                        END) elem(value)) cat ON true
        ), abrindo_valores AS (
         SELECT cr.codigo_lancamento_omie,
            cr.data_emissao,
            cr.data_lancamento,
            cr.data_vencimento,
            cr.empresa_cnpj,
            cr.bandeira_nome AS bandeira,
            cr.cnpj_cpf,
            cr.razao_social,
            cr.numero_documento,
            cr.numero_documento_fiscal,
            cr.numero_contrato,
            cr.codigo_categoria_expl,
            cr.percentual_categoria,
            co.descricao AS descricao_cat,
            cr.valor_conta,
            cr.pagamento_parcial,
            cr.status_titulo AS situacao,
            dep.elem ->> 'cCodDep'::text AS ccoddep,
            (dep.elem ->> 'nPerDep'::text)::numeric AS percentual_departamento
           FROM contas_receber_sb cr
             LEFT JOIN categorias_omie co ON co.codigo::text = cr.codigo_categoria_expl AND co.empresa_cnpj = cr.empresa_cnpj
             LEFT JOIN LATERAL ( SELECT elem.value AS elem
                   FROM jsonb_array_elements(
                        CASE
                            WHEN cr.departamentos IS NOT NULL AND jsonb_typeof(cr.departamentos) = 'array'::text AND jsonb_array_length(cr.departamentos) > 0 THEN cr.departamentos
                            ELSE '[{}]'::jsonb
                        END) elem(value)) dep ON true
        ), agrupando_valores AS (
         SELECT av.codigo_lancamento_omie,
            av.data_emissao,
            av.data_lancamento,
            av.data_vencimento,
            av.empresa_cnpj,
            av.bandeira,
            av.cnpj_cpf,
            av.razao_social,
            av.numero_documento,
            av.numero_documento_fiscal,
            av.numero_contrato,
            av.codigo_categoria_expl,
            av.percentual_categoria,
            av.descricao_cat,
            av.pagamento_parcial,
            av.situacao,
            sum(av.valor_conta) AS valor_conta,
            av.ccoddep,
            av.percentual_departamento
           FROM abrindo_valores av
          GROUP BY av.codigo_lancamento_omie, av.data_emissao, av.data_lancamento, av.data_vencimento, av.empresa_cnpj, av.bandeira, av.cnpj_cpf, av.razao_social, av.numero_documento, av.numero_documento_fiscal, av.numero_contrato, av.codigo_categoria_expl, av.percentual_categoria, av.descricao_cat, av.pagamento_parcial, av.situacao, av.ccoddep, av.percentual_departamento
        ), departamentos AS (
         SELECT av.codigo_lancamento_omie,
            av.data_emissao,
            av.data_lancamento,
            av.data_vencimento,
            av.bandeira,
            av.cnpj_cpf,
            av.razao_social,
            av.numero_documento,
            av.numero_documento_fiscal,
            av.numero_contrato,
            av.descricao_cat,
            av.percentual_categoria,
            av.pagamento_parcial,
            av.situacao,
            av.ccoddep,
            av.percentual_departamento,
            d.descricao AS descricao_dept,
            av.valor_conta * (av.percentual_departamento / 100::numeric) * (av.percentual_categoria / 100::numeric) AS valor_cat_dept
           FROM agrupando_valores av
             LEFT JOIN departamentos_omie d ON d.codigo::text = av.ccoddep AND d.empresa_cnpj = av.empresa_cnpj
          WHERE av.ccoddep IS NOT NULL
        ), sem_departamento AS (
         SELECT av.codigo_lancamento_omie,
            av.data_emissao,
            av.data_lancamento,
            av.data_vencimento,
            av.bandeira,
            av.cnpj_cpf,
            av.razao_social,
            av.numero_documento,
            av.numero_documento_fiscal,
            av.numero_contrato,
            av.descricao_cat,
            av.percentual_categoria,
            av.pagamento_parcial,
            av.situacao,
            NULL::text AS ccoddep,
            NULL::numeric AS percentual_departamento,
            NULL::text AS descricao_dept,
            av.valor_conta * (av.percentual_categoria / 100::numeric) AS valor_conta
           FROM abrindo_valores av
          WHERE NOT (av.codigo_lancamento_omie IN ( SELECT DISTINCT departamentos.codigo_lancamento_omie
                   FROM departamentos))
        ), agrupando AS (
         SELECT d.codigo_lancamento_omie,
            d.data_emissao,
            d.data_lancamento,
            d.data_vencimento,
            d.bandeira,
            d.cnpj_cpf,
            d.razao_social,
            d.numero_documento,
            d.numero_documento_fiscal,
            d.numero_contrato,
            d.descricao_cat,
            d.percentual_categoria,
            d.pagamento_parcial,
            d.situacao,
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
            sd.numero_documento,
            sd.numero_documento_fiscal,
            sd.numero_contrato,
            sd.descricao_cat,
            sd.percentual_categoria,
            sd.pagamento_parcial,
            sd.situacao,
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
            a.numero_documento,
            a.numero_documento_fiscal,
            a.numero_contrato,
            a.descricao_cat,
            a.percentual_categoria,
            a.pagamento_parcial,
            a.situacao,
            a.ccoddep,
            a.percentual_departamento,
            a.descricao_dept,
            a.valor_cat_dept,
                CASE
                    WHEN TRIM(BOTH FROM upper(a.descricao_cat::text)) ~~ '%RECEITA DE CONTABILIDADE RECORRENTE%'::text OR (upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE HOLDING'::text, 'RECEITA DE SERVIÇOS CONTÁBEIS'::text])) THEN 'CORPORATE'::text
                    WHEN regexp_replace(a.cnpj_cpf, '\D'::text, ''::text, 'g'::text) = ANY (ARRAY['12340921000182'::text, '62700834000167'::text, '44158057000199'::text, '01501108000120'::text, '23382154000190'::text, '42622192000118'::text, '56378880000199'::text, '36657397000136'::text, '39287808000137'::text, '36480461000156'::text, '27057563000172'::text, '36530240000145'::text, '39484812000195'::text, '37852789000119'::text, '42380661000130'::text, '14723195000102'::text, '34349108000106'::text, '42275720000100'::text, '08865854000142'::text, '36685910000100'::text, '47244267053'::text, '57341084000144'::text, '23448109000191'::text, '11863345000195'::text, '39349860000170'::text, '58420510000106'::text, '48552493000107'::text, '44189727000134'::text, '53192862000120'::text]) THEN 'INTER COMPANY'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['TAXAS DE FRANQUIA/ALIANÇA'::text, 'ROYALTIES/CRM'::text, 'RECEITA DE ROYALTIES/CRM'::text, 'ROYALTIES VARIÁVEIS'::text, 'RECEITA DE ROYALTIES VARIÁVEIS'::text, 'ROYALTIES ANTECIPADO'::text, 'RECEITA DE ROYALTIES ANTECIPADOS'::text, 'RECEITA DE ROYALTIES'::text, 'FRANCHISING - ROYALTIES'::text, 'RECEITA DE CRM'::text, 'FRANCHISING - CRM'::text]) THEN 'FRANCHISING'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE TAXAS DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE ROYALTIES ANTECIPADO'::text, 'RECEITA DE TREINAMENTO INTERNO'::text, 'EXPANSÃO - TAXA DE LICENCIAMENTO'::text, 'RECEITA DE TAXA DE FRANQUIA/ALIANÇA'::text, 'EXPANSÃO - TAXA DE FRANQUIA'::text, 'RECEITA DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE IMPLANTAÇÃO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS PJ360'::text, 'RECEITA DE LICENÇAS DE SOFWARES - PJ360'::text, 'RECEITA DE LICENÇAS DE SOFTWARES - PJ360'::text, 'RECEITA DE PRODUTOS/LOJA'::text]) THEN 'EXPANSÃO'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE TREINAMENTO EXTERNO'::text, 'RECEITA DE TREINAMENTOS'::text]) THEN 'EDUCAÇÃO'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE SERVIÇOS JURÍDICOS'::text, 'RECEITA DE RESTITUIÇÃO'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRI'::text, 'RECEITA DE RETIFICAÇÃO'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LOW)'::text, 'RECEITA DE TESES TRIBUTÁRIAS'::text, 'RECEITA DE TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE PRT'::text, 'RECEITA DE PROJETOS ESPECIAIS'::text, 'RECEITA DE TESES'::text, 'RECEITA DE PONTOS QUALIFICADOS'::text, 'RECEITA DE OPERAÇÃO DE JOBS (ÊXITO)'::text, 'CLIENTES - TRIBUTÁRIO'::text, 'CLIENTES - TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE COMPENSAÇÃO'::text, 'RECEITA DE PONTO QUALIFICADOS'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRIA'::text, 'RECEITA DE MAPA FISCAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LAW)'::text, 'RECEITA DE GESTÃO DO PASSIVO TRIBUTÁRIO'::text, 'RECEITA DE AJE - ASSESSORIA JURÍDICA EMPRESARIAL'::text, 'RECEITA DE LIQUIDAÇÃO'::text, 'RECEITA DE AJUIZAMENTO'::text, 'RECEITA DE AJUIZAMENTOS TRIBUTÁRIOS'::text, 'RECEITA DE LEI DO BEM'::text, 'RECEITA DE LIQUIDAÇÃO TRIBUTÁRIO'::text, 'CLIENTES - INTERMEDIAÇÕES DE NEGÓCIOS (JOBS)'::text, 'RECEITA DE SUBVENÇÃO FINEP'::text, 'RECEITA DE SUPPLY TAX'::text, 'RECEITA DE RENEGOCIAÇÃO DE DÍVIDAS'::text]) THEN 'TAX'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DA SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OFFSHORE'::text, 'RECEITA DE CONSULTORIA ESTRATÉGICA'::text, 'RECEITA DE AJUIZAMENTOS CÍVEIS'::text, 'RECEITA DE GESTÃO DE CARTEIRA DE INVESTIMENTOS'::text, 'RECEITA DE FINANCIAMENTO DE FRANQUIA'::text, 'RECEITA DE HOLDING GOVERNANÇA'::text, 'RECEITA DE ASSESSORIA JURÍDICA MENSAL'::text, 'ASSESSORIA JURÍDICA MENSAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OPERAÇÃO DE JOBS (RECORRENTE)'::text, 'RECEITA DE OPERAÇÃO DE JOBS - SPACEW'::text, 'RECEITA DE OPERAÇÃO DE JOBS - AGRO'::text, 'RECEITA DE OPERAÇÃO DE JOBS'::text, 'RECEITA DE MERCADO LIVRE'::text, 'RECEITA DA SERVIÇOS JURÍDICOS'::text, 'CLIENTES - HOLDING'::text, 'RECEITA DE CESSÃO/NEGOCIAÇÃO DE PRECATÓRIOS'::text, 'RECEITA DE OPERAÇÃO DE JOB'::text, 'RECEITA DE CAPTAÇÃO DE RECURSOS'::text, 'RECEITA DE SEGUROS'::text, 'RECEITA DE MEA'::text, 'BPO FINANCEIRO'::text, 'RECEITA DE VALUATION'::text, 'RECEITA DE ASSINATURA DE ENERGIA'::text, 'RECEITA DE ENERGY GERAÇÃO - GD'::text, 'RECEITA DE HOLDING ITBI'::text, 'RECEITA DE SERVIÇOS JURIDICOS'::text, 'RECEITA DE AVALIAÇÃO PATRIMONIAL'::text, 'RECEITA DE ENERGY ASSESSORIA - RCE'::text, 'RECEITA DE FINANCIAMENTO - AMORTIZAÇÃO DE CRÉDITO'::text, 'RECEITA DE FINANCIAMENTO - RENDIMENTO DE FINANCIAMENTO'::text, 'RECEITA DE RECUPERA ENERGIA'::text, 'RECEITA DE ANTEPICAÇÃO DE RECEBÍVEIS'::text, 'RECEITA DE ANTECIPAÇÃO DE RECEBÍVEIS'::text]) THEN 'CORPORATE'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE SUPORTE E CONSULTORIA EM TI'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITACARD'::text, 'CLIENTES - LOCAÇÃO DE EQUIPAMENTOS E SUPORTE TI'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS GS'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS EXTERNO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITATAX'::text, 'RECEITA AUDITACARD'::text]) THEN 'TECNOLOGIA'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['SERVIÇOS ADMINISTRATIVOS'::text, 'REPASSE'::text, 'REEMBOLSO DE DESPESAS'::text, 'RECEITA IMPRESSÕES'::text, 'RECEITA IMPORTAÇÃO FINANCEIRO GS'::text, 'RECEITA DE MARKETING'::text, 'RECEITA DE LOJA'::text, 'RECEITA A IDENTIFICAR'::text, 'PRODUTOS/LOJA'::text, 'DISTRIBUIÇÃO DE LUCROS'::text, 'DEVOLUÇÃO PAGAMENTO EFETUADO'::text, 'DEVOLUÇÃO DE SERVIÇO PRESTADO'::text, 'DEVOLUÇÃO DE PAGAMENTO FEITO'::text, 'DEVOLUÇÃO DE PAGAMENTOS FEITOS'::text, 'APLICAÇÃO PARA EMPRÉSTIMOS'::text, '<DISPONÍVEL>'::text, 'RENDIMENTO DE APLICAÇÃO FINANCEIRA'::text, 'RECEITA DE VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text, 'RECEITA DHO'::text, 'VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text, 'RECEITA SOCIAL MÍDIA DE ALTA PERFORMANCE'::text, 'RESGATE DE APLICAÇÃO FINANCEIRA'::text, 'RESGATE DE APLICAÇÕES FINANCEIRAS'::text, 'RECEITA DIVERSA'::text, 'RECEITA DE SERVIÇO DE IMPRESSÃO'::text, 'DEVOLUÇÃO DE CAPITAL DE GIRO'::text, 'DESCONTOS OBTIDOS'::text, 'RECEITA DE SERVIÇOS DE IMPRESSÃO'::text, 'RESTITUIÇÃO E RECUPERAÇÃO DE TRIBUTOS'::text, 'TAXAS BANCÁRIAS'::text, 'RECUPERAÇÃO DE DEPÓSITOS JUDICIAIS'::text]) THEN 'OUTRAS RECEITAS'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE TRANSFERÊNCIA ENTRE EMPRESAS DO GRUPO'::text, 'APORTE DE CAPITAL'::text, 'RECEITA DE EMPRÉSTIMOS ENTRE EMPRESAS'::text, 'TRANSFERÊNCIA ENTRE CONTAS'::text, 'CAPITAL DE GIRO'::text, 'ADIANTAMENTO RECEBIDO REPASSES FUTUROS'::text, 'RECEITA INTERCOMPANY'::text, 'RECEITA DE FUNDO DE MARKETING/ADMINISTRATIVO'::text, 'ENTRADA DE TRANSFERÊNCIAS'::text, 'ANTECIPAÇÃO DE LUCROS'::text]) THEN 'INTER COMPANY'::text
                    WHEN upper(a.descricao_cat::text) = ANY (ARRAY['RECEITA DE LOCAÇÃO DE ESPAÇO E ESTACIONAMENTO'::text, 'RECEITA DE LOCAÇÃO DE ESPAÇO'::text, 'RECEITA DE ESTACIONAMENTO'::text, 'RECEITA DE COWORKING'::text, 'RECEITA DE CESSÃO DE USO DE IMÓVEL'::text]) THEN 'ADMINISTRAÇÃO'::text
                    ELSE 'SEM CATEGORIA'::text
                END AS categoria
           FROM agrupando a
          WHERE a.data_lancamento >= '2026-01-01'::date
        )
 SELECT row_number() OVER () AS id,
    codigo_lancamento_omie,
    data_emissao,
    data_lancamento,
    data_vencimento,
    bandeira,
    cnpj_cpf,
    razao_social,
    numero_documento,
    numero_documento_fiscal,
    numero_contrato,
    descricao_cat,
    percentual_categoria,
    ccoddep,
    percentual_departamento,
    descricao_dept,
    round(valor_cat_dept, 2) AS valor_bruto,
    categoria,
    pagamento_parcial,
    situacao
   FROM classificando c;


-- painel_contas_pagar
-- origem: producao (banco vivo, 02/09/2026)
DROP VIEW IF EXISTS public.painel_contas_pagar CASCADE;
CREATE OR REPLACE VIEW public.painel_contas_pagar AS
 WITH clientesunicos AS (
         SELECT DISTINCT ON (clientes_grupo.codigo_cliente_omie, clientes_grupo.empresa_cnpj) clientes_grupo.codigo_cliente_omie,
            clientes_grupo.empresa_nome,
            clientes_grupo.empresa_cnpj,
            clientes_grupo.cnpj_cpf,
            clientes_grupo.razao_social,
            clientes_grupo.nome_fantasia,
            clientes_grupo.data_integracao
           FROM clientes_grupo
          ORDER BY clientes_grupo.codigo_cliente_omie, clientes_grupo.empresa_cnpj
        ), categoriasunicas AS (
         SELECT DISTINCT ON (categorias_omie.codigo, categorias_omie.empresa_cnpj) categorias_omie.codigo,
            categorias_omie.empresa_nome,
            categorias_omie.empresa_cnpj,
            categorias_omie.descricao,
            categorias_omie.descricao_padrao,
            categorias_omie.categoria_superior,
            categorias_omie.conta_despesa,
            categorias_omie.conta_receita,
            categorias_omie.conta_inativa,
            categorias_omie.definida_pelo_usuario,
            categorias_omie.nao_exibir,
            categorias_omie.totalizadora,
            categorias_omie.transferencia,
            categorias_omie.codigo_dre,
            categorias_omie.id_conta_contabil,
            categorias_omie.tag_conta_contabil,
            categorias_omie.natureza,
            categorias_omie.tipo_categoria,
            categorias_omie.dados_dre,
            categorias_omie.last_update,
            categorias_omie.codigo_valores_unidades,
            categorias_omie.bandeiras
           FROM categorias_omie
          ORDER BY categorias_omie.codigo, categorias_omie.empresa_cnpj
        ), departamentosunicos AS (
         SELECT DISTINCT ON (departamentos_omie.codigo, departamentos_omie.empresa_cnpj) departamentos_omie.codigo,
            departamentos_omie.descricao,
            departamentos_omie.estrutura,
            departamentos_omie.inativo,
            departamentos_omie.bandeira_id,
            departamentos_omie.empresa_nome,
            departamentos_omie.empresa_cnpj
           FROM departamentos_omie
          ORDER BY departamentos_omie.codigo, departamentos_omie.empresa_cnpj
        ), base_cp_raw AS (
         SELECT cp.empresa_nome,
            cp.empresa_cnpj,
            cl.cnpj_cpf AS cnpj,
            cl.razao_social,
            cp.data_vencimento,
            cp.data_previsao,
            COALESCE(to_date(NULLIF((cp.json_bruto -> 'info'::text) ->> 'dDtPagamento'::text, ''::text), 'DD/MM/YYYY'::text), to_date(NULLIF((cp.json_bruto -> 'info'::text) ->> 'dDtBaixa'::text, ''::text), 'DD/MM/YYYY'::text), to_date(NULLIF((cp.json_bruto -> 'resumo'::text) ->> 'dDtBaixa'::text, ''::text), 'DD/MM/YYYY'::text), to_date(NULLIF(cp.json_bruto ->> 'data_pagamento'::text, ''::text), 'DD/MM/YYYY'::text), to_date(NULLIF(cp.json_bruto ->> 'data_baixa'::text, ''::text), 'DD/MM/YYYY'::text), cc.max_data_lancamento, cp.data_vencimento) AS data_lancamento,
            cp.codigo_lancamento_omie,
                CASE
                    WHEN cc.id_origem_pagar IS NOT NULL THEN 'PAGO (No Banco)'::character varying
                    ELSE cp.status_titulo
                END AS status_titulo,
            COALESCE(cp.codigo_cliente_fornecedor, cc.id_cliente_fornecedor) AS codigo_cliente_fornecedor,
            cat.descricao AS categoria,
            dep_omie.descricao AS departamento,
                CASE
                    WHEN regexp_replace(cl.cnpj_cpf, '\D'::text, ''::text, 'g'::text) = ANY (ARRAY['12340921000182'::text, '62700834000167'::text, '44158057000199'::text, '01501108000120'::text, '23382154000190'::text, '42622192000118'::text, '56378880000199'::text, '36657397000136'::text, '39287808000137'::text, '36480461000156'::text, '27057563000172'::text, '36530240000145'::text, '39484812000195'::text, '37852789000119'::text, '42380661000130'::text, '14723195000102'::text, '34349108000106'::text, '42275720000100'::text, '08865854000142'::text, '36685910000100'::text, '47244267053'::text, '57341084000144'::text, '23448109000191'::text, '11863345000195'::text, '39349860000170'::text, '58420510000106'::text, '48552493000107'::text, '44189727000134'::text, '53192862000120'::text]) THEN true
                    ELSE false
                END AS is_intercompany,
            COALESCE(cx.percentual, 100::numeric) / 100.0 AS pct_cat,
            COALESCE(dx."nPerDep", dx."nPerc", dx."nValDep" / NULLIF(cp.valor_documento, 0::numeric) * 100::numeric, 100::numeric) / 100.0 AS pct_dep,
            cc.soma_valor_banco,
                CASE
                    WHEN jsonb_typeof(cp.categorias) = 'array'::text AND jsonb_array_length(cp.categorias) > 1 OR jsonb_typeof(cp.distribuicao::jsonb) = 'array'::text AND jsonb_array_length(cp.distribuicao::jsonb) > 1 THEN true
                    ELSE false
                END AS tem_rateio,
                CASE
                    WHEN cc.soma_valor_banco > (cp.valor_documento * 1.2) THEN true
                    ELSE false
                END AS is_lote,
            round((- (COALESCE(cx.percentual, 100::numeric) / 100.0 * cp.valor_documento)) * (COALESCE(dx."nPerDep", dx."nPerc", dx."nValDep" / NULLIF(cp.valor_documento, 0::numeric) * 100::numeric, 100::numeric) / 100.0), 2) AS valor_original,
            round((- (COALESCE(cx.percentual, 100::numeric) / 100.0 * COALESCE(NULLIF(((cp.json_bruto -> 'resumo'::text) ->> 'nValJuros'::text)::numeric, 0::numeric), NULLIF((((cp.json_bruto -> 'lista_recibos'::text) -> 0) ->> 'nValJuros'::text)::numeric, 0::numeric), NULLIF((((cp.json_bruto -> 'titulos_baixados'::text) -> 0) ->> 'nValJuros'::text)::numeric, 0::numeric), NULLIF(cp.valor_juros, 0::numeric), 0::numeric))) * (COALESCE(dx."nPerDep", dx."nPerc", dx."nValDep" / NULLIF(cp.valor_documento, 0::numeric) * 100::numeric, 100::numeric) / 100.0), 2) AS valor_juros,
            round((- (COALESCE(cx.percentual, 100::numeric) / 100.0 * COALESCE(NULLIF(((cp.json_bruto -> 'resumo'::text) ->> 'nValMulta'::text)::numeric, 0::numeric), NULLIF((((cp.json_bruto -> 'lista_recibos'::text) -> 0) ->> 'nValMulta'::text)::numeric, 0::numeric), NULLIF((((cp.json_bruto -> 'titulos_baixados'::text) -> 0) ->> 'nValMulta'::text)::numeric, 0::numeric), NULLIF(cp.valor_multa, 0::numeric), 0::numeric))) * (COALESCE(dx."nPerDep", dx."nPerc", dx."nValDep" / NULLIF(cp.valor_documento, 0::numeric) * 100::numeric, 100::numeric) / 100.0), 2) AS valor_multa,
            round(COALESCE(cx.percentual, 100::numeric) / 100.0 * COALESCE(NULLIF(((cp.json_bruto -> 'resumo'::text) ->> 'nValDesconto'::text)::numeric, 0::numeric), NULLIF((((cp.json_bruto -> 'lista_recibos'::text) -> 0) ->> 'nValDesconto'::text)::numeric, 0::numeric), NULLIF((((cp.json_bruto -> 'titulos_baixados'::text) -> 0) ->> 'nValDesconto'::text)::numeric, 0::numeric), NULLIF(cp.valor_desconto, 0::numeric), 0::numeric) * (COALESCE(dx."nPerDep", dx."nPerc", dx."nValDep" / NULLIF(cp.valor_documento, 0::numeric) * 100::numeric, 100::numeric) / 100.0), 2) AS valor_desconto
           FROM contas_pagar cp
             LEFT JOIN ( SELECT conta_corrente.id_origem_pagar,
                    conta_corrente.empresa_cnpj,
                    max(conta_corrente.data_lancamento) AS max_data_lancamento,
                    max(conta_corrente.id_cliente_fornecedor) AS id_cliente_fornecedor,
                    sum(abs(conta_corrente.valor)) AS soma_valor_banco
                   FROM conta_corrente
                  WHERE conta_corrente.id_origem_pagar IS NOT NULL
                  GROUP BY conta_corrente.id_origem_pagar, conta_corrente.empresa_cnpj) cc ON cc.id_origem_pagar = cp.codigo_lancamento_omie AND cc.empresa_cnpj = cp.empresa_cnpj::text
             LEFT JOIN LATERAL jsonb_to_recordset(
                CASE
                    WHEN jsonb_typeof(cp.categorias) = 'array'::text AND jsonb_array_length(cp.categorias) > 0 THEN cp.categorias
                    ELSE jsonb_build_array(jsonb_build_object('codigo_categoria', cp.codigo_categoria, 'percentual', 100, 'valor', cp.valor_documento))
                END) cx(codigo_categoria text, percentual numeric, valor numeric) ON true
             LEFT JOIN LATERAL jsonb_to_recordset(
                CASE
                    WHEN jsonb_typeof(cp.distribuicao::jsonb) = 'array'::text AND jsonb_array_length(cp.distribuicao::jsonb) > 0 THEN cp.distribuicao::jsonb
                    ELSE jsonb_build_array(jsonb_build_object('cCodDep', NULL::text, 'nPerDep', 100, 'nPerc', 100, 'nValDep', NULL::numeric))
                END) dx("cCodDep" text, "nPerDep" numeric, "nPerc" numeric, "nValDep" numeric) ON true
             LEFT JOIN clientesunicos cl ON cl.codigo_cliente_omie = COALESCE(cp.codigo_cliente_fornecedor, cc.id_cliente_fornecedor) AND cl.empresa_cnpj = cp.empresa_cnpj::text
             LEFT JOIN categoriasunicas cat ON cat.codigo::text = cx.codigo_categoria AND cat.empresa_cnpj = cp.empresa_cnpj::text
             LEFT JOIN departamentosunicos dep_omie ON dep_omie.codigo::text = dx."cCodDep" AND dep_omie.empresa_cnpj = cp.empresa_cnpj::text
        ), base_cp AS (
         SELECT base_cp_raw.empresa_nome,
            base_cp_raw.empresa_cnpj,
            base_cp_raw.cnpj,
            base_cp_raw.razao_social,
            base_cp_raw.data_vencimento,
            base_cp_raw.data_previsao,
            base_cp_raw.data_lancamento,
            base_cp_raw.codigo_lancamento_omie,
            base_cp_raw.status_titulo,
            base_cp_raw.codigo_cliente_fornecedor,
            base_cp_raw.categoria,
            base_cp_raw.departamento,
            base_cp_raw.is_intercompany,
                CASE
                    WHEN base_cp_raw.status_titulo::text = 'PAGO'::text OR base_cp_raw.status_titulo::text = 'PAGO (No Banco)'::text THEN
                    CASE
                        WHEN base_cp_raw.tem_rateio = true AND base_cp_raw.is_lote = true THEN base_cp_raw.valor_original + base_cp_raw.valor_juros + base_cp_raw.valor_multa + base_cp_raw.valor_desconto
                        ELSE round((- COALESCE(base_cp_raw.soma_valor_banco, abs(base_cp_raw.valor_original + base_cp_raw.valor_juros + base_cp_raw.valor_multa + base_cp_raw.valor_desconto))) * base_cp_raw.pct_cat * base_cp_raw.pct_dep, 2)
                    END
                    ELSE base_cp_raw.valor_original
                END AS valor_final,
                CASE
                    WHEN base_cp_raw.status_titulo::text = 'PAGO'::text OR base_cp_raw.status_titulo::text = 'PAGO (No Banco)'::text THEN
                    CASE
                        WHEN base_cp_raw.tem_rateio = true AND base_cp_raw.is_lote = true THEN base_cp_raw.valor_original + base_cp_raw.valor_juros + base_cp_raw.valor_multa + base_cp_raw.valor_desconto
                        ELSE round((- COALESCE(base_cp_raw.soma_valor_banco, abs(base_cp_raw.valor_original + base_cp_raw.valor_juros + base_cp_raw.valor_multa + base_cp_raw.valor_desconto))) * base_cp_raw.pct_cat * base_cp_raw.pct_dep, 2)
                    END
                    ELSE 0::numeric
                END AS valor_pago,
            base_cp_raw.valor_original,
            base_cp_raw.valor_juros,
            base_cp_raw.valor_multa,
            base_cp_raw.valor_desconto
           FROM base_cp_raw
        ), base_cc AS (
         SELECT cc.empresa_nome,
            cc.empresa_cnpj,
            cl.cnpj_cpf AS cnpj,
            COALESCE(cl.razao_social, 'Lançamento Direto (Sem Favorecido)'::text) AS razao_social,
            cc.data_lancamento AS data_vencimento,
            cc.data_lancamento AS data_previsao,
            cc.data_lancamento,
            cc.codigo_lancamento AS codigo_lancamento_omie,
            'PAGO (No Banco)'::text AS status_titulo,
            cc.id_cliente_fornecedor AS codigo_cliente_fornecedor,
            COALESCE(cat.descricao, 'Despesa Bancária / Direta'::character varying) AS categoria,
            dep_omie.descricao AS departamento,
                CASE
                    WHEN regexp_replace(cl.cnpj_cpf, '\D'::text, ''::text, 'g'::text) = ANY (ARRAY['12340921000182'::text, '62700834000167'::text, '44158057000199'::text, '01501108000120'::text, '23382154000190'::text, '42622192000118'::text, '56378880000199'::text, '36657397000136'::text, '39287808000137'::text, '36480461000156'::text, '27057563000172'::text, '36530240000145'::text, '39484812000195'::text, '37852789000119'::text, '42380661000130'::text, '14723195000102'::text, '34349108000106'::text, '42275720000100'::text, '08865854000142'::text, '36685910000100'::text, '47244267053'::text, '57341084000144'::text, '23448109000191'::text, '11863345000195'::text, '39349860000170'::text, '58420510000106'::text, '48552493000107'::text, '44189727000134'::text, '53192862000120'::text]) THEN true
                    ELSE false
                END AS is_intercompany,
            round(
                CASE
                    WHEN cc.natureza::text = ANY (ARRAY['P'::text, 'S'::text, 'D'::text]) THEN '-1'::integer
                    ELSE 1
                END::numeric * COALESCE(cx."nValCateg", abs(cc.valor)) * (COALESCE(dx."nPerDep", dx."nPerc", 100::numeric) / 100.0), 2) AS valor_final,
            round(
                CASE
                    WHEN cc.natureza::text = ANY (ARRAY['P'::text, 'S'::text, 'D'::text]) THEN '-1'::integer
                    ELSE 1
                END::numeric * COALESCE(cx."nValCateg", abs(cc.valor)) * (COALESCE(dx."nPerDep", dx."nPerc", 100::numeric) / 100.0), 2) AS valor_pago,
            round(
                CASE
                    WHEN cc.natureza::text = ANY (ARRAY['P'::text, 'S'::text, 'D'::text]) THEN '-1'::integer
                    ELSE 1
                END::numeric * COALESCE(cx."nValCateg", abs(cc.valor)) * (COALESCE(dx."nPerDep", dx."nPerc", 100::numeric) / 100.0), 2) AS valor_original,
            0::numeric AS valor_juros,
            0::numeric AS valor_multa,
            0::numeric AS valor_desconto
           FROM conta_corrente cc
             LEFT JOIN LATERAL jsonb_to_recordset(
                CASE
                    WHEN jsonb_typeof(cc.categorias) = 'array'::text AND jsonb_array_length(cc.categorias) > 0 THEN cc.categorias
                    ELSE jsonb_build_array(jsonb_build_object('cCodCateg', cc.codigo_categoria, 'nValCateg', abs(cc.valor)))
                END) cx("cCodCateg" text, "nValCateg" numeric) ON true
             LEFT JOIN LATERAL jsonb_to_recordset(
                CASE
                    WHEN jsonb_typeof(cc.departamentos) = 'array'::text AND jsonb_array_length(cc.departamentos) > 0 THEN cc.departamentos
                    ELSE jsonb_build_array(jsonb_build_object('cCodDep', NULL::text, 'nPerDep', 100, 'nPerc', 100, 'nValDep', NULL::numeric))
                END) dx("cCodDep" text, "nPerDep" numeric, "nPerc" numeric, "nValDep" numeric) ON true
             LEFT JOIN clientesunicos cl ON cl.codigo_cliente_omie = cc.id_cliente_fornecedor AND cl.empresa_cnpj = cc.empresa_cnpj
             LEFT JOIN categoriasunicas cat ON cat.codigo::text = cx."cCodCateg" AND cat.empresa_cnpj = cc.empresa_cnpj
             LEFT JOIN departamentosunicos dep_omie ON dep_omie.codigo::text = dx."cCodDep" AND dep_omie.empresa_cnpj = cc.empresa_cnpj
          WHERE cc.id_origem_pagar IS NULL AND (cc.id_origem_receber IS NULL OR (cc.natureza::text = ANY (ARRAY['P'::text, 'S'::text, 'D'::text])))
        )
 SELECT base_cp.empresa_nome,
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
   FROM base_cp
  WHERE base_cp.valor_final <= 0::numeric
UNION ALL
 SELECT base_cc.empresa_nome,
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
   FROM base_cc
  WHERE base_cc.valor_final <= 0::numeric;


-- view_contas_pagar
-- origem: recuperada (fix_supabase.sql @ af5b3c2)
DROP VIEW IF EXISTS public.view_contas_pagar CASCADE;
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


-- view_contas_receber
-- origem: recuperada (fix_supabase.sql @ af5b3c2)
DROP VIEW IF EXISTS public.view_contas_receber CASCADE;
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


-- view_faturamento_rateado
-- origem: recuperada (fix_supabase.sql @ af5b3c2)
DROP VIEW IF EXISTS public.view_faturamento_rateado CASCADE;
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


-- view_inadimplencia
-- origem: recuperada (fix_supabase.sql @ af5b3c2)
DROP VIEW IF EXISTS public.view_inadimplencia CASCADE;
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


-- vw_contas_receber_detalhada
-- origem: recuperada (fix_supabase.sql @ af5b3c2)
DROP VIEW IF EXISTS public.vw_contas_receber_detalhada CASCADE;
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

-- =============================== SEGURANCA ===============================
-- RLS ligado em todas as tabelas, SEM politicas: as chaves publicas (anon e
-- publishable) nao leem nem gravam nada pela API REST. Quem continua com acesso:
--   - service_role (a automacao): ignora RLS por definicao;
--   - usuario postgres (Power BI e clientes SQL): dono das tabelas, nao e
--     afetado por RLS.
-- As views passam a rodar com as permissoes de quem consulta (security_invoker);
-- sem isso elas seriam uma porta lateral contornando o RLS das tabelas.
--
-- Ate 04/10/2026 o banco foi recriado sem isto e a chave anon - que o Supabase
-- trata como publica - podia ler, inserir e apagar qualquer dado.

ALTER TABLE public.categorias_omie ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clientes_grupo ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conta_corrente ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contas_pagar ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contas_receber_grupo ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.departamentos_omie ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.extrato_bancario ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.movimentos_financeiros ENABLE ROW LEVEL SECURITY;

ALTER VIEW public.metas SET (security_invoker = on);
ALTER VIEW public.metas_bruto SET (security_invoker = on);
ALTER VIEW public.painel_contas_pagar SET (security_invoker = on);
ALTER VIEW public.view_contas_pagar SET (security_invoker = on);
ALTER VIEW public.view_contas_receber SET (security_invoker = on);
ALTER VIEW public.view_faturamento_rateado SET (security_invoker = on);
ALTER VIEW public.view_inadimplencia SET (security_invoker = on);
ALTER VIEW public.vw_contas_receber_detalhada SET (security_invoker = on);
