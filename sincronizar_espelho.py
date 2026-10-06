"""
Copia o banco principal inteiro para o espelho da Audit, tabela por tabela, pela API REST.

  python sincronizar_espelho.py               # todas as tabelas
  python sincronizar_espelho.py clientes_grupo contas_pagar

Usa SUPABASE_URL e SUPABASE_KEY (principal) e SUPABASE_URL_ESPELHO e SUPABASE_KEY_ESPELHO
(espelho, ver espelho.py). Para cada tabela: apaga tudo no espelho, em lotes de chaves (a API
corta consultas com mais de 8 segundos), copia o principal em paginas de 1.000 linhas
ordenadas pela chave e, no fim, confere se as contagens batem. Diferenca = erro.

Use na primeira carga do espelho e quando o checar_saude.py apontar diferenca entre os bancos
(ex.: o espelho ficou fora do ar durante uma rotina). Pelo workflow "Sincronizar Espelho", que
nao roda junto com a rotina noturna (mesmo grupo de concorrencia).
"""
import os
import sys
import time

import requests

# tabela: chave primaria (extraidas do banco; duas fogem do padrao (codigo, empresa_cnpj))
TABELAS = {
    "categorias_omie": ["codigo", "empresa_cnpj"],
    "departamentos_omie": ["codigo", "empresa_cnpj"],
    "clientes_grupo": ["codigo_cliente_omie", "empresa_cnpj"],
    "contas_receber_grupo": ["codigo_lancamento_omie", "empresa_cnpj"],
    "movimentos_financeiros": ["id_movimento", "empresa_cnpj"],
    "conta_corrente": ["codigo_lancamento", "empresa_cnpj"],
    "contas_pagar": ["codigo_lancamento_omie", "bandeira_id"],
    "extrato_bancario": ["id"],
}
PAGINA = 1000
LOTE = 500


def erro(msg):
    print(f"❌ {msg}")
    print(f"::error::{msg[:500]}")
    sys.exit(1)


def cabecalhos(chave, **extra):
    return {"apikey": chave, "Authorization": f"Bearer {chave}", **extra}


def chamar(metodo, url, tentativas=4, **kw):
    """Requisicao com novas tentativas para falhas passageiras de rede ou 5xx."""
    for t in range(tentativas):
        try:
            r = requests.request(metodo, url, timeout=180, **kw)
        except requests.RequestException as e:
            if t == tentativas - 1:
                raise
            print(f"   rede falhou ({e}); nova tentativa em {5 * (t + 1)}s")
            time.sleep(5 * (t + 1))
            continue
        if r.status_code >= 500 and t < tentativas - 1:
            print(f"   HTTP {r.status_code}; nova tentativa em {5 * (t + 1)}s")
            time.sleep(5 * (t + 1))
            continue
        return r
    return r


def contar(url, chave, tabela):
    r = chamar("GET", f"{url}/rest/v1/{tabela}?select=*&limit=1", headers=cabecalhos(chave, Prefer="count=exact"))
    if r.status_code not in (200, 206):
        erro(f"{tabela}: falha ao contar em {url} (HTTP {r.status_code}: {r.text[:200]})")
    return int(r.headers.get("Content-Range", "*/0").split("/")[-1])


def valor_in(v):
    """Valor para o filtro in.(...) da API, entre aspas (codigos com ponto, virgula ou espaco)."""
    s = str(v).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{s}"'


def limpar_espelho(url_e, chave_e, tabela, coluna):
    """Apaga tudo da tabela no espelho, em lotes de ate PAGINA valores da primeira coluna da chave."""
    apagados = 0
    while True:
        r = chamar("GET", f"{url_e}/rest/v1/{tabela}?select={coluna}&limit={PAGINA}", headers=cabecalhos(chave_e))
        if r.status_code != 200:
            erro(f"{tabela}: falha ao ler o espelho para limpar (HTTP {r.status_code}: {r.text[:200]})")
        valores = sorted({linha[coluna] for linha in r.json()}, key=str)
        if not valores:
            return apagados
        filtro = "in.(" + ",".join(valor_in(v) for v in valores) + ")"
        d = chamar("DELETE", f"{url_e}/rest/v1/{tabela}", params={coluna: filtro},
                   headers=cabecalhos(chave_e, Prefer="return=minimal,count=exact"))
        if d.status_code not in (200, 204):
            erro(f"{tabela}: limpeza do espelho recusada (HTTP {d.status_code}: {d.text[:200]})")
        apagados += int(d.headers.get("Content-Range", "*/0").split("/")[-1] or 0)


def copiar(url, chave, url_e, chave_e, tabela, chave_pk):
    ordem = ",".join(f"{c}.asc" for c in chave_pk)
    copiados, offset = 0, 0
    while True:
        r = chamar("GET", f"{url}/rest/v1/{tabela}?select=*&order={ordem}&limit={PAGINA}&offset={offset}",
                   headers=cabecalhos(chave))
        if r.status_code != 200:
            erro(f"{tabela}: falha ao ler o principal (HTTP {r.status_code}: {r.text[:200]})")
        linhas = r.json()
        for i in range(0, len(linhas), LOTE):
            lote = linhas[i:i + LOTE]
            p = chamar("POST", f"{url_e}/rest/v1/{tabela}", json=lote,
                       headers=cabecalhos(chave_e, Prefer="return=minimal"))
            if p.status_code not in (200, 201, 204):
                erro(f"{tabela}: lote recusado no espelho (HTTP {p.status_code}: {p.text[:200]})")
            copiados += len(lote)
        if len(linhas) < PAGINA:
            return copiados
        offset += PAGINA


def main():
    url = (os.environ.get("SUPABASE_URL") or "").rstrip("/")
    chave = os.environ.get("SUPABASE_KEY")
    url_e = (os.environ.get("SUPABASE_URL_ESPELHO") or "").rstrip("/")
    chave_e = os.environ.get("SUPABASE_KEY_ESPELHO")
    if not (url and chave and url_e and chave_e):
        erro("Configure SUPABASE_URL, SUPABASE_KEY, SUPABASE_URL_ESPELHO e SUPABASE_KEY_ESPELHO.")
    if url == url_e:
        erro("SUPABASE_URL_ESPELHO e igual a SUPABASE_URL: nada a copiar.")

    pedidas = sys.argv[1:] or list(TABELAS)
    desconhecidas = [t for t in pedidas if t not in TABELAS]
    if desconhecidas:
        erro(f"Tabela(s) desconhecida(s): {', '.join(desconhecidas)}")

    print(f"Principal: {url}\nEspelho:   {url_e}\n")
    resultado = []
    for tabela in pedidas:
        inicio = time.time()
        apagados = limpar_espelho(url_e, chave_e, tabela, TABELAS[tabela][0])
        copiados = copiar(url, chave, url_e, chave_e, tabela, TABELAS[tabela])
        n, n_e = contar(url, chave, tabela), contar(url_e, chave_e, tabela)
        resultado.append((tabela, n, n_e))
        print(f"{'✅' if n == n_e else '❌'} {tabela}: {copiados:,} copiadas ({apagados:,} apagadas antes no espelho) · "
              f"principal {n:,} · espelho {n_e:,} · {time.time() - inicio:.0f}s")

    destino = os.environ.get("GITHUB_STEP_SUMMARY")
    if destino:
        with open(destino, "a", encoding="utf-8") as f:
            f.write("### Sincronizacao do espelho\n\n| Tabela | Principal | Espelho |\n|---|---:|---:|\n")
            for tabela, n, n_e in resultado:
                f.write(f"| `{tabela}` | {n:,} | {n_e:,} |\n")

    diferentes = [t for t, n, n_e in resultado if n != n_e]
    if diferentes:
        erro(f"Contagem diferente depois da copia: {', '.join(diferentes)} (o principal pode ter mudado durante a copia).")
    print("\n✅ Espelho igual ao principal.")


if __name__ == "__main__":
    main()
