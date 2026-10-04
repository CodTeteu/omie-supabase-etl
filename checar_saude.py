"""
Checagem do banco antes e depois da rotina.

  python checar_saude.py --antes
      Confere se o Supabase responde. Roda no inicio do workflow: se o banco
      estiver fora do ar, a rotina para em segundos em vez de extrair tudo do
      Omie por ~95 minutos sem ter onde gravar.

  python checar_saude.py
      Confere se as tabelas tem dados e escreve um resumo na pagina da
      execucao no GitHub Actions. Sai com erro se alguma estiver vazia.

Existe porque de 16/09 a 04/10/2026 o projeto Supabase deixou de existir e
todas as execucoes terminaram verdes, sem gravar nada.
"""
import os
import sys

import requests

TABELAS = [
    "contas_receber_grupo",
    "conta_corrente",
    "movimentos_financeiros",
    "contas_pagar",
    "clientes_grupo",
    "categorias_omie",
    "departamentos_omie",
]


def erro(msg):
    print(f"❌ {msg}")
    print(f"::error::{msg[:500]}")
    sys.exit(1)


def resumo(texto):
    """Escreve no painel 'Summary' da execucao do Actions (se estiver no Actions)."""
    destino = os.environ.get("GITHUB_STEP_SUMMARY")
    if destino:
        with open(destino, "a", encoding="utf-8") as f:
            f.write(texto + "\n")


def main():
    url = (os.environ.get("SUPABASE_URL") or "").rstrip("/")
    chave = os.environ.get("SUPABASE_KEY")
    if not url or not chave:
        erro("SUPABASE_URL e SUPABASE_KEY nao configurados.")
    headers = {"apikey": chave, "Authorization": f"Bearer {chave}"}

    if "--antes" in sys.argv:
        try:
            r = requests.get(f"{url}/rest/v1/contas_pagar?select=codigo_lancamento_omie&limit=1",
                             headers=headers, timeout=30)
        except requests.RequestException as e:
            erro(f"Banco inacessivel em {url} ({e}). Confira no painel do Supabase se o projeto "
                 f"existe e nao esta pausado.")
        if r.status_code != 200:
            erro(f"Banco respondeu HTTP {r.status_code} em {url}: {r.text[:200]}")
        print(f"✅ Banco acessivel: {url}")
        return

    linhas, vazias = [], []
    for tabela in TABELAS:
        try:
            r = requests.get(f"{url}/rest/v1/{tabela}?select=*&limit=1",
                             headers={**headers, "Prefer": "count=exact"}, timeout=120)
        except requests.RequestException as e:
            erro(f"Banco inacessivel ao contar {tabela} ({e}).")
        if r.status_code not in (200, 206):
            erro(f"Falha ao contar {tabela}: HTTP {r.status_code} {r.text[:200]}")
        total = int(r.headers.get("Content-Range", "*/0").split("/")[-1])
        linhas.append((tabela, total))
        if total == 0:
            vazias.append(tabela)

    print(f"{'TABELA':<26}{'REGISTROS':>12}")
    for tabela, total in linhas:
        print(f"{tabela:<26}{total:>12,}")

    resumo("### Registros no banco depois da rotina\n\n| Tabela | Registros |\n|---|---:|")
    for tabela, total in linhas:
        resumo(f"| `{tabela}` | {total:,} |")

    if vazias:
        erro(f"Tabela(s) vazia(s) depois da rotina: {', '.join(vazias)}.")
    print("\n✅ Todas as tabelas tem dados.")


if __name__ == "__main__":
    main()
