"""
Gravacao no Supabase com falha visivel.

Os scripts imprimiam o erro e seguiam em frente, e o workflow do GitHub
Actions terminava como sucesso mesmo sem gravar nada. Foi assim que o banco
ficou fora do ar de 16/09 a 04/10/2026 com todas as execucoes verdes.

Aqui toda gravacao que nao acontece e registrada com falha(), aparece como
anotacao de erro no Actions e, no fim da rotina, encerrar() sai com codigo 1:
o workflow fica vermelho e o GitHub avisa por email.

Problemas que nao perdem dados ja gravados (ex.: empresa com chave suspensa
no Omie, cujos dados antigos sao preservados) usam aviso(): aparecem no
Actions sem derrubar a execucao.

Toda tabela e gravada do zero, empresa por empresa (substituir_dados_empresa),
para que nada excluido no Omie fique no banco. A unica excecao e a extracao
incompleta (extracao_completa): ai nada e apagado.
"""
import sys
import time

import requests

import espelho  # noqa: F401 - liga o espelho no banco da Audit, se SUPABASE_URL_ESPELHO estiver configurado

_falhas = []


def falha(msg):
    """Registra uma gravacao que nao aconteceu. Faz a rotina terminar com erro."""
    _falhas.append(msg)
    print(f"❌ {msg}")
    print(f"::error::{msg[:500]}")


def aviso(msg):
    """Registra um problema que nao perde dados. Nao derruba a execucao."""
    print(f"⚠️ {msg}")
    print(f"::warning::{msg[:500]}")


def empresa_fora(rotulo, empresa, motivo):
    """
    Empresa que nao carregou (ex.: chave do Omie suspensa). Se estiver marcada
    com "suspensa_desde" em empresas.py, e uma ausencia conhecida: so aviso.
    Qualquer outra vira falha - execucao vermelha e email.

    Existe porque a STUDIO GROWTH ficou fora de 22/09 a 04/10/2026 sem ninguem
    perceber: um aviso amarelo no Actions nao gera email.
    """
    msg = f"{rotulo} / {empresa['empresa']}: {motivo}. Dados antigos preservados."
    if empresa.get("suspensa_desde"):
        aviso(f"{msg} Suspensa conhecida desde {empresa['suspensa_desde']}.")
    else:
        falha(msg)


def com_segunda_chance(empresas, processar, espera=120):
    """
    Roda processar(empresa, ultima_chance) para cada empresa. processar devolve
    False quando a extracao do Omie falhou e a empresa merece outra tentativa.
    Essas sao tentadas de novo no fim, depois de uma espera: instabilidade do
    Omie costuma passar em minutos. Em 07/10/2026, a conta corrente da STUDIO
    OPERACIONAL caiu com HTTP 500 tres vezes seguidas na mesma pagina, que
    horas depois respondia normalmente - e a noite ficou vermelha por isso.

    Empresa com suspensao conhecida (suspensa_desde em empresas.py) nao espera
    a segunda chance: ja vai como ultima_chance.
    """
    pendentes = [e for e in empresas if not processar(e, bool(e.get("suspensa_desde")))]
    if not pendentes:
        return
    nomes = ", ".join(e["empresa"] for e in pendentes)
    print(f"\nSegunda chance em {espera}s para {len(pendentes)} empresa(s) cuja extracao falhou: {nomes}")
    time.sleep(espera)
    for empresa in pendentes:
        processar(empresa, True)


def extracao_completa(rotulo, empresa, baixados, total_omie):
    """
    Confere, antes de apagar, se veio do Omie tudo o que ele diz ter.

    Faltando registro (pagina que nao veio, registro que o zoom progressivo
    nao recuperou, lista cortada no meio), a empresa NAO e apagada: so os
    registros que vieram sao atualizados, os demais ficam como estavam, com
    aviso. Apagar com a extracao pela metade sumiria com dados que existem.
    Vir a mais (lancamento incluido durante a extracao) nao e falta.
    Sem total informado, confia na paginacao.
    """
    if total_omie is None or baixados >= total_omie:
        return True
    aviso(f"{rotulo} / {empresa['empresa']}: vieram {baixados} de {total_omie} registros que o Omie informa. "
          "Nada foi apagado: so os que vieram foram atualizados; os demais ficam como estavam.")
    return False


def _com_repeticao(metodo, *args, tentativas=3, **kwargs):
    """
    Chamada ao Supabase repetida em erro de rede ou HTTP 5xx (espera 3 s, 6 s).
    Apagar a empresa e gravar com merge-duplicates podem ser repetidos sem
    efeito colateral. Devolve a ultima resposta ou levanta o ultimo erro.
    """
    for t in range(tentativas):
        try:
            resp = metodo(*args, **kwargs)
        except requests.RequestException:
            if t == tentativas - 1:
                raise
        else:
            if resp.status_code < 500 or t == tentativas - 1:
                return resp
        time.sleep(3 * (t + 1))


def substituir_dados_empresa(url, headers, tabela, registros, empresa, rotulo, tamanho_lote=500,
                             apagar_antes=True):
    """
    Apaga os dados da empresa na tabela e grava os novos, em lotes: a carga
    do zero de cada noite, empresa por empresa. Devolve quantos registros
    foram efetivamente gravados.

    Se a limpeza falhar, nao grava nada: os dados antigos ficam intactos.
    Com apagar_antes=False (extracao incompleta, ver extracao_completa) so
    atualiza os registros que vieram, sem apagar nenhum - os headers precisam
    pedir "resolution=merge-duplicates".
    """
    nome = empresa["empresa"]
    if apagar_antes:
        print(f"Limpando base de dados antiga de {tabela} da empresa {nome}...")
        try:
            resp = _com_repeticao(
                requests.delete,
                f"{url}/rest/v1/{tabela}",
                headers=headers,
                params={"empresa_cnpj": f"eq.{empresa['cnpj']}"},
                timeout=60,
            )
        except requests.RequestException as e:
            falha(f"{rotulo} / {nome}: nao foi possivel limpar os dados antigos ({e})")
            return 0
        if resp.status_code not in (200, 204):
            falha(f"{rotulo} / {nome}: limpeza recusada pelo Supabase (HTTP {resp.status_code}: {resp.text[:200]})")
            return 0
    else:
        print(f"Atualizando {tabela} da empresa {nome} sem apagar nada (extracao incompleta)...")

    gravados = 0
    for i in range(0, len(registros), tamanho_lote):
        lote = registros[i:i + tamanho_lote]
        n_lote = i // tamanho_lote + 1
        try:
            resp = _com_repeticao(requests.post, f"{url}/rest/v1/{tabela}", json=lote, headers=headers, timeout=60)
        except requests.RequestException as e:
            falha(f"{rotulo} / {nome}: lote {n_lote} nao enviado ({e})")
            continue
        if resp.status_code in (200, 201):
            gravados += len(lote)
        else:
            falha(f"{rotulo} / {nome}: lote {n_lote} recusado (HTTP {resp.status_code}: {resp.text[:200]})")

    if gravados == len(registros):
        print(f"✅ {gravados} registros gravados em {tabela} para {nome}")
    else:
        print(f"⚠️ Apenas {gravados} de {len(registros)} registros gravados em {tabela} para {nome}")
    return gravados


def encerrar(rotina):
    """Chamar no fim da rotina: sai com codigo 1 se alguma gravacao falhou."""
    if _falhas:
        print(f"\n{rotina}: {len(_falhas)} falha(s) de gravacao. Encerrando com erro.")
        sys.exit(1)
    print(f"\n{rotina}: concluida sem falhas de gravacao.")
