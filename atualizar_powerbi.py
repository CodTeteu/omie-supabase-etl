"""Rodadas financeiras das 14h/18h, depois de uma carga completa do mesmo ciclo."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import threading
import time
from datetime import datetime, timedelta, timezone

import requests

import controle_execucao as controle

PBI = "https://api.powerbi.com/v1.0/myorg"
TERMINAIS = {"Completed", "Failed", "Cancelled", "Disabled"}
TRANSITORIO = re.compile(
    r"EMAXCONNSESSION|max clients|timeout|timed out|tempo limite|GatewayUnreachable|"
    r"GatewayNotReachable|Gateway_Offline|connection.*(closed|reset)|could not connect|"
    r"Unknown message code|converter bytes|translate bytes|Exception while reading from stream|"
    r"MashupDataAccessInternalError|Service Unavailable|TooManyRequests|not enough space left in the buffer|"
    r"network-related or instance-specific|transport-level error|Container exited|HTTP 429", re.I)
CREDENCIAL = re.compile(r"credential|Unauthorized|Forbidden|AccessDenied|CancelledByUser", re.I)


def data(texto):
    return datetime.fromisoformat(texto.replace("Z", "+00:00"))


def ativo(linha):
    return linha.get("status") not in TERMINAIS and not linha.get("endTime")


def pode_repetir(erro):
    return bool(TRANSITORIO.search(erro)) and not CREDENCIAL.search(erro)


class API:
    def __init__(self):
        self._token = None
        self._expira = 0
        self._lock = threading.Lock()

    def token(self):
        with self._lock:
            if self._expira - time.time() > 180:
                return self._token
            tenant = os.environ["POWERBI_TENANT"]
            r = requests.post(f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token",
                              data={"grant_type": "client_credentials",
                                    "client_id": os.environ["POWERBI_CLIENT_ID"],
                                    "client_secret": os.environ["POWERBI_CLIENT_SECRET"],
                                    "scope": "https://analysis.windows.net/powerbi/api/.default"}, timeout=35)
            if r.status_code != 200:
                raise RuntimeError(f"Autenticacao Power BI recusada: HTTP {r.status_code}")
            resposta = r.json()
            self._token = resposta["access_token"]
            self._expira = time.time() + int(resposta["expires_in"])
            return self._token

    def get(self, caminho):
        for tentativa in range(3):
            try:
                r = requests.get(f"{PBI}{caminho}", headers={"Authorization": f"Bearer {self.token()}"}, timeout=45)
            except requests.RequestException:
                if tentativa == 2:
                    raise RuntimeError("Consulta ao Power BI indisponivel (rede)") from None
            else:
                if r.status_code == 200:
                    return r.json()
                if r.status_code < 500 and r.status_code != 429:
                    raise RuntimeError(f"Consulta ao Power BI recusada: HTTP {r.status_code}")
            time.sleep(5 * (tentativa + 1))
        raise RuntimeError("Power BI nao respondeu apos tres consultas")

    def historico(self, modelo):
        return self.get(f"/groups/{modelo['workspace_id']}/datasets/{modelo['id']}/refreshes?$top=60")["value"]

    def atualizar(self, modelo):
        caminho = f"/groups/{modelo['workspace_id']}/datasets/{modelo['id']}/refreshes"
        # O POST nao e repetido automaticamente: uma resposta perdida pode ter iniciado a carga.
        return requests.post(f"{PBI}{caminho}", headers={"Authorization": f"Bearer {self.token()}"},
                             json={"notifyOption": "NoNotification"}, timeout=45)

    def descobrir(self, config):
        grupos = self.get("/groups")["value"]
        grupos = [g for g in grupos if g["name"] == config["workspace"]]
        if len(grupos) != 1:
            raise RuntimeError("Workspace financeiro ausente ou ambiguo")
        workspace = grupos[0]["id"]
        datasets = self.get(f"/groups/{workspace}/datasets")["value"]
        modelos = []
        for nome in config["modelos"]:
            encontrados = [m for m in datasets if m["name"] == nome]
            if len(encontrados) != 1 or not encontrados[0].get("isRefreshable"):
                raise RuntimeError(f"Modelo ausente, ambiguo ou sem atualizacao: {nome}")
            modelo = {"id": encontrados[0]["id"], "name": nome, "workspace_id": workspace}
            fontes = self.get(f"/groups/{workspace}/datasets/{modelo['id']}/datasources")["value"]
            if not any("aws-0-sa-east-1.pooler.supabase.com" in json.dumps(f) for f in fontes):
                raise RuntimeError(f"Fonte financeira atual nao encontrada: {nome}")
            modelos.append(modelo)
        return modelos


def config():
    with Path(__file__).with_name("powerbi_financeiro.json").open(encoding="utf-8") as arquivo:
        resultado = json.load(arquivo)
    if len(resultado["modelos"]) != len(set(resultado["modelos"])):
        raise RuntimeError("Catalogo financeiro tem modelos repetidos")
    return resultado


def aguardar_anteriores(api, modelos):
    limite = time.monotonic() + 2 * 3600
    while True:
        pendentes = [m["name"] for m in modelos if any(ativo(x) for x in api.historico(m))]
        if not pendentes:
            print("Atualizacoes financeiras anteriores encerradas")
            return
        if time.monotonic() >= limite:
            raise RuntimeError("Ainda ha atualizacao financeira ativa. ETL bloqueado para evitar sobreposicao")
        print("Aguardando Power BI antes da carga: " + ", ".join(pendentes), flush=True)
        time.sleep(30)


class Rodada:
    def __init__(self, api, ciclo, referencia, estado):
        self.api = api
        self.ciclo = ciclo
        self.referencia = referencia
        self.carga = controle.validar_fonte(estado)
        self.estados = {r["modelo_id"]: r["dados"] for r in estado.get("powerbi", [])}
        self.corte = max(data(self.carga["finalizado_em"]), controle.horario_powerbi(ciclo, referencia))

    def gravar(self, modelo, estado, **valores):
        registro = {**self.estados.get(modelo["id"], {}), **valores, "estado": estado}
        controle.rpc("powerbi", {"ciclo": self.ciclo, "referencia": self.referencia,
                                 "modelo_id": modelo["id"], "nome": modelo["name"],
                                 "estado": estado, "dados": registro})
        self.estados[modelo["id"]] = registro
        return registro

    def esperar(self, modelo, registro):
        limite = time.monotonic() + 2 * 3600
        anteriores = set(registro.get("anteriores", []))
        while time.monotonic() < limite:
            linhas = self.api.historico(modelo)
            requisicao = registro.get("request_id")
            linha = next((x for x in linhas if requisicao and x.get("requestId") == requisicao), None)
            if linha is None:
                linha = next((x for x in linhas if x.get("requestId") not in anteriores
                              and x.get("startTime") and data(x["startTime"]) >= data(registro["submetido_em"])), None)
            if linha:
                if linha.get("status") in TERMINAIS:
                    return linha
                registro = self.gravar(modelo, "executando", request_id=linha["requestId"])
            time.sleep(20)
        self.gravar(modelo, "incerta", erro="Atualizacao sem resultado final em duas horas")
        raise RuntimeError(f"Resultado ainda incerto: {modelo['name']}. Conferir historico antes de nova solicitacao")

    def enviar(self, modelo, linhas):
        hoje_utc = controle.agora().date()
        usadas = sum(1 for x in linhas if x.get("startTime") and data(x["startTime"]).date() == hoje_utc)
        if usadas >= 8:
            raise RuntimeError(f"Limite diario de atualizacoes atingido: {modelo['name']}")
        tentativas = self.estados.get(modelo["id"], {}).get("tentativas", 0) + 1
        registro = self.gravar(modelo, "submetendo", tentativas=tentativas,
                               anteriores=[x["requestId"] for x in linhas], request_id=None,
                               submetido_em=(controle.agora() - timedelta(seconds=2)).isoformat(), erro=None)
        try:
            resposta = self.api.atualizar(modelo)
        except requests.RequestException:
            # Primeiro concilia pelo historico. Reenviar aqui poderia iniciar duas atualizacoes.
            self.gravar(modelo, "incerta", erro="Resposta de envio perdida; conciliando pelo historico")
        else:
            if resposta.status_code not in (200, 202):
                mensagem = f"Solicitacao recusada: HTTP {resposta.status_code}"
                if resposta.status_code >= 500:
                    self.gravar(modelo, "incerta", erro=mensagem)
                else:
                    self.gravar(modelo, "falhou", erro=mensagem)
                    raise RuntimeError(f"{modelo['name']}: {mensagem}")
            else:
                local = resposta.headers.get("Location", "")
                request_id = local.rstrip("/").split("/")[-1] if "/refreshes/" in local else None
                registro = self.gravar(modelo, "executando", request_id=request_id)
        print(f"Solicitada atualizacao: {modelo['name']}", flush=True)
        return self.esperar(modelo, registro)

    def processar(self, modelo):
        registro = self.estados.get(modelo["id"], {})
        if registro.get("estado") == "concluido":
            return "ja concluido"
        if registro.get("estado") in ("submetendo", "executando", "incerta"):
            linha = self.esperar(modelo, registro)
        else:
            linha = None
        while True:
            if linha:
                sucesso = linha.get("status") == "Completed"
                erro = linha.get("serviceExceptionJson") or linha.get("status", "Falha")
                self.gravar(modelo, "concluido" if sucesso else "falhou",
                            request_id=linha.get("requestId"), fim=linha.get("endTime"), erro=None if sucesso else erro)
                if sucesso:
                    print(f"Concluido: {modelo['name']}", flush=True)
                    return "concluido"
            registro = self.estados.get(modelo["id"], {})
            if registro.get("tentativas", 0) >= 2:
                raise RuntimeError(f"Duas tentativas sem sucesso neste ciclo: {modelo['name']}")
            if registro.get("estado") == "falhou":
                if not pode_repetir(registro.get("erro") or ""):
                    raise RuntimeError(f"Falha requer revisao: {modelo['name']}")
                time.sleep(60)
            linhas = self.api.historico(modelo)
            recentes = [x for x in linhas if x.get("startTime") and data(x["startTime"]) >= self.corte]
            pronto = next((x for x in recentes if x.get("status") == "Completed"), None)
            if pronto:
                linha = pronto
                continue
            em_andamento = next((x for x in linhas if ativo(x)), None)
            if em_andamento:
                if data(em_andamento["startTime"]) < self.corte:
                    aguardar_anteriores(self.api, [modelo])
                    continue
                registro = self.gravar(modelo, "executando", request_id=em_andamento["requestId"],
                                        submetido_em=em_andamento["startTime"], anteriores=[])
                linha = self.esperar(modelo, registro)
            else:
                linha = self.enviar(modelo, linhas)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--validar", action="store_true")
    parser.add_argument("--aguardar", action="store_true")
    args = parser.parse_args()
    ciclo, referencia = controle.contexto()
    estado = controle.consultar(ciclo, referencia)
    if args.aguardar and ciclo == "noturna" and not estado.get("powerbi_pendentes"):
        print("Sem rodada financeira anterior pendente")
        return
    configuracao = config()
    api = API()
    modelos = api.descobrir(configuracao)
    if args.validar:
        for modelo in modelos:
            print(f"Modelo validado: {modelo['name']}")
        print(f"Validacao concluida: {len(modelos)} modelos; nenhuma atualizacao solicitada")
        return
    if args.aguardar:
        aguardar_anteriores(api, modelos)
        return
    if ciclo not in controle.HORAS_POWERBI:
        raise RuntimeError("Este ciclo nao tem rodada financeira programada")
    alvo = controle.horario_powerbi(ciclo, referencia)
    while controle.agora() < alvo:
        time.sleep(min(45, (alvo - controle.agora()).total_seconds()))
    rodada = Rodada(api, ciclo, referencia, controle.consultar(ciclo, referencia))
    erros = []
    with ThreadPoolExecutor(max_workers=configuracao["paralelismo"]) as pool:
        futuros = [(modelo, pool.submit(rodada.processar, modelo)) for modelo in modelos]
        for modelo, futuro in futuros:
            try:
                resultado = futuro.result()
            except Exception as e:
                erros.append(modelo["name"])
                print(f"::error::{modelo['name']}: {str(e)[:350]}")
                resultado = "falhou; consultar historico"
            controle.resumo(f"- {modelo['name']}: {resultado}")
    if erros:
        raise SystemExit(f"Rodada financeira com {len(erros)} pendencia(s)")
    controle.resumo(f"\nRodada {ciclo}: **{len(modelos)} modelos concluidos**.")


if __name__ == "__main__":
    main()
