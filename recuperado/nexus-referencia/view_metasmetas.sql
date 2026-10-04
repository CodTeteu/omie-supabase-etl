create view view_metasmetas
            (id, codigo_lancamento_omie, data_emissao, data_lancamento, data_vencimento, bandeira, cnpj_cpf,
             razao_social, descricao_cat, ccoddep, descricao_dept, valor_conta, categoria)
as
WITH abrindo_valores AS (SELECT cr.codigo_lancamento_omie,
                                cr.data_emissao,
                                cr.data_lancamento,
                                cr.data_vencimento,
                                cr.bandeira,
                                cr.cnpj_cpf,
                                cr.razao_social,
                                cr.descricao                            AS descricao_cat,
                                dep.elem ->> 'cCodDep'::text            AS ccoddep,
                                (dep.elem ->> 'nValDep'::text)::numeric AS valor_conta
                         FROM view_contas_receber cr
                                  LEFT JOIN LATERAL ( SELECT elem.value AS elem
                                                      FROM jsonb_array_elements((cr.departamentos #>> '{}'::text[])::jsonb) elem(value)) dep
                                            ON true
                         WHERE cr.distribuicao IS NOT NULL),
     departamentos AS (SELECT av.codigo_lancamento_omie,
                              av.data_emissao,
                              av.data_lancamento,
                              av.data_vencimento,
                              av.bandeira,
                              av.cnpj_cpf,
                              av.razao_social,
                              av.descricao_cat,
                              av.ccoddep,
                              av.valor_conta,
                              d.descricao AS descricao_dept
                       FROM abrindo_valores av
                                LEFT JOIN departamentos_omie d ON d.codigo::text = av.ccoddep
                       WHERE av.ccoddep IS NOT NULL),
     sem_departamento AS (SELECT vcr.codigo_lancamento_omie,
                                 vcr.data_emissao,
                                 vcr.data_lancamento,
                                 vcr.data_vencimento,
                                 vcr.bandeira,
                                 vcr.cnpj_cpf,
                                 vcr.razao_social,
                                 vcr.descricao AS descricao_cat,
                                 vcr.valor_conta_corrente,
                                 NULL::text    AS ccoddep,
                                 NULL::text    AS descricao_dept
                          FROM view_contas_receber vcr
                          WHERE NOT (vcr.codigo_lancamento_omie IN (SELECT DISTINCT departamentos.codigo_lancamento_omie
                                                                    FROM departamentos))),
     agrupando AS (SELECT d.codigo_lancamento_omie,
                          d.data_emissao,
                          d.data_lancamento,
                          d.data_vencimento,
                          d.bandeira,
                          d.cnpj_cpf,
                          d.razao_social,
                          d.descricao_cat,
                          d.ccoddep,
                          d.descricao_dept,
                          d.valor_conta
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
                          sd.ccoddep,
                          sd.descricao_dept,
                          sd.valor_conta_corrente
                   FROM sem_departamento sd),
     classificando AS (SELECT a.codigo_lancamento_omie,
                              a.data_emissao,
                              a.data_lancamento,
                              a.data_vencimento,
                              a.bandeira,
                              a.cnpj_cpf,
                              a.razao_social,
                              a.descricao_cat,
                              a.ccoddep,
                              a.descricao_dept,
                              a.valor_conta,
                              CASE
                                  WHEN TRIM(BOTH FROM upper(a.descricao_cat::text)) ~~
                                       '%RECEITA DE CONTABILIDADE RECORRENTE%'::text OR
                                       (upper(a.descricao_cat::text) = ANY
                                        (ARRAY ['RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE MERCADO LIVRE DE ENERGIA'::text]))
                                      THEN 'CORPORATE'::text
                                  WHEN regexp_replace(a.cnpj_cpf, '[^0-9]'::text, ''::text, 'g'::text) = ANY
                                       (ARRAY ['12340921000182'::text, '62700834000167'::text, '44158057000199'::text, '01501108000120'::text, '23382154000190'::text, '42622192000118'::text, '56378880000199'::text, '36657397000136'::text, '39287808000137'::text, '36480461000156'::text, '27057563000172'::text, '36530240000145'::text, '39484812000195'::text, '37852789000119'::text, '42380661000130'::text, '14723195000102'::text, '34349108000106'::text, '42275720000100'::text, '08865854000142'::text, '36685910000100'::text, '47244267053'::text, '57341084000144'::text, '23448109000191'::text, '11863345000195'::text, '39349860000170'::text, '58420510000106'::text, '48552493000107'::text, '44189727000134'::text, '53192862000120'::text])
                                      THEN 'INTER COMPANY'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['TAXAS DE FRANQUIA/ALIANÇA'::text, 'ROYALTIES/CRM'::text, 'RECEITA DE ROYALTIES/CRM'::text, 'ROYALTIES VARIÁVEIS'::text, 'RECEITA DE ROYALTIES VARIÁVEIS'::text, 'ROYALTIES ANTECIPADO'::text, 'RECEITA DE ROYALTIES ANTECIPADOS'::text, 'RECEITA DE ROYALTIES'::text, 'FRANCHISING - ROYALTIES'::text, 'RECEITA DE CRM'::text, 'FRANCHISING - CRM'::text, 'RECEITA DE ROYALTIES ANTECIPADO'::text])
                                      THEN 'FRANCHISING'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DE TAXAS DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE TREINAMENTO INTERNO'::text, 'EXPANSÃO - TAXA DE LICENCIAMENTO'::text, 'RECEITA DE TAXA DE FRANQUIA/ALIANÇA'::text, 'EXPANSÃO - TAXA DE FRANQUIA'::text, 'RECEITA DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE IMPLANTAÇÃO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS PJ360'::text])
                                      THEN 'EXPANSÃO'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DE TREINAMENTO EXTERNO'::text, 'RECEITA DE TREINAMENTOS'::text])
                                      THEN 'EDUCAÇÃO'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DE SERVIÇOS JURÍDICOS'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRI'::text, 'RECEITA DE CONSULTORIA ESTRATÉGICA'::text, 'RECEITA DE RETIFICAÇÃO'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LOW)'::text, 'RECEITA DE TESES TRIBUTÁRIAS'::text, 'RECEITA DE TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE PRT'::text, 'RECEITA DE PROJETOS ESPECIAIS'::text, 'RECEITA DE TESES'::text, 'RECEITA DE PONTOS QUALIFICADOS'::text, 'RECEITA DE OPERAÇÃO DE JOBS (ÊXITO)'::text, 'CLIENTES - TRIBUTÁRIO'::text, 'CLIENTES - TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE COMPENSAÇÃO'::text, 'RECEITA DE PONTO QUALIFICADOS'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRIA'::text, 'RECEITA DE MAPA FISCAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LAW)'::text, 'RECEITA DE GESTÃO DO PASSIVO TRIBUTÁRIO'::text, 'RECEITA DE AJE - ASSESSORIA JURÍDICA EMPRESARIAL'::text, 'RECEITA DE LIQUIDAÇÃO'::text, 'RECEITA DE AJUIZAMENTO'::text, 'RECEITA DE AJUIZAMENTOS TRIBUTÁRIOS'::text, 'RECEITA DE LIQUIDAÇÃO TRIBUTÁRIO'::text, 'CLIENTES - INTERMEDIAÇÕES DE NEGÓCIOS (JOBS)'::text])
                                      THEN 'TAX'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DA SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OFFSHORE'::text, 'RECEITA DE GESTÃO DE CARTEIRA DE INVESTIMENTOS'::text, 'RECEITA DE RENEGOCIAÇÃO DE DÍVIDAS'::text, 'RECEITA DE FINANCIAMENTO DE FRANQUIA'::text, 'RECEITA DE FINANCIAMENTO DE FRANQUIA'::text, 'RECEITA DE HOLDING GOVERNANÇA'::text, 'RECEITA DE ASSESSORIA JURÍDICA MENSAL'::text, 'ASSESSORIA JURÍDICA MENSAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OPERAÇÃO DE JOBS (RECORRENTE)'::text, 'RECEITA DE OPERAÇÃO DE JOBS - SPACEW'::text, 'RECEITA DE OPERAÇÃO DE JOBS - AGRO'::text, 'RECEITA DE OPERAÇÃO DE JOBS'::text, 'RECEITA DE MERCADO LIVRE'::text, 'RECEITA DE HOLDING'::text, 'RECEITA DA SERVIÇOS JURÍDICOS'::text, 'CLIENTES - HOLDING'::text, 'RECEITA DE CESSÃO/NEGOCIAÇÃO DE PRECATÓRIOS'::text, 'RECEITA DE OPERAÇÃO DE JOB'::text, 'RECEITA DE CAPTAÇÃO DE RECURSOS'::text, 'RECEITA DE SEGUROS'::text, 'RECEITA DE MEA'::text, 'BPO FINANCEIRO'::text, 'RECEITA DE VALUATION'::text, 'RECEITA DE ASSINATURA DE ENERGIA'::text, 'RECEITA DE ENERGY GERAÇÃO - GD'::text, 'RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE SERVIÇOS CONTÁBEIS'::text, 'RECEITA DE HOLDING ITBI'::text, 'RECEITA DE SERVIÇOS JURIDICOS'::text, 'RECEITA DE AVALIAÇÃO PATRIMONIAL'::text, 'RECEITA DE ENERGY ASSESSORIA - RCE'::text, 'RECEITA DE FINANCIAMENTO - AMORTIZAÇÃO DE CRÉDITO'::text])
                                      THEN 'CORPORATE'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DE SUPORTE E CONSULTORIA EM TI'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITACARD'::text, 'CLIENTES - LOCAÇÃO DE EQUIPAMENTOS E SUPORTE TI'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS GS'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS EXTERNO'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITATAX'::text, 'RECEITA AUDITACARD'::text])
                                      THEN 'TECNOLOGIA'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['SERVIÇOS ADMINISTRATIVOS'::text, 'REPASSE'::text, 'REEMBOLSO DE DESPESAS'::text, 'RECEITA IMPRESSÕES'::text, 'RECEITA IMPORTAÇÃO FINANCEIRO GS'::text, 'RECEITA DE MARKETING'::text, 'RECEITA DE LOJA'::text, 'RECEITA A IDENTIFICAR'::text, 'PRODUTOS/LOJA'::text, 'DISTRIBUIÇÃO DE LUCROS'::text, 'DEVOLUÇÃO PAGAMENTO EFETUADO'::text, 'DEVOLUÇÃO DE SERVIÇO PRESTADO'::text, 'DEVOLUÇÃO DE PAGAMENTO FEITO'::text, 'DEVOLUÇÃO DE PAGAMENTOS FEITOS'::text, 'APLICAÇÃO PARA EMPRÉSTIMOS'::text, '<DISPONÍVEL>'::text, 'RENDIMENTO DE APLICAÇÃO FINANCEIRA'::text, 'RECEITA DE VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text, 'RECEITA DHO'::text, 'VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text])
                                      THEN 'OUTRAS RECEITAS'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DE TRANSFERÊNCIA ENTRE EMPRESAS DO GRUPO'::text, 'TRANSFERÊNCIA ENTRE CONTAS'::text])
                                      THEN 'INTER COMPANY'::text
                                  WHEN upper(a.descricao_cat::text) = ANY
                                       (ARRAY ['RECEITA DE LOCAÇÃO DE ESPAÇO E ESTACIONAMENTO'::text, 'RECEITA DE LOCAÇÃO DE ESPAÇO'::text, 'RECEITA DE ESTACIONAMENTO'::text, 'RECEITA DE COWORKING'::text])
                                      THEN 'ADMINISTRAÇÃO'::text
                                  ELSE 'SEM CATEGORIA'::text
                                  END AS categoria
                       FROM agrupando a
                       WHERE a.data_lancamento >= '2026-01-01'::date)
SELECT row_number() OVER () AS id,
       codigo_lancamento_omie,
       data_emissao,
       data_lancamento,
       data_vencimento,
       bandeira,
       cnpj_cpf,
       razao_social,
       descricao_cat,
       ccoddep,
       descricao_dept,
       valor_conta,
       categoria
FROM classificando c;

alter table view_metasmetas
    owner to postgres;

