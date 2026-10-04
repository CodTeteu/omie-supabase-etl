create view view_honorarios_jobs
            (codigo, job, data_cadastro, nome, uf, produto, modelo, valor_inicial, credito_percentual, credito_valor,
             credito_honorario, passivo_percentual, passivo_valor, passivo_honorario, honorarios,
             honorarios_pago_project, honorarios_pago_financeiro, honarios_aberto_financeiro, falta_faturar)
as
WITH movimentos_agrupados AS (SELECT pmv.job,
                                     sum(
                                             CASE
                                                 WHEN pg.passivo = 1 THEN COALESCE(pmv.valor, 0::numeric)
                                                 ELSE 0::numeric
                                                 END) AS credito_valor,
                                     sum(
                                             CASE
                                                 WHEN pg.passivo = 0 THEN COALESCE(pmv.valor, 0::numeric)
                                                 ELSE 0::numeric
                                                 END) AS passivo_valor
                              FROM project_movimentos pmv
                                       JOIN project_grupos pg ON pg.codigo = pmv.grupo
                              WHERE pmv.saida_data IS NULL
                              GROUP BY pmv.job),
     base AS (SELECT j.codigo,
                     j.job,
                     j.data_cadastro::date                                            AS data_cadastro,
                     p.razao_social                                                   AS nome,
                     p.uf,
                     s.nome                                                           AS produto,
                     mdl.nome                                                         AS modelo,
                     COALESCE(j.rf_valor, 0::numeric)                                 AS valor_inicial,
                     COALESCE(j.percentual, 0::numeric)                               AS credito_percentual,
                     COALESCE(j.percentual_passivo, j.passivo_percentual, 0::numeric) AS passivo_percentual,
                     COALESCE(ma.credito_valor, 0::numeric)                           AS credito_valor,
                     COALESCE(ma.passivo_valor, 0::numeric)                           AS passivo_valor
              FROM jobs j
                       LEFT JOIN participantes p ON p.codigo = j.codigo_cliente
                       LEFT JOIN servicos s ON s.codigo = j.codigo_produto
                       LEFT JOIN project_modelo mdl ON mdl.codigo = s.modelo
                       LEFT JOIN movimentos_agrupados ma ON ma.job = j.codigo),
     calculado AS (SELECT base.codigo,
                          base.job,
                          base.data_cadastro,
                          base.nome,
                          base.uf,
                          base.produto,
                          base.modelo,
                          base.valor_inicial,
                          base.credito_percentual,
                          base.credito_valor,
                          CASE
                              WHEN base.credito_valor > 0::numeric
                                  THEN (base.credito_valor * base.credito_percentual / 100::numeric)::numeric(12, 2)
                              ELSE 0::numeric(12, 2)
                              END AS credito_honorario,
                          base.passivo_percentual,
                          base.passivo_valor,
                          CASE
                              WHEN base.passivo_valor > 0::numeric
                                  THEN (base.passivo_valor * base.passivo_percentual / 100::numeric)::numeric(12, 2)
                              ELSE 0::numeric(12, 2)
                              END AS passivo_honorario
                   FROM base)
SELECT codigo,
       job,
       data_cadastro,
       nome,
       uf,
       produto,
       modelo,
       valor_inicial,
       credito_percentual,
       credito_valor,
       credito_honorario,
       passivo_percentual,
       passivo_valor,
       passivo_honorario,
       (credito_honorario + passivo_honorario)::numeric(12, 2) AS honorarios,
       0                                                       AS honorarios_pago_project,
       0                                                       AS honorarios_pago_financeiro,
       0                                                       AS honarios_aberto_financeiro,
       0                                                       AS falta_faturar
FROM calculado;

alter table view_honorarios_jobs
    owner to postgres;

