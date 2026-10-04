create view view_metas
            (id, codigo_lancamento_omie, data_emissao, data_lancamento, data_vencimento, bandeira, cnpj_cpf,
             razao_social, descricao_cat, percentual_categoria, ccoddep, percentual_departamento, descricao_dept,
             valor_conta, categoria)
as
WITH contas_receber_sb AS (SELECT cr.codigo_lancamento_omie,
                                  cr.bandeira,
                                  cr.codigo_lancamento_integracao,
                                  cr.codigo_cliente_fornecedor,
                                  cr.data_emissao,
                                  cr.data_vencimento,
                                  cr.data_previsao,
                                  cr.data_registro,
                                  cr.valor_documento,
                                  cr.numero_documento,
                                  cr.numero_parcela,
                                  cr.numero_pedido,
                                  cr.codigo_categoria,
                                  cr.codigo_projeto,
                                  cr.codigo_vendedor,
                                  cr.id_origem,
                                  cr.status_titulo,
                                  cr.codigo_tipo_documento,
                                  cr.operacao,
                                  cr.situacao,
                                  cr.retem_pis,
                                  cr.retem_cofins,
                                  cr.retem_csll,
                                  cr.retem_ir,
                                  cr.retem_iss,
                                  cr.retem_inss,
                                  cr.boleto_gerado,
                                  cr.boleto_data_emissao,
                                  cr.boleto_numero,
                                  cr.boleto_juros,
                                  cr.boleto_multa,
                                  cr.codigo_barras_ficha_compensacao,
                                  cr.last_update,
                                  cr.info,
                                  cr.distribuicao,
                                  cr.numero_documento_fiscal,
                                  cr.valor_pis,
                                  cr.valor_cofins,
                                  cr.valor_csll,
                                  cr.valor_ir,
                                  cr.categorias,
                                  cc.departamentos,
                                  cc.data_lancamento,
                                  oc.cnpj_cpf,
                                  oc.razao_social,
                                  bo.codigo                                                                  AS codigo_bandeira,
                                  bo.nome                                                                    AS bandeira_nome,
                                  COALESCE(cat.elem ->> 'codigo_categoria'::text,
                                           cr.codigo_categoria::text)                                        AS codigo_categoria_expl,
                                  COALESCE((cat.elem ->> 'percentual'::text)::numeric, 100::numeric)         AS percentual_categoria,
                                  COALESCE(cc.valor, 0::numeric)                                             AS valor_conta
                           FROM contas_receber cr
                                    LEFT JOIN conta_corrente cc ON cr.codigo_lancamento_omie = cc.id_origem_receber
                                    LEFT JOIN omie_clientes oc ON cr.codigo_cliente_fornecedor = oc.codigo_cliente_omie
                                    LEFT JOIN bandeiras_omie bo ON bo.codigo = cr.bandeira
                                    LEFT JOIN LATERAL ( SELECT elem.value AS elem
                                                        FROM jsonb_array_elements((cr.categorias #>> '{}'::text[])::jsonb) elem(value)) cat
                                              ON true),
     abrindo_valores AS (SELECT cr.codigo_lancamento_omie,
                                cr.data_emissao,
                                cr.data_lancamento,
                                cr.data_vencimento,
                                cr.codigo_bandeira,
                                cr.bandeira_nome                        AS bandeira,
                                cr.cnpj_cpf,
                                cr.razao_social,
                                cr.codigo_categoria_expl,
                                cr.percentual_categoria,
                                co.descricao                            AS descricao_cat,
                                cr.valor_conta,
                                dep.elem ->> 'cCodDep'::text            AS ccoddep,
                                (dep.elem ->> 'nPerDep'::text)::numeric AS percentual_departamento
                         FROM contas_receber_sb cr
                                  LEFT JOIN categorias_omie co ON co.codigo::text = cr.codigo_categoria_expl AND
                                                                  co.bandeiras = cr.codigo_bandeira
                                  LEFT JOIN LATERAL ( SELECT elem.value AS elem
                                                      FROM jsonb_array_elements((cr.departamentos #>> '{}'::text[])::jsonb) elem(value)) dep
                                            ON true),
     agrupando_valores AS (SELECT av.codigo_lancamento_omie,
                                  av.data_emissao,
                                  av.data_lancamento,
                                  av.data_vencimento,
                                  av.codigo_bandeira,
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
                           GROUP BY av.codigo_lancamento_omie, av.data_emissao, av.data_lancamento, av.data_vencimento,
                                    av.codigo_bandeira, av.bandeira, av.cnpj_cpf, av.razao_social,
                                    av.codigo_categoria_expl, av.percentual_categoria, av.descricao_cat, av.ccoddep,
                                    av.percentual_departamento),
     departamentos AS (SELECT av.codigo_lancamento_omie,
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
                              d.descricao  AS descricao_dept,
                              av.valor_conta * av.percentual_departamento / 100::numeric * av.percentual_categoria /
                              100::numeric AS valor_cat_dept
                       FROM agrupando_valores av
                                LEFT JOIN departamentos_omie d ON d.codigo::text = av.ccoddep
                       WHERE av.ccoddep IS NOT NULL),
     sem_departamento AS (SELECT av.codigo_lancamento_omie,
                                 av.data_emissao,
                                 av.data_lancamento,
                                 av.data_vencimento,
                                 av.bandeira,
                                 av.cnpj_cpf,
                                 av.razao_social,
                                 av.descricao_cat,
                                 av.percentual_categoria,
                                 NULL::text    AS ccoddep,
                                 NULL::numeric AS percentual_departamento,
                                 NULL::text    AS descricao_dept,
                                 av.valor_conta
                          FROM abrindo_valores av
                          WHERE NOT (av.codigo_lancamento_omie IN (SELECT DISTINCT departamentos.codigo_lancamento_omie
                                                                   FROM departamentos))),
     agrupando AS (SELECT d.codigo_lancamento_omie,
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
                   FROM sem_departamento sd),
     classificando AS (SELECT a.codigo_lancamento_omie,
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
                                  WHEN TRIM(BOTH FROM upper(a.descricao_cat::text)) ~~
                                       '%RECEITA DE CONTABILIDADE RECORRENTE%'::text OR
                                       (upper(a.descricao_cat::text) = ANY
                                        (ARRAY ['RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE MERCADO LIVRE DE ENERGIA'::text]))
                                      THEN 'CORPORATE'::text
                                  WHEN a.cnpj_cpf::text = ANY
                                       (ARRAY ['12340921000182'::text, '62700834000167'::text, '44158057000199'::text, '01501108000120'::text, '23382154000190'::text, '42622192000118'::text, '56378880000199'::text, '36657397000136'::text, '39287808000137'::text, '36480461000156'::text, '27057563000172'::text, '36530240000145'::text, '39484812000195'::text, '37852789000119'::text, '42380661000130'::text, '14723195000102'::text, '34349108000106'::text, '42275720000100'::text, '08865854000142'::text, '36685910000100'::text, '47244267053'::text, '57341084000144'::text, '23448109000191'::text, '11863345000195'::text, '39349860000170'::text, '58420510000106'::text, '48552493000107'::text, '44189727000134'::text, '53192862000120'::text])
                                      THEN 'INTER COMPANY'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['TAXAS DE FRANQUIA/ALIANÇA'::text, 'ROYALTIES/CRM'::text, 'RECEITA DE ROYALTIES/CRM'::text, 'ROYALTIES VARIÁVEIS'::text, 'RECEITA DE ROYALTIES VARIÁVEIS'::text, 'ROYALTIES ANTECIPADO'::text, 'RECEITA DE ROYALTIES ANTECIPADOS'::text, 'RECEITA DE ROYALTIES'::text, 'FRANCHISING - ROYALTIES'::text, 'RECEITA DE CRM'::text, 'FRANCHISING - CRM'::text])
                                      THEN 'FRANCHISING'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DE TAXAS DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE ROYALTIES ANTECIPADO'::text, 'RECEITA DE TREINAMENTO INTERNO'::text, 'EXPANSÃO - TAXA DE LICENCIAMENTO'::text, 'RECEITA DE TAXA DE FRANQUIA/ALIANÇA'::text, 'EXPANSÃO - TAXA DE FRANQUIA'::text, 'RECEITA DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE IMPLANTAÇÃO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS PJ360'::text])
                                      THEN 'EXPANSÃO'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DE TREINAMENTO EXTERNO'::text, 'RECEITA DE TREINAMENTOS'::text])
                                      THEN 'EDUCAÇÃO'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DE SERVIÇOS JURÍDICOS'::text, 'RECEITA DE RESTITUIÇÃO'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRI'::text, 'RECEITA DE RETIFICAÇÃO'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LOW)'::text, 'RECEITA DE TESES TRIBUTÁRIAS'::text, 'RECEITA DE TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE PRT'::text, 'RECEITA DE PROJETOS ESPECIAIS'::text, 'RECEITA DE TESES'::text, 'RECEITA DE PONTOS QUALIFICADOS'::text, 'RECEITA DE OPERAÇÃO DE JOBS (ÊXITO)'::text, 'CLIENTES - TRIBUTÁRIO'::text, 'CLIENTES - TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE COMPENSAÇÃO'::text, 'RECEITA DE PONTO QUALIFICADOS'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRIA'::text, 'RECEITA DE MAPA FISCAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LAW)'::text, 'RECEITA DE GESTÃO DO PASSIVO TRIBUTÁRIO'::text, 'RECEITA DE AJE - ASSESSORIA JURÍDICA EMPRESARIAL'::text, 'RECEITA DE LIQUIDAÇÃO'::text, 'RECEITA DE AJUIZAMENTO'::text, 'RECEITA DE AJUIZAMENTOS TRIBUTÁRIOS'::text, 'RECEITA DE LIQUIDAÇÃO TRIBUTÁRIO'::text, 'CLIENTES - INTERMEDIAÇÕES DE NEGÓCIOS (JOBS)'::text])
                                      THEN 'TAX'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DA SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OFFSHORE'::text, 'RECEITA DE CONSULTORIA ESTRATÉGICA'::text, 'RECEITA DE AJUIZAMENTOS CÍVEIS'::text, 'RECEITA DE GESTÃO DE CARTEIRA DE INVESTIMENTOS'::text, 'RECEITA DE RENEGOCIAÇÃO DE DÍVIDAS'::text, 'RECEITA DE FINANCIAMENTO DE FRANQUIA'::text, 'RECEITA DE FINANCIAMENTO DE FRANQUIA'::text, 'RECEITA DE HOLDING GOVERNANÇA'::text, 'RECEITA DE ASSESSORIA JURÍDICA MENSAL'::text, 'ASSESSORIA JURÍDICA MENSAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OPERAÇÃO DE JOBS (RECORRENTE)'::text, 'RECEITA DE OPERAÇÃO DE JOBS - SPACEW'::text, 'RECEITA DE OPERAÇÃO DE JOBS - AGRO'::text, 'RECEITA DE OPERAÇÃO DE JOBS'::text, 'RECEITA DE MERCADO LIVRE'::text, 'RECEITA DE HOLDING'::text, 'RECEITA DA SERVIÇOS JURÍDICOS'::text, 'CLIENTES - HOLDING'::text, 'RECEITA DE CESSÃO/NEGOCIAÇÃO DE PRECATÓRIOS'::text, 'RECEITA DE OPERAÇÃO DE JOB'::text, 'RECEITA DE CAPTAÇÃO DE RECURSOS'::text, 'RECEITA DE SEGUROS'::text, 'RECEITA DE MEA'::text, 'BPO FINANCEIRO'::text, 'RECEITA DE VALUATION'::text, 'RECEITA DE ASSINATURA DE ENERGIA'::text, 'RECEITA DE ENERGY GERAÇÃO - GD'::text, 'RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE SERVIÇOS CONTÁBEIS'::text, 'RECEITA DE HOLDING ITBI'::text, 'RECEITA DE SERVIÇOS JURIDICOS'::text, 'RECEITA DE AVALIAÇÃO PATRIMONIAL'::text, 'RECEITA DE ENERGY ASSESSORIA - RCE'::text, 'RECEITA DE FINANCIAMENTO - AMORTIZAÇÃO DE CRÉDITO'::text])
                                      THEN 'CORPORATE'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DE SUPORTE E CONSULTORIA EM TI'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITACARD'::text, 'CLIENTES - LOCAÇÃO DE EQUIPAMENTOS E SUPORTE TI'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS GS'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS EXTERNO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITATAX'::text, 'RECEITA AUDITACARD'::text])
                                      THEN 'TECNOLOGIA'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['SERVIÇOS ADMINISTRATIVOS'::text, 'REPASSE'::text, 'REEMBOLSO DE DESPESAS'::text, 'RECEITA IMPRESSÕES'::text, 'RECEITA IMPORTAÇÃO FINANCEIRO GS'::text, 'RECEITA DE MARKETING'::text, 'RECEITA DE LOJA'::text, 'RECEITA A IDENTIFICAR'::text, 'PRODUTOS/LOJA'::text, 'DISTRIBUIÇÃO DE LUCROS'::text, 'DEVOLUÇÃO PAGAMENTO EFETUADO'::text, 'DEVOLUÇÃO DE SERVIÇO PRESTADO'::text, 'DEVOLUÇÃO DE PAGAMENTO FEITO'::text, 'DEVOLUÇÃO DE PAGAMENTOS FEITOS'::text, 'APLICAÇÃO PARA EMPRÉSTIMOS'::text, '<DISPONÍVEL>'::text, 'RENDIMENTO DE APLICAÇÃO FINANCEIRA'::text, 'RECEITA DE VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text, 'RECEITA DHO'::text, 'VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text])
                                      THEN 'OUTRAS RECEITAS'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DE TRANSFERÊNCIA ENTRE EMPRESAS DO GRUPO'::text, 'APORTE DE CAPITAL'::text, 'RECEITA DE EMPRÉSTIMOS ENTRE EMPRESAS'::text, 'TRANSFERÊNCIA ENTRE CONTAS'::text])
                                      THEN 'INTER COMPANY'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DE LOCAÇÃO DE ESPAÇO E ESTACIONAMENTO'::text, 'RECEITA DE LOCAÇÃO DE ESPAÇO'::text, 'RECEITA DE ESTACIONAMENTO'::text, 'RECEITA DE COWORKING'::text])
                                      THEN 'ADMINISTRAÇÃO'::text
                                  ELSE 'SEM CATEGORIA'::text
                                  END AS categoria
                       FROM agrupando a
                       WHERE a.data_lancamento >= '2026-01-01'::date)
SELECT row_number() OVER ()     AS id,
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

alter table view_metas
    owner to postgres;

