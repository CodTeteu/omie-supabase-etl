create view view_inadimplencia_bkp
            (id, codigo_lancamento_omie, bandeira, nome, codigo_categoria, descricao_categoria, numero_documento,
             cnpj_cpf, razao_social, data_vencimento, data_emissao, data_previsao, valor_documento, valor_pago,
             valor_imposto, valor_desconto, inadimplencia, departamentos)
as
WITH agrupando AS (SELECT cr.codigo_lancamento_omie,
                          cr.bandeira,
                          bo.nome,
                          cr.codigo_categoria,
                          cr.numero_documento,
                          oc.cnpj_cpf,
                          oc.razao_social,
                          cr.data_vencimento,
                          cr.data_emissao,
                          cr.data_previsao,
                          cr.valor_documento,
                          sum(cc.valor)                                           AS valor_pago,
                          COALESCE(cr.distribuicao::text, cc.departamentos::text) AS departamentos
                   FROM contas_receber cr
                            LEFT JOIN omie_clientes oc ON oc.codigo_cliente_omie = cr.codigo_cliente_fornecedor
                            LEFT JOIN conta_corrente cc ON cc.id_origem_receber = cr.codigo_lancamento_omie
                            LEFT JOIN bandeiras_omie bo ON bo.codigo = cr.bandeira
                   WHERE cr.data_vencimento >= '2010-01-01'::date
                     AND cr.data_vencimento <= '2035-01-01'::date
                     AND NOT (oc.cnpj_cpf::text IN (SELECT DISTINCT bandeiras_omie.cnpj
                                                    FROM bandeiras_omie
                                                    WHERE bandeiras_omie.cnpj IS NOT NULL))
                     AND cr.status_titulo::text IS DISTINCT FROM 'CANCELADO'::text
                     AND cr.situacao::text IS DISTINCT FROM 'Cancelado'::text
                   GROUP BY cr.codigo_lancamento_omie, cr.bandeira, bo.nome, cr.codigo_categoria, cr.numero_documento,
                            oc.cnpj_cpf, oc.razao_social, cr.data_vencimento, cr.data_emissao, cr.data_previsao,
                            cr.valor_documento, (COALESCE(cr.distribuicao::text, cc.departamentos::text))),
     consulta AS (SELECT a.codigo_lancamento_omie,
                         a.bandeira,
                         a.nome,
                         a.codigo_categoria,
                         a.numero_documento,
                         a.cnpj_cpf,
                         a.razao_social,
                         a.data_vencimento,
                         a.data_emissao,
                         a.data_previsao,
                         a.valor_documento,
                         COALESCE(a.valor_pago, 0::numeric)                                       AS valor_pago,
                         COALESCE(cr.valor_pis, 0::numeric) + COALESCE(cr.valor_cofins, 0::numeric) +
                         COALESCE(cr.valor_csll, 0::numeric) + COALESCE(cr.valor_ir, 0::numeric) +
                         COALESCE(cr.valor_iss, 0::numeric) + COALESCE(cr.valor_inss, 0::numeric) AS valor_imposto,
                         a.departamentos
                  FROM agrupando a
                           LEFT JOIN contas_receber cr ON cr.codigo_lancamento_omie = a.codigo_lancamento_omie),
     inadimplencia AS (SELECT c.codigo_lancamento_omie,
                              c.bandeira,
                              c.nome,
                              c.codigo_categoria,
                              co.descricao                                      AS descricao_categoria,
                              c.numero_documento,
                              c.cnpj_cpf,
                              c.razao_social,
                              c.data_vencimento,
                              c.data_emissao,
                              c.data_previsao,
                              c.valor_documento,
                              c.valor_pago,
                              c.valor_imposto,
                              COALESCE(mf.valor_desconto, 0::numeric)           AS valor_desconto,
                              round(c.valor_documento - c.valor_imposto - c.valor_pago -
                                    COALESCE(mf.valor_desconto, 0::numeric), 2) AS inadimplencia,
                              c.departamentos
                       FROM consulta c
                                LEFT JOIN movimentos_financeiros mf ON mf.id_movimento = c.codigo_lancamento_omie
                                LEFT JOIN categorias_omie co
                                          ON co.codigo::text = c.codigo_categoria::text AND co.bandeiras = c.bandeira)
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
       valor_imposto,
       valor_desconto,
       inadimplencia,
       departamentos
FROM inadimplencia
WHERE data_vencimento < CURRENT_DATE;

alter table view_inadimplencia_bkp
    owner to postgres;

