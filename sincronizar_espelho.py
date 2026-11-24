"""Reconciliar as tabelas Omie verificando chaves e conteúdo, sem esvaziar o espelho."""

import os
import sys
import time
from urllib.parse import urlsplit

import requests

TABELAS = {
    "categorias_omie": ("codigo", "empresa_cnpj"),
    "departamentos_omie": ("codigo", "empresa_cnpj"),
    "clientes_grupo": ("codigo_cliente_omie", "empresa_cnpj"),
    "contas_receber_grupo": ("codigo_lancamento_omie", "empresa_cnpj"),
    "movimentos_financeiros": ("id_movimento", "empresa_cnpj"),
    "conta_corrente": ("codigo_lancamento", "empresa_cnpj"),
    "contas_pagar": ("codigo_lancamento_omie", "bandeira_id"),
    "extrato_bancario": ("id",),
}
PAGINA = 500
LOTE = 150


class ErroDeSincronizacao(RuntimeError):
    pass


class Banco:
    def __init__(self, cliente, url, chave, nome):
        endereco = urlsplit(url)
        if (
            endereco.scheme != "https"
            or not endereco.hostname
            or endereco.username
            or endereco.password
            or endereco.path not in ("", "/")
            or endereco.query
            or endereco.fragment
        ):
            raise ErroDeSincronizacao(f"Endereço inválido do {nome}.")
        self.cliente = cliente
        self.url = url.rstrip("/")
        self.nome = nome
        self.headers = {"apikey": chave, "Authorization": f"Bearer {chave}"}

    def chamar(self, metodo, tabela, *, esperado, prefer=None, **kwargs):
        headers = dict(self.headers)
        if prefer:
            headers["Prefer"] = prefer
        for tentativa in range(5):
            try:
                response = self.cliente.request(
                    metodo,
                    f"{self.url}/rest/v1/{tabela}",
                    headers=headers,
                    timeout=(12, 90),
                    allow_redirects=False,
                    **kwargs,
                )
            except requests.RequestException as error:
                detalhe = type(error).__name__
            else:
                if response.status_code in esperado:
                    return response
                detalhe = f"HTTP {response.status_code}"
                if response.status_code not in (408, 429) and response.status_code < 500:
                    raise ErroDeSincronizacao(f"{self.nome} {tabela}: {metodo} recusado ({detalhe}).")
            if tentativa < 4:
                print(f"  {self.nome} {tabela}: {metodo} falhou ({detalhe}). Repetindo.", flush=True)
                time.sleep(3 * (tentativa + 1))
        raise ErroDeSincronizacao(f"{self.nome} {tabela}: {metodo} falhou após as tentativas ({detalhe}).")

    def contar(self, tabela, pk):
        resposta = self.chamar(
            "GET", tabela, esperado=(200, 206), prefer="count=exact",
            params={"select": pk[0], "limit": 1, "order": ",".join(pk)},
        )
        _, _, total = resposta.headers.get("Content-Range", "").rpartition("/")
        if not total.isdecimal():
            raise ErroDeSincronizacao(f"{self.nome} {tabela}: contagem exata indisponível.")
        return int(total)

    def fotografia(self, tabela, pk):
        total = self.contar(tabela, pk)
        dados = {}
        while len(dados) < total:
            resposta = self.chamar(
                "GET", tabela, esperado=(200, 206),
                params={"select": "*", "order": ",".join(f"{c}.asc" for c in pk),
                        "limit": PAGINA, "offset": len(dados)},
            )
            try:
                linhas = resposta.json()
                if not isinstance(linhas, list) or not linhas or len(dados) + len(linhas) > total:
                    raise ValueError
                for linha in linhas:
                    chave = tuple(linha[c] for c in pk)
                    if None in chave or chave in dados:
                        raise ValueError
                    dados[chave] = linha
            except (ValueError, KeyError, TypeError) as error:
                raise ErroDeSincronizacao(f"{self.nome} {tabela}: paginação ou chave inconsistente.") from error
        if self.contar(tabela, pk) != total:
            raise ErroDeSincronizacao(f"{self.nome} {tabela}: a contagem mudou durante a leitura.")
        return dados

    def upsert(self, tabela, pk, linhas):
        for inicio in range(0, len(linhas), LOTE):
            self.chamar(
                "POST", tabela, esperado=(200, 201, 204),
                prefer="return=minimal,resolution=merge-duplicates",
                params={"on_conflict": ",".join(pk)}, json=linhas[inicio:inicio + LOTE],
            )


def reconciliar(principal, espelho, tabela, pk):
    # Validate the entire source before the first write. A complete source can
    # repair a missing row or a partially updated row with the same primary key.
    fonte = principal.fotografia(tabela, pk)
    if not fonte and tabela != "extrato_bancario":
        raise ErroDeSincronizacao(f"Principal {tabela}: origem de negócio vazia.")
    anterior = espelho.fotografia(tabela, pk)
    mudancas = [linha for chave, linha in fonte.items() if anterior.get(chave) != linha]
    print(f"{tabela}: principal {len(fonte):,} · Audit {len(anterior):,} · diferenças a repor {len(mudancas):,}.", flush=True)
    if mudancas:
        espelho.upsert(tabela, pk, mudancas)
        depois = espelho.fotografia(tabela, pk)
    else:
        depois = anterior
    ausentes = len(fonte.keys() - depois.keys())
    extras = len(depois.keys() - fonte.keys())
    alteradas = sum(fonte[k] != depois[k] for k in fonte.keys() & depois.keys())
    return len(fonte), len(depois), ausentes, alteradas, extras


def main():
    pedidas = list(dict.fromkeys(sys.argv[1:] or TABELAS))
    if any(tabela not in TABELAS for tabela in pedidas):
        raise ErroDeSincronizacao("Selecione apenas tabelas Omie cadastradas.")
    urls = [os.environ.get(k, "").rstrip("/") for k in ("SUPABASE_URL", "SUPABASE_URL_ESPELHO")]
    chaves = [os.environ.get(k, "") for k in ("SUPABASE_KEY", "SUPABASE_KEY_ESPELHO")]
    if not all(urls + chaves) or urls[0] == urls[1]:
        raise ErroDeSincronizacao("Configure as duas conexões Supabase em destinos distintos.")
    with requests.Session() as cliente:
        principal, espelho = (Banco(cliente, u, key, nome)
                              for u, key, nome in zip(urls, chaves, ("principal", "Audit")))
        resultados = []
        for tabela in pedidas:
            try:
                a, b, ausentes, divergentes, extras = reconciliar(principal, espelho, tabela, TABELAS[tabela])
                iguais = ausentes == divergentes == extras == 0
                detalhe = f"principal={a:,}; Audit={b:,}; ausentes={ausentes}; divergentes={divergentes}; extras preservados={extras}"
                resultados.append((tabela, iguais, detalhe))
                print(f"{tabela}: {'igual por chave e conteúdo' if iguais else 'divergência'} · {detalhe}.", flush=True)
            except ErroDeSincronizacao as error:
                resultados.append((tabela, False, str(error)))
                print(f"::error::{error}", flush=True)
    if resumo := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(resumo, "a", encoding="utf-8") as arquivo:
            arquivo.write("### Reconciliação Omie → Audit\n\n")
            arquivo.write("\n".join(f"- **{t}** · {d}" for t, _, d in resultados) + "\n")
    if not all(iguais for _, iguais, _ in resultados):
        raise ErroDeSincronizacao("O espelho ainda apresenta diferenças nas tabelas verificadas.")
    print("Espelho igual ao principal por chave e conteúdo nas tabelas selecionadas.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except ErroDeSincronizacao as error:
        print(f"::error::{error}", flush=True)
        raise SystemExit(1) from None
