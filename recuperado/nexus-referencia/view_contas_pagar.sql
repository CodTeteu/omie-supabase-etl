create view view_contas_pagar
            (codigo_lancamento_omie, codigo_lancamento_integracao, codigo_cliente_omie, cnpj_cpf, razao_social,
             nome_fantasia, tags, data_emissao, numero_documento, status_titulo, numero_parcela, valor_documento,
             data_vencimento, codigo, descricao, bandeira)
as
SELECT r.codigo_lancamento_omie,
       r.codigo_lancamento_integracao,
       p.codigo_cliente_omie,
       replace(replace(replace(p.cnpj_cpf::text, '/'::text, ''::text), '.'::text, ''::text), '-'::text,
               ''::text) AS cnpj_cpf,
       p.razao_social,
       p.nome_fantasia,
       p.tags,
       r.data_emissao,
       r.numero_documento,
       r.status_titulo,
       r.numero_parcela,
       r.valor_documento,
       r.data_vencimento,
       c.codigo,
       c.descricao,
       b.nome            AS bandeira
FROM omie_clientes p
         JOIN contas_pagar r ON p.codigo_cliente_omie = r.codigo_cliente_fornecedor AND p.bandeira_id = r.bandeira_id
         JOIN bandeiras_omie b ON b.codigo = r.bandeira_id
         JOIN categorias_omie c ON c.codigo::text = r.codigo_categoria::text AND c.bandeiras = r.bandeira_id;

alter table view_contas_pagar
    owner to postgres;

