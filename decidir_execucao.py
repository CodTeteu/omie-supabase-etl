"""Decide cada ciclo usando o registro das sete etapas concluidas.

Noite: 22h, com referencia a partir das 20h. Dias uteis: 11h e 15h, cada um
com sua referencia e rodada do Power BI (14h/18h). O Supabase dispara pela
API; os crons do GitHub sao reservas. Disparos diurnos atrasados respeitam
a janela original. A decisao e repetida depois da fila de concorrencia.

Uma data recente em contas a receber nao comprova que contas a pagar terminou.
Se o controle estiver indisponivel, falha antes da carga. Os outputs tambem
permitem retomar o Power BI sem repetir um ETL ja concluido.
"""
import json
import os
import re
import urllib.request
from datetime import datetime, timedelta, timezone

from controle_execucao import consultar, inicio_ciclo, output

BRASILIA = timezone(timedelta(hours=-3))  # sem horario de verao desde 2019
INICIO_DA_NOITE = 20                       # a noite de carga comeca as 20:00 em Brasilia


def inicio_da_noite(agora):
    """Comeco da noite de carga em que `agora` esta: as 20:00 (Brasilia) mais recentes."""
    local = agora.astimezone(BRASILIA)
    inicio = local.replace(hour=INICIO_DA_NOITE, minute=0, second=0, microsecond=0)
    return inicio if local >= inicio else inicio - timedelta(days=1)


def janela_diurna_aberta(agora, ciclo):
    local = agora.astimezone(BRASILIA)
    inicio, fim = {"manha": (11, 15), "tarde": (15, 22)}[ciclo]
    return local.weekday() < 5 and inicio <= local.hour < fim


def decidir(evento, agendador, ultima_carga, agora, anteriores_em_andamento, ciclo="noturna"):
    """Regra de decisao, sem rede. Devolve (rodar, motivo, aviso)."""
    if evento != "schedule" and not agendador:
        return True, "disparo manual: roda sempre", None
    if ciclo != "noturna" and not janela_diurna_aberta(agora, ciclo):
        return False, "fora da janela util deste ciclo", None
    if anteriores_em_andamento and ciclo == "noturna":
        return False, "outra execucao da rotina ja esta rodando", None
    if ultima_carga is not None and ultima_carga >= inicio_ciclo(agora, ciclo):
        quando = ultima_carga.astimezone(BRASILIA).strftime("%d/%m %H:%M")
        return False, f"carga do ciclo {ciclo} ja feita, em {quando} (Brasilia)", None
    aviso = None
    if not agendador:
        aviso = (f"A carga do ciclo {ciclo} nao veio do agendador principal do Supabase. "
                 "Fazendo agora, pelo agendamento de reserva do GitHub. Se repetir, confira o "
                 "secret github_token_rotina no Vault e a tabela agendador.disparos.")
    return True, f"carga do ciclo {ciclo} ainda nao feita", aviso


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


def ciclo_do_disparo(evento, disparo, escolhido):
    if evento == "schedule":
        return {"7 14 * * 1-5": "manha", "7 18 * * 1-5": "tarde"}.get(disparo, "noturna")
    if escolhido not in ("noturna", "manha", "tarde"):
        raise ValueError("Ciclo desconhecido")
    return escolhido


def powerbi_pendente(estado):
    with open(os.path.join(os.path.dirname(__file__), "powerbi_financeiro.json"), encoding="utf-8") as arquivo:
        nomes = set(json.load(arquivo)["modelos"])
    prontos = {m["nome"] for m in estado.get("powerbi", []) if m["estado"] == "concluido"}
    return not nomes.issubset(prontos)


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
    agendador = os.environ.get("AGENDADOR", "").strip().lower() == "true"
    ciclo = ciclo_do_disparo(evento, disparo, os.environ.get("CICLO", "noturna"))
    agora = datetime.now(timezone.utc)
    referencia = os.environ.get("REFERENCIA") or inicio_ciclo(agora, ciclo).date().isoformat()
    estado = consultar(ciclo, referencia)
    carga = estado.get("execucao") or {}
    ultima = converter_data(carga["iniciado_em"]) if carga.get("estado") == "concluido" else None
    try:
        anteriores = contar_anteriores_em_andamento()
    except Exception as e:
        print(f"Nao foi possivel consultar execucoes em andamento ({e}); na duvida, roda.")
        anteriores = 0

    # Uma rodada diurna longa deixa a noite na fila. So um ciclo noturno ja
    # iniciado deve fazer outro disparo da mesma noite desistir.
    if ciclo == "noturna" and carga.get("estado") != "executando":
        anteriores = 0
    rodar, motivo, aviso = decidir(evento, agendador, ultima, agora, anteriores, ciclo)
    mesma_referencia = referencia == inicio_ciclo(agora, ciclo).date().isoformat()
    if agendador or evento == "schedule":
        rodar = rodar and mesma_referencia
    completar_powerbi = (ciclo != "noturna" and ultima is not None and mesma_referencia
                         and janela_diurna_aberta(agora, ciclo) and powerbi_pendente(estado))
    agenda = estado.get("agenda") or {}
    if ciclo != "noturna" and (agendador or evento == "schedule"):
        habilitado = agenda.get("ativo") and referencia >= (agenda.get("inicio_em") or "9999-12-31")
        if not habilitado:
            rodar = completar_powerbi = False
            motivo = "agendamento diurno ainda nao ativado para esta data"
    print(f"Disparo: agendador do Supabase ({ciclo})" if agendador else f"Disparo: {evento} {disparo}".strip())
    print(f"Ultima carga: {ultima.astimezone(BRASILIA):%d/%m %H:%M} (Brasilia)" if ultima
          else "Ultima carga: desconhecida")
    print(f"Decisao: {'RODAR' if rodar else 'NAO RODAR'} - {motivo}")
    if aviso and rodar:
        print(f"::warning::{aviso}")
    output("ciclo", ciclo)
    output("referencia", referencia)
    output("rodar_etl", str(rodar).lower())
    output("rodar_powerbi", str(ciclo != "noturna" and (rodar or completar_powerbi)).lower())
    output("rodar", str(rodar or completar_powerbi).lower())


if __name__ == "__main__":
    main()
