create view view_conciliacao_omie_project
            (id, codigo, razao_social, cnpj_cpf, tipo, descricao, data_vencimento, mes, ano, valor_project,
             valor_contas_receber, valor_conta_corrente, status_titulo, bandeira, data, crm, valor, royalties,
             data_inativacao, tipo_venda, ativo, tipo_franquia)
as
SELECT DISTINCT row_number() OVER () AS id,
                u.codigo,
                p.razao_social,
                c.cnpj_cpf,
                v.tipo,
                r.descricao,
                r.data_vencimento,
                v.mes,
                v.ano,
                v.valor              AS valor_project,
                r.valor_contas_receber,
                r.valor_conta_corrente,
                r.status_titulo,
                r.bandeira,
                m.data,
                m.crm,
                m.valor,
                m.royalties,
                m.data_inativacao,
                m.tipo_venda,
                m.ativo,
                m.tipo_franquia
FROM unidades u
         JOIN modelos m ON u.codigo = m.unidade
         JOIN vinculo_participante_unidade vpu ON vpu.unidade = u.codigo
         JOIN participantes p ON p.codigo = vpu.participante
         JOIN valores_unidades v ON v.unidade = u.codigo
         JOIN omie_clientes c ON p.cnpj::text =
                                 replace(replace(replace(c.cnpj_cpf::text, '.'::text, ''::text), '/'::text, ''::text),
                                         '-'::text, ''::text) OR p.cpf::text = replace(
        replace(replace(c.cnpj_cpf::text, '.'::text, ''::text), '/'::text, ''::text), '-'::text, ''::text)
         JOIN view_contas_receber r ON r.codigo_cliente_omie = c.codigo_cliente_omie AND
                                       v.ano::numeric = EXTRACT(year FROM r.data_vencimento) AND
                                       v.mes::numeric = EXTRACT(month FROM r.data_vencimento)
         JOIN categorias_omie cat ON cat.codigo::text = r.codigo::text AND cat.bandeiras = r.codigo_bandeira AND
                                     v.tipo = cat.codigo_valores_unidades;

alter table view_conciliacao_omie_project
    owner to postgres;

