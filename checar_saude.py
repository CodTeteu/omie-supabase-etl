"""
Checagem do banco antes e depois da rotina.

  python checar_saude.py --antes
      Confere se o Supabase responde. Roda no inicio do workflow: se o banco
      estiver fora do ar, a rotina para em segundos em vez de extrair tudo do
      Omie por ~95 minutos sem ter onde gravar.

  python checar_saude.py
      Confere se as tabelas tem dados e escreve um resumo na pagina da
      execucao no GitHub Actions. Sai com erro se alguma estiver vazia.

Com o espelho configurado (SUPABASE_URL_ESPELHO e SUPABASE_KEY_ESPELHO, ver espelho.py), o
--antes tambem testa o banco da Audit (so aviso: a carga do principal roda mesmo assim) e o
final compara a contagem de cada tabela nos dois bancos: diferenca = execucao vermelha.

Com APROVACOES_URL e APROVACOES_KEY, o final tambem consulta o banco das aprovacoes do BI de
Repasse (outro projeto, plano gratuito): o Supabase pausa projeto gratuito depois de 7 dias sem
uso, e o botao de aprovar do relatorio pararia se ninguem o abrisse por uma semana.

Existe porque de 16/09 a 04/10/2026 o projeto Supabase deixou de existir e
todas as execucoes terminaram verdes, sem gravar nada.
"""
import os
import sys
import time

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


def aviso(msg):
    print(f"⚠️ {msg}")
    print(f"::warning::{msg[:500]}")


def contar(url, headers, tabela):
    """Total de registros da tabela (Content-Range com count=exact). Devolve (total, erro)."""
    try:
        r = requests.get(f"{url}/rest/v1/{tabela}?select=*&limit=1",
                         headers={**headers, "Prefer": "count=exact"}, timeout=120)
    except requests.RequestException as e:
        return None, str(e)[:200]
    if r.status_code not in (200, 206):
        return None, f"HTTP {r.status_code} {r.text[:200]}"
    return int(r.headers.get("Content-Range", "*/0").split("/")[-1]), None


def espelho():
    """(url, headers) do banco espelho da Audit, ou (None, None) se nao estiver configurado."""
    url = (os.environ.get("SUPABASE_URL_ESPELHO") or "").rstrip("/")
    chave = os.environ.get("SUPABASE_KEY_ESPELHO")
    if not url or not chave:
        return None, None
    return url, {"apikey": chave, "Authorization": f"Bearer {chave}"}


def aprovacoes():
    """(url, headers) do banco das aprovacoes do BI de Repasse, ou (None, None) se nao estiver configurado."""
    url = (os.environ.get("APROVACOES_URL") or "").rstrip("/")
    chave = os.environ.get("APROVACOES_KEY")
    if not url or not chave:
        return None, None
    return url, {"apikey": chave}


def manter_aprovacoes_ativo():
    """Uma consulta por noite no banco das aprovacoes, para o Supabase nao pausar o projeto.
    Devolve o problema (texto) se ele nao responder em 3 tentativas, ou None."""
    url, headers = aprovacoes()
    if not url:
        return None
    problema = None
    for tentativa in range(3):
        try:
            r = requests.get(f"{url}/rest/v1/repasse_aprovacoes?select=*&limit=1", headers=headers, timeout=30)
            if r.status_code == 200:
                return None
            problema = f"HTTP {r.status_code} {r.text[:150]}"
        except requests.RequestException as e:
            problema = str(e)[:150]
        if tentativa < 2:
            time.sleep(5 * (tentativa + 1))
    return problema


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
        url_e, headers_e = espelho()
        if url_e:
            total, problema = contar(url_e, headers_e, "contas_pagar")
            if problema:
                aviso(f"Banco espelho da Audit nao respondeu em {url_e} ({problema}). A carga do banco principal "
                      f"roda mesmo assim; as gravacoes no espelho vao falhar e a execucao fica vermelha.")
            else:
                print(f"✅ Banco espelho acessivel: {url_e}")
        return

    linhas, vazias = [], []
    for tabela in TABELAS:
        total, problema = contar(url, headers, tabela)
        if problema:
            erro(f"Falha ao contar {tabela}: {problema}")
        linhas.append((tabela, total))
        if total == 0:
            vazias.append(tabela)

    url_e, headers_e = espelho()
    no_espelho, diferentes = {}, []
    if url_e:
        for tabela, total in linhas:
            total_e, problema = contar(url_e, headers_e, tabela)
            no_espelho[tabela] = total_e
            if problema or total_e != total:
                diferentes.append(f"{tabela} ({total:,} no principal, {problema or format(total_e, ',')} no espelho)")

    problema_aprovacoes = manter_aprovacoes_ativo()  # antes dos erros abaixo, que encerram a execucao

    print(f"{'TABELA':<26}{'REGISTROS':>12}" + (f"{'ESPELHO':>12}" if url_e else ""))
    for tabela, total in linhas:
        e = no_espelho.get(tabela)
        extra = (f"{e:>12,}" if e is not None else f"{'?':>12}") if url_e else ""
        print(f"{tabela:<26}{total:>12,}{extra}")

    if url_e:
        resumo("### Registros depois da rotina\n\n| Tabela | Principal | Espelho (Audit) |\n|---|---:|---:|")
        for tabela, total in linhas:
            e = no_espelho.get(tabela)
            resumo(f"| `{tabela}` | {total:,} | {format(e, ',') if e is not None else '?'} |")
    else:
        resumo("### Registros no banco depois da rotina\n\n| Tabela | Registros |\n|---|---:|")
        for tabela, total in linhas:
            resumo(f"| `{tabela}` | {total:,} |")

    if vazias:
        erro(f"Tabela(s) vazia(s) depois da rotina: {', '.join(vazias)}.")
    print("\n✅ Todas as tabelas tem dados.")
    if diferentes:
        erro("O banco espelho da Audit ficou diferente do principal: " + "; ".join(diferentes) +
             ". Rode o workflow Sincronizar Espelho para igualar.")
    if url_e:
        print("✅ Banco espelho da Audit igual ao principal.")
    if problema_aprovacoes:
        erro(f"O banco das aprovacoes do BI de Repasse nao respondeu ({problema_aprovacoes}). Os dados do Omie "
             f"foram gravados normalmente; se o projeto estiver pausado, restaure-o no painel do Supabase.")
    if aprovacoes()[0]:
        print("✅ Banco das aprovacoes do repasse ativo.")


if __name__ == "__main__":
    main()
