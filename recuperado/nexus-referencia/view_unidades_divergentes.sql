create view view_unidades_divergentes
            (codigo, nome, modelo, valor, data, data_inativacao, tipo_venda, tipo, valor_unidade, cpf_cnpj) as
WITH clientes_limpos AS (SELECT omie_clientes.codigo_cliente_omie,
                                regexp_replace(omie_clientes.cnpj_cpf::text, '[^0-9]'::text, ''::text,
                                               'g'::text) AS documento_limpo
                         FROM omie_clientes)
SELECT u.codigo,
       u.nome,
       m.modelo,
       m.valor,
       m.data,
       m.data_inativacao,
       m.tipo_venda,
       vu.tipo,
       vu.valor                                              AS valor_unidade,
       COALESCE(NULLIF(p.cnpj::text, ''::text), p.cpf::text) AS cpf_cnpj
FROM unidades u
         JOIN modelos m ON u.codigo = m.unidade
         LEFT JOIN vinculo_participante_unidade vpu ON vpu.unidade = u.codigo AND vpu.modelo = m.modelo
         LEFT JOIN participantes p ON p.codigo = vpu.participante
         LEFT JOIN valores_unidades vu ON vu.unidade = u.codigo
WHERE m.ativo = 0
  AND NOT (EXISTS (SELECT 1
                   FROM vinculo_participante_unidade vpu_1
                            JOIN participantes p_1 ON p_1.codigo = vpu_1.participante
                            JOIN valores_unidades v ON v.unidade = vpu_1.unidade
                            JOIN clientes_limpos c
                                 ON p_1.cnpj::text = c.documento_limpo OR p_1.cpf::text = c.documento_limpo
                            JOIN view_contas_receber r ON r.codigo_cliente_omie = c.codigo_cliente_omie
                            JOIN categorias_omie cat
                                 ON cat.codigo::text = r.codigo::text AND cat.bandeiras = r.codigo_bandeira AND
                                    v.tipo = cat.codigo_valores_unidades
                   WHERE vpu_1.unidade = u.codigo
                     AND vpu_1.modelo = m.modelo
                     AND v.ano::numeric = EXTRACT(year FROM r.data_vencimento)
                     AND v.mes::numeric = EXTRACT(month FROM r.data_vencimento)));

alter table view_unidades_divergentes
    owner to postgres;

