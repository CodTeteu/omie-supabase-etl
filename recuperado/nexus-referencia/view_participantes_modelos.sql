create view view_participantes_modelos
            (codigo, cpf, cnpj, cpf_cnpj, unidade, modelo, royalties, crm, ativo, valor, tipo) as
SELECT p.codigo,
       p.cpf,
       p.cnpj,
       COALESCE(NULLIF(p.cnpj::text, ''::text), NULLIF(p.cpf::text, ''::text)) AS cpf_cnpj,
       m.unidade,
       m.modelo,
       m.royalties,
       m.crm,
       m.ativo,
       vu.valor,
       vu.tipo
FROM vinculo_participante_unidade vpu
         JOIN participantes p ON vpu.participante = p.codigo
         JOIN modelos m ON vpu.unidade = m.unidade
         LEFT JOIN unidades u ON vpu.unidade = u.codigo
         LEFT JOIN valores_unidades vu ON u.codigo = vu.unidade;

alter table view_participantes_modelos
    owner to postgres;

