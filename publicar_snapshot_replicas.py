"""Libera ao Rundeck somente a carga integral validada dos dois Supabase."""

import os
import sys
import time

import requests

from controle_execucao import consultar, contexto, resumo, validar_fonte


def habilitado():
    return os.environ.get("REPLICAS_ATIVAS", "").lower() == "true"


def headers():
    key = os.environ["SUPABASE_KEY_ESPELHO"]
    return {"apikey": key, "Authorization": "Bearer " + key}


def snapshot():
    base = os.environ["SUPABASE_URL_ESPELHO"].rstrip("/")
    for attempt in range(3):
        try:
            response = requests.get(
                base + "/rest/v1/omie_replica_snapshot",
                params={
                    "select": "geracao,estado,run_id,tentativa,ciclo,referencia",
                    "id": "eq.true",
                },
                headers=headers(),
                timeout=30,
            )
            if response.status_code == 200:
                rows = response.json()
                if len(rows) == 1:
                    return rows[0]
        except requests.RequestException:
            pass
        if attempt < 2:
            time.sleep(3)
    raise RuntimeError("Nao foi possivel consultar o snapshot do espelho Audit")


def pendente(estado):
    if not habilitado():
        return False
    try:
        carga = validar_fonte(estado)
    except RuntimeError:
        return False
    current = snapshot()
    return not (
        current.get("estado") == "pronto"
        and (current.get("run_id"), current.get("tentativa"))
        == (carga["run_id"], carga["tentativa"])
    )


def main():
    if not habilitado():
        print("Publicacao de replicas ainda desativada")
        return
    if "--validar" in sys.argv:
        state = snapshot()
        print(
            f"Controle de replicas disponivel: estado={state['estado']}, geracao={state['geracao']}"
        )
        return
    ciclo, referencia = contexto()
    carga = validar_fonte(consultar(ciclo, referencia))
    marker = snapshot()
    payload = {
        **carga,
        "ciclo": ciclo,
        "referencia": referencia,
        "geracao": marker["geracao"],
    }
    base = os.environ["SUPABASE_URL_ESPELHO"].rstrip("/")
    for attempt in range(3):
        # Antes de cada envio, impedir que uma carga nova seja confundida com esta.
        latest = validar_fonte(consultar(ciclo, referencia))
        if (latest["run_id"], latest["tentativa"]) != (
            carga["run_id"],
            carga["tentativa"],
        ):
            raise RuntimeError(
                "Outra carga concluiu durante a publicacao; tentar novamente"
            )
        try:
            response = requests.post(
                base + "/rest/v1/rpc/publicar_snapshot_omie",
                json={"p_dados": payload},
                headers=headers(),
                timeout=35,
            )
            if response.status_code == 200:
                print(
                    f"Snapshot publicado para replicas: ciclo={ciclo}, run={carga['run_id']}"
                )
                resumo(
                    f"\nSnapshot dos novos Data Lakes liberado: **{ciclo} / {referencia}**."
                )
                return
            if response.status_code < 500:
                break
        except requests.RequestException:
            pass
        if attempt < 2:
            time.sleep(5)
    raise RuntimeError(
        "Snapshot nao publicado; a reserva deve retomar sem repetir a extracao"
    )


if __name__ == "__main__":
    main()
