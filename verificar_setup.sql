-- =============================================================================
-- VERIFICACAO DO PROVISIONAMENTO - ETL Omie -> Supabase
-- Rode no SQL Editor DEPOIS de aplicar provisionar_banco_completo.sql.
-- Esperado: 41 linhas, todas com status OK.
-- =============================================================================
WITH esperado(tipo, nome) AS (
  VALUES
    ('1-extensao','uuid-ossp'),
    ('2-tabela','categorias_omie'), ('2-tabela','clientes_grupo'),
    ('2-tabela','conta_corrente'),  ('2-tabela','contas_pagar'),
    ('2-tabela','contas_receber_grupo'), ('2-tabela','departamentos_omie'),
    ('2-tabela','extrato_bancario'), ('2-tabela','movimentos_financeiros'),
    ('3-pk','categorias_omie'), ('3-pk','clientes_grupo'),
    ('3-pk','conta_corrente'),  ('3-pk','contas_pagar'),
    ('3-pk','contas_receber_grupo'), ('3-pk','departamentos_omie'),
    ('3-pk','extrato_bancario'), ('3-pk','movimentos_financeiros'),
    ('4-view','metas'), ('4-view','metas_bruto'), ('4-view','painel_contas_pagar'),
    ('4-view','view_contas_pagar'), ('4-view','view_contas_receber'),
    ('4-view','view_faturamento_rateado'), ('4-view','view_inadimplencia'),
    ('4-view','vw_contas_receber_detalhada'),
    ('5-rls','categorias_omie'),
    ('5-rls','clientes_grupo'),
    ('5-rls','conta_corrente'),
    ('5-rls','contas_pagar'),
    ('5-rls','contas_receber_grupo'),
    ('5-rls','departamentos_omie'),
    ('5-rls','extrato_bancario'),
    ('5-rls','movimentos_financeiros'),
    ('6-invoker','metas'),
    ('6-invoker','metas_bruto'),
    ('6-invoker','painel_contas_pagar'),
    ('6-invoker','view_contas_pagar'),
    ('6-invoker','view_contas_receber'),
    ('6-invoker','view_faturamento_rateado'),
    ('6-invoker','view_inadimplencia'),
    ('6-invoker','vw_contas_receber_detalhada')
)
SELECT
  e.tipo,
  e.nome,
  CASE WHEN (
       (e.tipo = '1-extensao' AND EXISTS (SELECT 1 FROM pg_extension WHERE extname = e.nome))
    OR (e.tipo = '2-tabela'   AND to_regclass('public.'||quote_ident(e.nome)) IS NOT NULL)
    OR (e.tipo = '4-view'     AND to_regclass('public.'||quote_ident(e.nome)) IS NOT NULL)
    OR (e.tipo = '5-rls'      AND (SELECT relrowsecurity FROM pg_class
                                   WHERE oid = to_regclass('public.'||quote_ident(e.nome))))
    OR (e.tipo = '6-invoker'  AND EXISTS (SELECT 1 FROM pg_class c, unnest(c.reloptions) o
                                          WHERE c.oid = to_regclass('public.'||quote_ident(e.nome))
                                            AND lower(o) ~ '^security_invoker=(on|true|1|yes)$'))
    OR (e.tipo = '3-pk'       AND EXISTS (SELECT 1 FROM pg_constraint
                                          WHERE conrelid = to_regclass('public.'||quote_ident(e.nome))
                                            AND contype = 'p'))
  ) THEN 'OK' ELSE '*** FALTANDO ***' END AS status,
  CASE
    WHEN e.tipo = '3-pk' THEN
      (SELECT pg_get_constraintdef(oid) FROM pg_constraint
       WHERE conrelid = to_regclass('public.'||quote_ident(e.nome)) AND contype = 'p')
    WHEN e.tipo = '2-tabela' THEN
      (SELECT count(*)::text || ' colunas' FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = e.nome)
    WHEN e.tipo = '4-view' THEN
      (SELECT count(*)::text || ' colunas' FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = e.nome)
  END AS detalhe
FROM esperado e
ORDER BY e.tipo, e.nome;
