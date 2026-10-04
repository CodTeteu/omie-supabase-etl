create view view_impostos_dre
            (codigo_lancamento_omie, valor_pis, valor_cofins, valor_csll, valor_ir, valor_iss, valor_inss) as
SELECT codigo_lancamento_omie,
       valor_pis,
       valor_cofins,
       valor_csll,
       valor_ir,
       valor_iss,
       valor_inss
FROM contas_receber_teste
WHERE data_vencimento > '2025-01-01'::date;

alter table view_impostos_dre
    owner to postgres;

