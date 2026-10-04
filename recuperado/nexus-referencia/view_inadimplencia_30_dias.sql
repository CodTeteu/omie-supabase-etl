create view view_inadimplencia_30_dias
            (id, bandeira, data_vencimento, cnpj_cpf, razao_social, data_previsao, valor_documento) as
SELECT id,
       nome AS bandeira,
       data_vencimento,
       cnpj_cpf,
       razao_social,
       data_previsao,
       valor_documento
FROM view_inadimplencia
WHERE inadimplencia > 1::numeric
  AND data_vencimento >= (CURRENT_DATE - 30)
  AND data_vencimento <= CURRENT_DATE
ORDER BY nome, data_vencimento, razao_social;

alter table view_inadimplencia_30_dias
    owner to postgres;

