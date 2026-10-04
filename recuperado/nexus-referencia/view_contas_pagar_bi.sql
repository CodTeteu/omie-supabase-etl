create view view_contas_pagar_bi
            (id, ccoddep, descricao_dept, data_vencimento, data_lancamento, razao_social, cnpj_cpf, codigo,
             descricao_cat, valor) as
WITH explodindo_valores AS (SELECT dep_1.elem ->> 'cCodDep'::text            AS ccoddep,
                                   (dep_1.elem ->> 'nValDep'::text)::numeric AS valor_departamento,
                                   cp.data_vencimento,
                                   cc.data_lancamento,
                                   oc.razao_social,
                                   oc.cnpj_cpf,
                                   co.codigo,
                                   co.descricao
                            FROM contas_pagar cp
                                     LEFT JOIN conta_corrente cc ON cc.id_origem_pagar = cp.codigo_lancamento_omie
                                     LEFT JOIN omie_clientes oc ON oc.codigo_cliente_omie = cp.codigo_cliente_fornecedor
                                     LEFT JOIN categorias_omie co ON co.codigo::text = cp.codigo_categoria::text AND
                                                                     co.bandeiras = cp.bandeira_id
                                     LEFT JOIN LATERAL ( SELECT elem.value AS elem
                                                         FROM jsonb_array_elements((cp.distribuicao #>> '{}'::text[])::jsonb) elem(value)) dep_1
                                               ON true)
SELECT row_number() OVER ()  AS id,
       ev.ccoddep,
       dep.descricao         AS descricao_dept,
       ev.data_vencimento,
       ev.data_lancamento,
       ev.razao_social,
       ev.cnpj_cpf,
       ev.codigo,
       ev.descricao          AS descricao_cat,
       ev.valor_departamento AS valor
FROM explodindo_valores ev
         LEFT JOIN departamentos_omie dep ON ev.ccoddep = dep.codigo::text
WHERE ev.data_lancamento >= '2026-01-01'::date;

alter table view_contas_pagar_bi
    owner to postgres;

