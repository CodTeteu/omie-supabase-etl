create view view_jobs_prev_checklist(id, job, coalesce, razao_social, dias) as
SELECT row_number() OVER ()                AS id,
       j.job,
       COALESCE(p.cnpj, p.cpf)             AS "coalesce",
       p.razao_social,
       CURRENT_DATE - min(pm.entrada_data) AS dias
FROM project_movimentos pm
         LEFT JOIN jobs j ON j.codigo = pm.job
         LEFT JOIN participantes p ON p.codigo = j.codigo_cliente
WHERE pm.area = 2::numeric
  AND pm.saida_data IS NULL
  AND (pm.grupo = ANY (ARRAY [528, 551]))
GROUP BY j.job, (COALESCE(p.cnpj, p.cpf)), p.razao_social;

alter table view_jobs_prev_checklist
    owner to postgres;

