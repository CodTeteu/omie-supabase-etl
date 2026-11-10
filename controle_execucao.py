"""Controle de cargas completas e das rodadas financeiras, acessivel so pela service_role."""
import argparse
import json
import os
import time
from datetime import date, datetime, timedelta, timezone

import requests

BRASILIA = timezone(timedelta(hours=-3))
CICLOS = {"noturna": 20, "manha": 11, "tarde": 15}
HORAS_POWERBI = {"manha": 14, "tarde": 18}


def agora():
    return datetime.now(timezone.utc)


def inicio_ciclo(quando, ciclo):
    local = quando.astimezone(BRASILIA)
    inicio = local.replace(hour=CICLOS[ciclo], minute=0, second=0, microsecond=0)
    if ciclo == "noturna" and local < inicio:
        inicio -= timedelta(days=1)
    return inicio


def contexto():
    ciclo = os.environ.get("CICLO", "noturna")
    if ciclo not in CICLOS:
        raise ValueError("Ciclo desconhecido")
    referencia = os.environ.get("REFERENCIA") or inicio_ciclo(agora(), ciclo).date().isoformat()
    date.fromisoformat(referencia)
    return ciclo, referencia


def horario_powerbi(ciclo, referencia):
    return datetime.combine(date.fromisoformat(referencia), datetime.min.time(), BRASILIA).replace(
        hour=HORAS_POWERBI[ciclo])


def rpc(acao, dados=None):
    url = os.environ["SUPABASE_URL"].rstrip("/")
    chave = os.environ["SUPABASE_KEY"]
    headers = {"apikey": chave, "Authorization": f"Bearer {chave}"}
    for tentativa in range(3):
        try:
            resposta = requests.post(f"{url}/rest/v1/rpc/etl_operacao", headers=headers,
                                      json={"p_acao": acao, "p_dados": dados or {}}, timeout=35)
        except requests.RequestException:
            if tentativa == 2:
                raise RuntimeError("Controle de execucao indisponivel (rede)") from None
        else:
            if resposta.status_code == 200:
                return resposta.json()
            if resposta.status_code < 500 or tentativa == 2:
                raise RuntimeError(f"Controle de execucao recusou {acao}: HTTP {resposta.status_code}")
        time.sleep(3 * (tentativa + 1))


def consultar(ciclo=None, referencia=None):
    if ciclo is None:
        ciclo, referencia = contexto()
    return rpc("consulta", {"ciclo": ciclo, "referencia": referencia})


def output(nome, valor):
    destino = os.environ.get("GITHUB_OUTPUT")
    if destino:
        with open(destino, "a", encoding="utf-8") as arquivo:
            arquivo.write(f"{nome}={valor}\n")


def resumo(texto):
    destino = os.environ.get("GITHUB_STEP_SUMMARY")
    if destino:
        with open(destino, "a", encoding="utf-8") as arquivo:
            arquivo.write(texto + "\n")


def registrar(estado):
    ciclo, referencia = contexto()
    dados = {"run_id": int(os.environ["GITHUB_RUN_ID"]),
             "tentativa": int(os.environ.get("GITHUB_RUN_ATTEMPT", "1")),
             "ciclo": ciclo, "referencia": referencia, "estado": estado}
    return rpc("iniciar" if estado == "executando" else "finalizar", dados)


def validar_fonte(estado):
    carga = estado.get("execucao") or {}
    ultima = estado.get("ultima_carga") or {}
    if carga.get("estado") != "concluido":
        raise RuntimeError("A carga deste ciclo ainda nao concluiu todas as etapas")
    if (carga.get("run_id"), carga.get("tentativa")) != (ultima.get("run_id"), ultima.get("tentativa")):
        raise RuntimeError("Outra carga comecou depois deste ciclo; rodada antiga bloqueada")
    return carga


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("acao", choices=["iniciar", "finalizar", "validar"])
    args = parser.parse_args()
    if args.acao == "validar":
        versao = rpc("validar")
        print(f"Controle de ciclos disponivel: versao {versao['versao']}")
        return
    if args.acao == "iniciar":
        registrar("executando")
        print("Inicio da carga registrado")
        return
    completo = os.environ.get("ETL_SUCESSO", "").lower() == "true"
    arquivo = os.environ.get("ETL_INCOMPLETUDE_ARQUIVO")
    incompleto = bool(arquivo and os.path.exists(arquivo) and os.path.getsize(arquivo))
    completo = completo and not incompleto
    estado = "concluido" if completo else "falhou"
    registrar(estado)
    output("concluido", str(completo).lower())
    resumo(f"\nCarga do ciclo {contexto()[0]}: **{estado}**.")
    print(f"Carga registrada como {estado}")
    if incompleto:
        raise SystemExit("Extracao incompleta em uma ou mais empresas. Power BI bloqueado neste ciclo.")


if __name__ == "__main__":
    main()
