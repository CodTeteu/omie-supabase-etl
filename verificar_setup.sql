-- Verificacao do setup: roda no SQL Editor do projeto novo.
-- Esperado: 20 linhas, todas com status OK.
WITH esperado(tipo, nome) AS (
  VALUES
    ('tabela','categorias_omie'), ('tabela','clientes_grupo'), ('tabela','conta_corrente'),
    ('tabela','contas_pagar'), ('tabela','contas_receber_grupo'), ('tabela','departamentos_omie'),
    ('tabela','extrato_bancario'), ('tabela','movimentos_financeiros'),
    ('view','metas'), ('view','metas_bruto'), ('view','painel_contas_pagar'),
    ('pk','categorias_omie'), ('pk','clientes_grupo'), ('pk','conta_corrente'),
    ('pk','contas_pagar'), ('pk','contas_receber_grupo'), ('pk','departamentos_omie'),
    ('pk','extrato_bancario'), ('pk','movimentos_financeiros'),
    ('extensao','uuid-ossp')
)
SELECT e.tipo, e.nome,
       CASE WHEN (
         (e.tipo = 'tabela'   AND to_regclass('public.'||e.nome) IS NOT NULL)
      OR (e.tipo = 'view'     AND to_regclass('public.'||e.nome) IS NOT NULL)
      OR (e.tipo = 'pk'       AND EXISTS (SELECT 1 FROM pg_constraint
                                          WHERE conrelid = to_regclass('public.'||e.nome)
                                            AND contype = 'p'))
      OR (e.tipo = 'extensao' AND EXISTS (SELECT 1 FROM pg_extension WHERE extname = e.nome))
       ) THEN 'OK' ELSE '*** FALTANDO ***' END AS status,
       CASE WHEN e.tipo = 'pk'
            THEN (SELECT pg_get_constraintdef(oid) FROM pg_constraint
                  WHERE conrelid = to_regclass('public.'||e.nome) AND contype = 'p')
            WHEN e.tipo = 'tabela'
            THEN (SELECT count(*)::text || ' colunas' FROM information_schema.columns
                  WHERE table_schema='public' AND table_name = e.nome)
       END AS detalhe
FROM esperado e
ORDER BY e.tipo, e.nome;
