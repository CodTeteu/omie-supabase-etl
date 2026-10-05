"""
Decide se a rotina agendada roda a carga.

O GitHub atrasa execucoes agendadas em horas e, sob carga, pode descarta-las
sem aviso. Na primeira noite do horario novo (05/10/2026) a das 00:07 so
chegou as 07:17; a rotina original, marcada para 00:00, comecava entre 04:46
e 06:53. E um disparo que nunca chega nao roda nada e nao alerta ninguem.
Por isso a rotina tem tres disparos (00:07, 04:07 e 08:07 em Brasilia), e
este script evita que mais de um faca a carga no mesmo dia.

Roda a carga quando:
  - o disparo e manual; ou
  - os dados ainda nao foram atualizados HOJE (dia no horario de Brasilia) e
    nao ha execucao anterior desta rotina em andamento.

O criterio e o DIA, nao "ha quantas horas": uma carga que atrasou ate a tarde
nao pode fazer a madrugada seguinte achar que os dados ainda estao frescos.

Na duvida (banco ou API do GitHub sem resposta), roda: melhor uma carga a
mais do que um dia sem dados. So usa a biblioteca padrao do Python.
Escreve rodar=true|false em $GITHUB_OUTPUT.
"""
import json
import os
import re
import urllib.request
from datetime import datetime, timedelta, timezone

BRASILIA = timezone(timedelta(hours=-3))  # sem horario de verao desde 2019
PRINCIPAL = "7 3 * * *"                    # 00:07 em Brasilia; os outros sao reserva


def decidir(evento, disparo, ultima_carga, agora, anteriores_em_andamento):
    """Regra de decisao, sem rede. Devolve (rodar, motivo, aviso)."""
    if evento != "schedule":
        return True, "disparo manual: roda sempre", None
    if anteriores_em_andamento:
        return False, "outra execucao da rotina ja esta rodando", None
    hoje = agora.astimezone(BRASILIA).date()
    if ultima_carga is not None and ultima_carga.astimezone(BRASILIA).date() >= hoje:
        quando = ultima_carga.astimezone(BRASILIA).strftime("%H:%M")
        return False, f"dados ja atualizados hoje, as {quando} (Brasilia)", None
    aviso = None
    if disparo != PRINCIPAL:
        aviso = ("A carga da meia-noite ainda nao aconteceu hoje (o GitHub atrasou ou nao "
                 "disparou, ou ela falhou antes de gravar). Fazendo a carga agora, no "
                 "disparo de reserva.")
    return True, "dados ainda nao atualizados hoje", aviso


def converter_data(texto):
    """'2026-10-04T19:37:12.12345+00:00' -> datetime com fuso horario."""
    m = re.match(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.\d+)?(Z|[+-]\d{2}:?\d{2})?$", texto.strip())
    if not m:
        raise ValueError(f"data em formato inesperado: {texto!r}")
    base = datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")
    fuso = m.group(2) or "+00:00"
    if fuso == "Z":
        return base.replace(tzinfo=timezone.utc)
    sinal = 1 if fuso[0] == "+" else -1
    return base.replace(tzinfo=timezone(sinal * timedelta(hours=int(fuso[1:3]), minutes=int(fuso[-2:]))))


def _get_json(url, headers):
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def ler_ultima_carga():
    """Hora da gravacao mais recente: a rotina regrava contas a receber todo dia,
    e o banco preenche data_integracao sozinho (DEFAULT now())."""
    url = os.environ["SUPABASE_URL"].rstrip("/")
    chave = os.environ["SUPABASE_KEY"]
    dados = _get_json(f"{url}/rest/v1/contas_receber_grupo?select=data_integracao"
                      f"&order=data_integracao.desc.nullslast&limit=1",
                      {"apikey": chave, "Authorization": f"Bearer {chave}"})
    if not dados or not dados[0].get("data_integracao"):
        return None
    return converter_data(dados[0]["data_integracao"])


def contar_anteriores_em_andamento():
    """Execucoes desta rotina em andamento ou na fila que comecaram ANTES desta.
    So as anteriores contam: se o GitHub entregar dois disparos atrasados ao
    mesmo tempo, o mais antigo roda e o outro desiste - e nao os dois."""
    repo = os.environ["GITHUB_REPOSITORY"]
    propria = int(os.environ["GITHUB_RUN_ID"])
    headers = {"Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
               "Accept": "application/vnd.github+json"}
    total = 0
    for status in ("in_progress", "queued"):
        dados = _get_json(f"https://api.github.com/repos/{repo}/actions/workflows/schedule.yml/runs"
                          f"?status={status}&per_page=20", headers)
        total += sum(1 for r in dados.get("workflow_runs", []) if r["id"] < propria)
    return total


def main():
    evento = os.environ.get("EVENTO", "")
    disparo = os.environ.get("DISPARO", "")
    try:
        ultima = ler_ultima_carga()
    except Exception as e:
        print(f"Nao foi possivel ler a data da ultima carga ({e}); na duvida, roda.")
        ultima = None
    try:
        anteriores = contar_anteriores_em_andamento()
    except Exception as e:
        print(f"Nao foi possivel consultar execucoes em andamento ({e}); na duvida, roda.")
        anteriores = 0

    rodar, motivo, aviso = decidir(evento, disparo, ultima, datetime.now(timezone.utc), anteriores)
    print(f"Disparo: {evento} {disparo}".strip())
    print(f"Ultima carga: {ultima.astimezone(BRASILIA):%d/%m %H:%M} (Brasilia)" if ultima
          else "Ultima carga: desconhecida")
    print(f"Decisao: {'RODAR' if rodar else 'NAO RODAR'} - {motivo}")
    if aviso:
        print(f"::warning::{aviso}")
    destino = os.environ.get("GITHUB_OUTPUT")
    if destino:
        with open(destino, "a", encoding="utf-8") as f:
            f.write(f"rodar={'true' if rodar else 'false'}\n")


if __name__ == "__main__":
    main()
