create view view_contas_receber
            (id, codigo_lancamento_omie, codigo_lancamento_integracao, codigo_cliente_omie, cnpj_cpf, razao_social,
             nome_fantasia, tags, data_emissao, data_conciliacao, data_inclusao, data_lancamento, numero_documento,
             boleto, status_titulo, numero_parcela, valor_contas_receber, valor_conta_corrente, data_vencimento,
             data_previsao, codigo, descricao, bandeira, codigo_bandeira, codigo_lancamento_conta_corrente, situacao,
             distribuicao, departamentos)
as
SELECT row_number() OVER (ORDER BY r.data_emissao DESC, r.codigo_lancamento_omie, m.codigo_lancamento)            AS id,
       r.codigo_lancamento_omie,
       r.codigo_lancamento_integracao,
       p.codigo_cliente_omie,
       replace(replace(replace(p.cnpj_cpf::text, '/'::text, ''::text), '.'::text, ''::text), '-'::text,
               ''::text)                                                                                          AS cnpj_cpf,
       p.razao_social,
       p.nome_fantasia,
       p.tags,
       r.data_emissao,
       m.data_conciliacao,
       m.data_inclusao,
       m.data_lancamento,
       r.numero_documento,
       json_build_object('cGerado', r.boleto_gerado, 'cNumBoleto', r.boleto_numero, 'dDtEmBol', r.boleto_data_emissao,
                         'nPerJuros', r.boleto_juros, 'nPerMulta', r.boleto_multa, 'cCodBarra',
                         r.codigo_barras_ficha_compensacao)                                                       AS boleto,
       r.status_titulo,
       r.numero_parcela,
       r.valor_documento                                                                                          AS valor_contas_receber,
       m.valor                                                                                                    AS valor_conta_corrente,
       r.data_vencimento,
       r.data_previsao,
       c.codigo,
       c.descricao,
       b.nome                                                                                                     AS bandeira,
       b.codigo                                                                                                   AS codigo_bandeira,
       m.codigo_lancamento                                                                                        AS codigo_lancamento_conta_corrente,
       r.situacao,
       r.distribuicao,
       m.departamentos
FROM omie_clientes p
         JOIN contas_receber r ON p.codigo_cliente_omie = r.codigo_cliente_fornecedor AND p.bandeira_id = r.bandeira
         JOIN bandeiras_omie b ON b.codigo = r.bandeira
         JOIN categorias_omie c ON c.codigo::text = r.codigo_categoria::text AND c.bandeiras = r.bandeira
         LEFT JOIN conta_corrente m ON r.codigo_lancamento_omie = m.id_origem_receber;

alter table view_contas_receber
    owner to postgres;

