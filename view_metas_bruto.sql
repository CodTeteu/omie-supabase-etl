DROP VIEW IF EXISTS public.metas_bruto;

create view public.metas_bruto as
with
  contas_receber_sb as (
    select
      cr.codigo_lancamento_omie,
      cr.empresa_nome as bandeira_nome,
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
      COALESCE(
        cat.elem ->> 'codigo_categoria'::text,
        cr.codigo_categoria
      ) as codigo_categoria_expl,
      COALESCE(
        (cat.elem ->> 'percentual'::text)::numeric,
        100::numeric
      ) as percentual_categoria,
      case 
        when cr.status_titulo ILIKE '%PARCIAL%' or (cc.valor > 0 and cc.valor < cr.valor_documento) then COALESCE(cc.valor, 0::numeric)
        else COALESCE(cr.valor_documento, 0::numeric)
      end as valor_conta,
      case 
        when cr.status_titulo ILIKE '%PARCIAL%' or (cc.valor > 0 and cc.valor < cr.valor_documento) then 'SIM'
        else 'NÃO'
      end as pagamento_parcial
    from
      contas_receber_grupo cr
      left join conta_corrente cc on cr.codigo_lancamento_omie = cc.id_origem_receber
      and cr.empresa_cnpj = cc.empresa_cnpj
      left join clientes_grupo oc on cr.codigo_cliente_fornecedor = oc.codigo_cliente_omie
      and cr.empresa_cnpj = oc.empresa_cnpj
      left join lateral (
        select
          elem.value as elem
        from
          jsonb_array_elements(
            case
              when cr.categorias is not null
              and jsonb_typeof(cr.categorias) = 'array'::text
              and jsonb_array_length(cr.categorias) > 0 then cr.categorias
              else '[{}]'::jsonb
            end
          ) elem (value)
      ) cat on true
  ),
  abrindo_valores as (
    select
      cr.codigo_lancamento_omie,
      cr.data_emissao,
      cr.data_lancamento,
      cr.data_vencimento,
      cr.empresa_cnpj,
      cr.bandeira_nome as bandeira,
      cr.cnpj_cpf,
      cr.razao_social,
      cr.numero_contrato,
      cr.codigo_categoria_expl,
      cr.percentual_categoria,
      co.descricao as descricao_cat,
      cr.valor_conta,
      cr.pagamento_parcial,
      cr.status_titulo as situacao,
      dep.elem ->> 'cCodDep'::text as ccoddep,
      (dep.elem ->> 'nPerDep'::text)::numeric as percentual_departamento
    from
      contas_receber_sb cr
      left join categorias_omie co on co.codigo::text = cr.codigo_categoria_expl
      and co.empresa_cnpj = cr.empresa_cnpj
      left join lateral (
        select
          elem.value as elem
        from
          jsonb_array_elements(
            case
              when cr.departamentos is not null
              and jsonb_typeof(cr.departamentos) = 'array'::text
              and jsonb_array_length(cr.departamentos) > 0 then cr.departamentos
              else '[{}]'::jsonb
            end
          ) elem (value)
      ) dep on true
  ),
  agrupando_valores as (
    select
      av.codigo_lancamento_omie,
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
      av.pagamento_parcial,
      av.situacao,
      max(av.valor_conta) as valor_conta,
      av.ccoddep,
      av.percentual_departamento
    from
      abrindo_valores av
    group by
      av.codigo_lancamento_omie,
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
      av.pagamento_parcial,
      av.situacao,
      av.ccoddep,
      av.percentual_departamento
  ),
  departamentos as (
    select
      av.codigo_lancamento_omie,
      av.data_emissao,
      av.data_lancamento,
      av.data_vencimento,
      av.bandeira,
      av.cnpj_cpf,
      av.razao_social,
      av.numero_contrato,
      av.descricao_cat,
      av.percentual_categoria,
      av.pagamento_parcial,
      av.situacao,
      av.ccoddep,
      av.percentual_departamento,
      d.descricao as descricao_dept,
      av.valor_conta * (av.percentual_departamento / 100::numeric) * (av.percentual_categoria / 100::numeric) as valor_cat_dept
    from
      agrupando_valores av
      left join departamentos_omie d on d.codigo::text = av.ccoddep
      and d.empresa_cnpj = av.empresa_cnpj
    where
      av.ccoddep is not null
  ),
  sem_departamento as (
    select
      av.codigo_lancamento_omie,
      av.data_emissao,
      av.data_lancamento,
      av.data_vencimento,
      av.bandeira,
      av.cnpj_cpf,
      av.razao_social,
      av.numero_contrato,
      av.descricao_cat,
      av.percentual_categoria,
      av.pagamento_parcial,
      av.situacao,
      null::text as ccoddep,
      null::numeric as percentual_departamento,
      null::text as descricao_dept,
      av.valor_conta * (av.percentual_categoria / 100::numeric) as valor_conta
    from
      abrindo_valores av
    where
      not (
        av.codigo_lancamento_omie in (
          select distinct
            departamentos.codigo_lancamento_omie
          from
            departamentos
        )
      )
  ),
  agrupando as (
    select
      d.codigo_lancamento_omie,
      d.data_emissao,
      d.data_lancamento,
      d.data_vencimento,
      d.bandeira,
      d.cnpj_cpf,
      d.razao_social,
      d.numero_contrato,
      d.descricao_cat,
      d.percentual_categoria,
      d.pagamento_parcial,
      d.situacao,
      d.ccoddep,
      d.percentual_departamento,
      d.descricao_dept,
      d.valor_cat_dept
    from
      departamentos d
    union all
    select
      sd.codigo_lancamento_omie,
      sd.data_emissao,
      sd.data_lancamento,
      sd.data_vencimento,
      sd.bandeira,
      sd.cnpj_cpf,
      sd.razao_social,
      sd.numero_contrato,
      sd.descricao_cat,
      sd.percentual_categoria,
      sd.pagamento_parcial,
      sd.situacao,
      sd.ccoddep,
      sd.percentual_departamento,
      sd.descricao_dept,
      sd.valor_conta
    from
      sem_departamento sd
  ),
  classificando as (
    select
      a.codigo_lancamento_omie,
      a.data_emissao,
      a.data_lancamento,
      a.data_vencimento,
      a.bandeira,
      a.cnpj_cpf,
      a.razao_social,
      a.numero_contrato,
      a.descricao_cat,
      a.percentual_categoria,
      a.pagamento_parcial,
      a.situacao,
      a.ccoddep,
      a.percentual_departamento,
      a.descricao_dept,
      a.valor_cat_dept,
      case
        when TRIM(both from upper(a.descricao_cat::text)) ~~ '%RECEITA DE CONTABILIDADE RECORRENTE%'::text
        or (upper(a.descricao_cat::text) = any (array['RECEITA DE GESTÃO DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE MERCADO LIVRE DE ENERGIA'::text, 'RECEITA DE HOLDING'::text, 'RECEITA DE SERVIÇOS CONTÁBEIS'::text])) then 'CORPORATE'::text
        when regexp_replace(a.cnpj_cpf, '\D'::text, ''::text, 'g'::text) = any (
          array[
            '12340921000182'::text, '62700834000167'::text, '44158057000199'::text, '01501108000120'::text, '23382154000190'::text, '42622192000118'::text, '56378880000199'::text,
            '36657397000136'::text, '39287808000137'::text, '36480461000156'::text, '27057563000172'::text, '36530240000145'::text, '39484812000195'::text, '37852789000119'::text,
            '42380661000130'::text, '14723195000102'::text, '34349108000106'::text, '42275720000100'::text, '08865854000142'::text, '36685910000100'::text, '47244267053'::text,
            '57341084000144'::text, '23448109000191'::text, '11863345000195'::text, '39349860000170'::text, '58420510000106'::text, '48552493000107'::text, '44189727000134'::text,
            '53192862000120'::text
          ]
        ) then 'INTER COMPANY'::text
        when upper(a.descricao_cat::text) = any (
          array[
            'TAXAS DE FRANQUIA/ALIANÇA'::text, 'ROYALTIES/CRM'::text, 'RECEITA DE ROYALTIES/CRM'::text, 'ROYALTIES VARIÁVEIS'::text, 'RECEITA DE ROYALTIES VARIÁVEIS'::text,
            'ROYALTIES ANTECIPADO'::text, 'RECEITA DE ROYALTIES ANTECIPADOS'::text, 'RECEITA DE ROYALTIES'::text, 'FRANCHISING - ROYALTIES'::text, 'RECEITA DE CRM'::text,
            'FRANCHISING - CRM'::text
          ]
        ) then 'FRANCHISING'::text
        when upper(a.descricao_cat::text) = any (
          array[
            'RECEITA DE TAXAS DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE ROYALTIES ANTECIPADO'::text, 'RECEITA DE TREINAMENTO INTERNO'::text, 'EXPANSÃO - TAXA DE LICENCIAMENTO'::text,
            'RECEITA DE TAXA DE FRANQUIA/ALIANÇA'::text, 'EXPANSÃO - TAXA DE FRANQUIA'::text, 'RECEITA DE FRANQUIA/ALIANÇA'::text, 'RECEITA DE IMPLANTAÇÃO'::text,
            'LICENÇAS DE SOFTWARES E PROGRAMAS PJ360'::text, 'RECEITA DE LICENÇAS DE SOFWARES - PJ360'::text, 'RECEITA DE LICENÇAS DE SOFTWARES - PJ360'::text, 'RECEITA DE PRODUTOS/LOJA'::text
          ]
        ) then 'EXPANSÃO'::text
        when upper(a.descricao_cat::text) = any (
          array['RECEITA DE TREINAMENTO EXTERNO'::text, 'RECEITA DE TREINAMENTOS'::text]
        ) then 'EDUCAÇÃO'::text
        when upper(a.descricao_cat::text) = any (
          array[
            'RECEITA DE SERVIÇOS JURÍDICOS'::text, 'RECEITA DE RESTITUIÇÃO'::text, 'RECEITA DE REVISÃO PREVIDENCIÁRI'::text, 'RECEITA DE RETIFICAÇÃO'::text,
            'RECEITA DE SERVIÇOS JURÍDICOS (LOW)'::text, 'RECEITA DE TESES TRIBUTÁRIAS'::text, 'RECEITA DE TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE PRT'::text,
            'RECEITA DE PROJETOS ESPECIAIS'::text, 'RECEITA DE TESES'::text, 'RECEITA DE PONTOS QUALIFICADOS'::text, 'RECEITA DE OPERAÇÃO DE JOBS (ÊXITO)'::text,
            'CLIENTES - TRIBUTÁRIO'::text, 'CLIENTES - TRANSAÇÃO TRIBUTÁRIA'::text, 'RECEITA DE COMPENSAÇÃO'::text, 'RECEITA DE PONTO QUALIFICADOS'::text,
            'RECEITA DE REVISÃO PREVIDENCIÁRIA'::text, 'RECEITA DE MAPA FISCAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (LAW)'::text, 'RECEITA DE GESTÃO DO PASSIVO TRIBUTÁRIO'::text,
            'RECEITA DE AJE - ASSESSORIA JURÍDICA EMPRESARIAL'::text, 'RECEITA DE LIQUIDAÇÃO'::text, 'RECEITA DE AJUIZAMENTO'::text, 'RECEITA DE AJUIZAMENTOS TRIBUTÁRIOS'::text,
            'RECEITA DE LEI DO BEM'::text, 'RECEITA DE LIQUIDAÇÃO TRIBUTÁRIO'::text, 'CLIENTES - INTERMEDIAÇÕES DE NEGÓCIOS (JOBS)'::text, 'RECEITA DE SUBVENÇÃO FINEP'::text,
            'RECEITA DE SUPPLY TAX'::text, 'RECEITA DE RENEGOCIAÇÃO DE DÍVIDAS'::text, 'RECUPERAÇÃO DE DEPÓSITOS JUDICIAIS'::text
          ]
        ) then 'TAX'::text
        when upper(a.descricao_cat::text) = any (
          array[
            'RECEITA DA SERVIÇOS JURÍDICOS (FAMILY)'::text, 'RECEITA DE OFFSHORE'::text, 'RECEITA DE CONSULTORIA ESTRATÉGICA'::text, 'RECEITA DE AJUIZAMENTOS CÍVEIS'::text,
            'RECEITA DE GESTÃO DE CARTEIRA DE INVESTIMENTOS'::text, 'RECEITA DE FINANCIAMENTO DE FRANQUIA'::text, 'RECEITA DE HOLDING GOVERNANÇA'::text,
            'RECEITA DE ASSESSORIA JURÍDICA MENSAL'::text, 'ASSESSORIA JURÍDICA MENSAL'::text, 'RECEITA DE SERVIÇOS JURÍDICOS (FAMILY)'::text,
            'RECEITA DE OPERAÇÃO DE JOBS (RECORRENTE)'::text, 'RECEITA DE OPERAÇÃO DE JOBS - SPACEW'::text, 'RECEITA DE OPERAÇÃO DE JOBS - AGRO'::text,
            'RECEITA DE OPERAÇÃO DE JOBS'::text, 'RECEITA DE MERCADO LIVRE'::text, 'RECEITA DA SERVIÇOS JURÍDICOS'::text, 'CLIENTES - HOLDING'::text,
            'RECEITA DE CESSÃO/NEGOCIAÇÃO DE PRECATÓRIOS'::text, 'RECEITA DE OPERAÇÃO DE JOB'::text, 'RECEITA DE CAPTAÇÃO DE RECURSOS'::text,
            'RECEITA DE SEGUROS'::text, 'RECEITA DE MEA'::text, 'BPO FINANCEIRO'::text, 'RECEITA DE VALUATION'::text, 'RECEITA DE ASSINATURA DE ENERGIA'::text,
            'RECEITA DE ENERGY GERAÇÃO - GD'::text, 'RECEITA DE HOLDING ITBI'::text, 'RECEITA DE SERVIÇOS JURIDICOS'::text, 'RECEITA DE AVALIAÇÃO PATRIMONIAL'::text,
            'RECEITA DE ENERGY ASSESSORIA - RCE'::text, 'RECEITA DE FINANCIAMENTO - AMORTIZAÇÃO DE CRÉDITO'::text, 'RECEITA DE FINANCIAMENTO - RENDIMENTO DE FINANCIAMENTO'::text,
            'RECEITA DE RECUPERA ENERGIA'::text, 'RECEITA DE ANTEPICAÇÃO DE RECEBÍVEIS'::text, 'RECEITA DE ANTECIPAÇÃO DE RECEBÍVEIS'::text
          ]
        ) then 'CORPORATE'::text
        when upper(a.descricao_cat::text) = any (
          array[
            'RECEITA DE SUPORTE E CONSULTORIA EM TI'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS'::text, 'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITACARD'::text,
            'CLIENTES - LOCAÇÃO DE EQUIPAMENTOS E SUPORTE TI'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS GS'::text, 'CLIENTES - LICENÇAS DE SOFTWARES E PROGRAMAS EXTERNO'::text,
            'LICENÇAS DE SOFTWARES E PROGRAMAS AUDITATAX'::text, 'RECEITA AUDITACARD'::text
          ]
        ) then 'TECNOLOGIA'::text
        when upper(a.descricao_cat::text) = any (
          array[
            'SERVIÇOS ADMINISTRATIVOS'::text, 'REPASSE'::text, 'REEMBOLSO DE DESPESAS'::text, 'RECEITA IMPRESSÕES'::text, 'RECEITA IMPORTAÇÃO FINANCEIRO GS'::text,
            'RECEITA DE MARKETING'::text, 'RECEITA DE LOJA'::text, 'RECEITA A IDENTIFICAR'::text, 'PRODUTOS/LOJA'::text, 'DISTRIBUIÇÃO DE LUCROS'::text,
            'DEVOLUÇÃO PAGAMENTO EFETUADO'::text, 'DEVOLUÇÃO DE SERVIÇO PRESTADO'::text, 'DEVOLUÇÃO DE PAGAMENTO FEITO'::text, 'DEVOLUÇÃO DE PAGAMENTOS FEITOS'::text,
            'APLICAÇÃO PARA EMPRÉSTIMOS'::text, '<DISPONÍVEL>'::text, 'RENDIMENTO DE APLICAÇÃO FINANCEIRA'::text, 'RECEITA DE VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text,
            'RECEITA DHO'::text, 'VALORES A TRANSFERIR/RECEBIMENTO INDEVIDO'::text, 'RECEITA SOCIAL MÍDIA DE ALTA PERFORMANCE'::text, 'RESGATE DE APLICAÇÃO FINANCEIRA'::text,
            'RESGATE DE APLICAÇÕES FINANCEIRAS'::text, 'RECEITA DIVERSA'::text, 'RECEITA DE SERVIÇO DE IMPRESSÃO'::text, 'DEVOLUÇÃO DE CAPITAL DE GIRO'::text,
            'DESCONTOS OBTIDOS'::text, 'RECEITA DE SERVIÇOS DE IMPRESSÃO'::text, 'RESTITUIÇÃO E RECUPERAÇÃO DE TRIBUTOS'::text, 'TAXAS BANCÁRIAS'::text
          ]
        ) then 'OUTRAS RECEITAS'::text
        when upper(a.descricao_cat::text) = any (
          array[
            'RECEITA DE TRANSFERÊNCIA ENTRE EMPRESAS DO GRUPO'::text, 'APORTE DE CAPITAL'::text, 'RECEITA DE EMPRÉSTIMOS ENTRE EMPRESAS'::text,
            'TRANSFERÊNCIA ENTRE CONTAS'::text, 'CAPITAL DE GIRO'::text, 'ADIANTAMENTO RECEBIDO REPASSES FUTUROS'::text, 'RECEITA INTERCOMPANY'::text,
            'RECEITA DE FUNDO DE MARKETING/ADMINISTRATIVO'::text, 'ENTRADA DE TRANSFERÊNCIAS'::text, 'ANTECIPAÇÃO DE LUCROS'::text
          ]
        ) then 'INTER COMPANY'::text
        when upper(a.descricao_cat::text) = any (
          array[
            'RECEITA DE LOCAÇÃO DE ESPAÇO E ESTACIONAMENTO'::text, 'RECEITA DE LOCAÇÃO DE ESPAÇO'::text, 'RECEITA DE ESTACIONAMENTO'::text, 'RECEITA DE COWORKING'::text,
            'RECEITA DE CESSÃO DE USO DE IMÓVEL'::text
          ]
        ) then 'ADMINISTRAÇÃO'::text
        else 'SEM CATEGORIA'::text
      end as categoria
    from
      agrupando a
    where
      a.data_lancamento >= '2026-01-01'::date
  )
select
  row_number() over () as id,
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
  round(valor_cat_dept, 2) as valor_bruto,
  categoria,
  pagamento_parcial,
  situacao
from
  classificando c;
