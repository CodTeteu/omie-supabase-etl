create view view_sla_checklist
            (id, job, cpf_cnpj, razao_social, primeira_entrada_area_2, ultima_saida_area_2, dias_uteis_area_2) as
WITH movimentacoes_area_2 AS (SELECT pm.codigo,
                                     j.job,
                                     COALESCE(p.cnpj, p.cpf) AS cpf_cnpj,
                                     p.razao_social,
                                     pm.entrada_data,
                                     pm.saida_data
                              FROM project_movimentos pm
                                       LEFT JOIN jobs j ON j.codigo = pm.job
                                       LEFT JOIN participantes p ON p.codigo = j.codigo_cliente
                              WHERE pm.area = 2::numeric
                                AND pm.saida_data IS NOT NULL
                                AND (pm.grupo = ANY (ARRAY [528, 551]))),
     dias_uteis_por_movimento AS (SELECT ma2.codigo,
                                         ma2.job,
                                         ma2.cpf_cnpj,
                                         ma2.razao_social,
                                         ma2.entrada_data,
                                         ma2.saida_data,
                                         count(*) AS dias_uteis_movimento
                                  FROM movimentacoes_area_2 ma2
                                           CROSS JOIN LATERAL generate_series(
                                          ma2.entrada_data::timestamp with time zone,
                                          ma2.saida_data::timestamp with time zone, '1 day'::interval) d(data_dia)
                                           LEFT JOIN feriados f
                                                     ON f.ativo = true AND f.tipo_data::text = 'FIXO'::text AND
                                                        f.mes = EXTRACT(month FROM d.data_dia)::integer AND
                                                        f.dia = EXTRACT(day FROM d.data_dia)::integer AND
                                                        (f.abrangencia::text = 'NACIONAL'::text OR
                                                         f.abrangencia::text = 'ESTADUAL'::text AND
                                                         TRIM(BOTH FROM f.uf) = 'RS'::text OR
                                                         f.abrangencia::text = 'MUNICIPAL'::text AND
                                                         TRIM(BOTH FROM f.uf) = 'RS'::text AND
                                                         f.municipio::text = 'Porto Alegre'::text)
                                  WHERE EXTRACT(isodow FROM d.data_dia) >= 1::numeric
                                    AND EXTRACT(isodow FROM d.data_dia) <= 5::numeric
                                    AND f.id IS NULL
                                  GROUP BY ma2.codigo, ma2.job, ma2.cpf_cnpj, ma2.razao_social, ma2.entrada_data,
                                           ma2.saida_data)
SELECT row_number() OVER (ORDER BY job) AS id,
       job,
       cpf_cnpj,
       razao_social,
       min(entrada_data)                AS primeira_entrada_area_2,
       max(saida_data)                  AS ultima_saida_area_2,
       sum(dias_uteis_movimento)        AS dias_uteis_area_2
FROM dias_uteis_por_movimento dpm
GROUP BY job, cpf_cnpj, razao_social
ORDER BY job;

alter table view_sla_checklist
    owner to postgres;

