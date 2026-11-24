CREATE OR REPLACE FUNCTION public.omie_substituir_categorias(p_empresa text, p_registros jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
    gravadas integer;
BEGIN
    IF nullif(btrim(p_empresa), '') IS NULL
       OR jsonb_typeof(p_registros) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Empresa ou lista de categorias inválida' USING ERRCODE = '22023';
    END IF;
    IF jsonb_array_length(p_registros) = 0 OR EXISTS (
        SELECT 1
        FROM jsonb_to_recordset(p_registros) AS c(codigo text, empresa_cnpj text)
        WHERE c.empresa_cnpj IS DISTINCT FROM p_empresa OR nullif(btrim(c.codigo), '') IS NULL
    ) THEN
        RAISE EXCEPTION 'O lote deve ter categorias válidas da mesma empresa' USING ERRCODE = '22023';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('omie-categorias:' || p_empresa, 0));
    DELETE FROM public.categorias_omie WHERE empresa_cnpj = p_empresa;
    INSERT INTO public.categorias_omie (codigo, empresa_nome, empresa_cnpj, descricao)
    SELECT c.codigo, c.empresa_nome, c.empresa_cnpj, c.descricao
    FROM jsonb_to_recordset(p_registros) AS c(codigo text, empresa_nome text, empresa_cnpj text, descricao text);
    GET DIAGNOSTICS gravadas = ROW_COUNT;
    RETURN gravadas;
END;
$$;

REVOKE ALL ON FUNCTION public.omie_substituir_categorias(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.omie_substituir_categorias(text, jsonb) TO service_role;
NOTIFY pgrst, 'reload schema';
