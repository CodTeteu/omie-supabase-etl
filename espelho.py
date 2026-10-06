"""
Espelho: repete no banco da Audit toda gravacao que a rotina faz no banco principal.

Com SUPABASE_URL_ESPELHO e SUPABASE_KEY_ESPELHO configurados, cada gravacao (POST, PATCH,
PUT ou DELETE) que um script faz na API REST do banco principal (SUPABASE_URL/rest/v1/...)
e repetida logo em seguida, igual, no banco espelho. Vale para o requests (gravacao.py e os
scripts) e para o cliente supabase-py dos sync_*.py, que usa httpx. Os dados do Omie sao
lidos uma vez so: a API do Omie nao e consultada de novo.

- Leituras nao sao repetidas: a rotina decide o que gravar olhando o banco principal.
- So repete o que o principal aceitou (resposta 2xx). Gravacao recusada no principal ja
  aparece como falha no proprio script.
- Falha no espelho vira falha() de gravacao.py: a execucao fica vermelha e o GitHub avisa
  por email. A resposta que o script recebe e sempre a do principal, que e gravado igual.
- Depois de MAX_FALHAS_SEGUIDAS falhas seguidas (banco espelho fora do ar), o espelho para
  nesta etapa: sem isso, cada lote esperaria o timeout e a rotina levaria horas.
- Sem as duas variaveis, nao faz nada.

Criado em 05/10/2026: o projeto omie-supabase-etl da organizacao audit.tec recebe os
mesmos dados do banco principal.
Se os dois divergirem, sincronizar_espelho.py copia tudo do principal para o espelho.
"""
import os

import requests

METODOS = {"POST", "PATCH", "PUT", "DELETE"}
MAX_FALHAS_SEGUIDAS = 5
TIMEOUT_PADRAO = 120

_estado = {"ativo": False, "parado": False, "repetidas": 0, "falhas": 0, "seguidas": 0}
_config = {"url": "", "url_espelho": "", "chave_espelho": ""}


def ativo():
    return _estado["ativo"] and not _estado["parado"]


def resumo():
    return dict(_estado)


def alvo(url):
    """Endereco no espelho para uma URL da API REST do principal, ou None se nao for gravacao espelhavel."""
    if not ativo() or not isinstance(url, str):
        return None
    base = _config["url"] + "/rest/v1/"
    if not url.startswith(base):
        return None
    return _config["url_espelho"] + "/rest/v1/" + url[len(base):]


def cabecalhos(originais):
    """Copia os cabecalhos trocando a chave do principal pela do espelho."""
    chave = _config["chave_espelho"]
    novos = {}
    for nome, valor in (originais or {}).items():
        minusculo = nome.lower()
        if minusculo == "apikey":
            novos[nome] = chave
        elif minusculo == "authorization":
            novos[nome] = f"Bearer {chave}"
        elif minusculo in ("host", "content-length"):
            continue
        else:
            novos[nome] = valor
    return novos


def _tabela(url):
    resto = url.split("/rest/v1/", 1)[-1]
    return resto.split("?", 1)[0]


def _registrar(ok, metodo, url, detalhe=""):
    if ok:
        _estado["repetidas"] += 1
        _estado["seguidas"] = 0
        return
    _estado["falhas"] += 1
    _estado["seguidas"] += 1
    from gravacao import falha  # aqui dentro: gravacao.py importa este modulo
    falha(f"Espelho (banco da Audit): {metodo} em {_tabela(url)} nao gravou ({detalhe})")
    if _estado["seguidas"] >= MAX_FALHAS_SEGUIDAS and not _estado["parado"]:
        _estado["parado"] = True
        falha(f"Espelho (banco da Audit): {MAX_FALHAS_SEGUIDAS} falhas seguidas; o espelho parou nesta etapa. "
              f"Depois de resolver, rode sincronizar_espelho.py para igualar os bancos.")


# --- requests --------------------------------------------------------------------------------

_request_original = requests.sessions.Session.request


def _request_espelhado(self, method, url, *args, **kwargs):
    resposta = _request_original(self, method, url, *args, **kwargs)
    metodo = str(method).upper()
    destino = alvo(url) if metodo in METODOS else None
    if destino and 200 <= resposta.status_code < 300:
        juntos = dict(self.headers)
        juntos.update(kwargs.get("headers") or {})
        extra = dict(kwargs)
        extra["headers"] = cabecalhos(juntos)
        extra.setdefault("timeout", TIMEOUT_PADRAO)
        try:
            r = _request_original(self, method, destino, *args, **extra)
            _registrar(200 <= r.status_code < 300, metodo, destino, f"HTTP {r.status_code}: {r.text[:200]}")
        except requests.RequestException as e:
            _registrar(False, metodo, destino, str(e)[:200])
    return resposta


# --- httpx (supabase-py) ---------------------------------------------------------------------

def _ligar_httpx():
    try:
        import httpx
    except ImportError:
        return
    send_original = httpx.Client.send

    def send_espelhado(self, request, *args, **kwargs):
        resposta = send_original(self, request, *args, **kwargs)
        metodo = request.method.upper()
        destino = alvo(str(request.url)) if metodo in METODOS else None
        if destino and 200 <= resposta.status_code < 300:
            try:
                copia = httpx.Request(metodo, destino, headers=cabecalhos(dict(request.headers)), content=request.content)
                r = send_original(self, copia, *args, **kwargs)
                _registrar(200 <= r.status_code < 300, metodo, destino, f"HTTP {r.status_code}: {r.text[:200]}")
            except httpx.HTTPError as e:
                _registrar(False, metodo, destino, str(e)[:200])
        return resposta

    httpx.Client.send = send_espelhado


def ligar():
    """Liga o espelho se SUPABASE_URL, SUPABASE_URL_ESPELHO e SUPABASE_KEY_ESPELHO estiverem configurados."""
    if _estado["ativo"]:
        return True
    url = (os.environ.get("SUPABASE_URL") or "").rstrip("/")
    url_espelho = (os.environ.get("SUPABASE_URL_ESPELHO") or "").rstrip("/")
    chave_espelho = os.environ.get("SUPABASE_KEY_ESPELHO") or ""
    if not (url and url_espelho and chave_espelho):
        return False
    if url_espelho == url:
        print("⚠️ Espelho desligado: SUPABASE_URL_ESPELHO e igual a SUPABASE_URL.")
        return False
    _config.update(url=url, url_espelho=url_espelho, chave_espelho=chave_espelho)
    requests.sessions.Session.request = _request_espelhado
    _ligar_httpx()
    _estado["ativo"] = True
    print(f"🪞 Espelho ligado: cada gravacao tambem vai para {url_espelho}")
    return True


ligar()
