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
"""
import sys

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


def substituir_dados_empresa(url, headers, tabela, registros, empresa, rotulo, tamanho_lote=500):
    """
    Apaga os dados da empresa na tabela e grava os novos, em lotes.
    Devolve quantos registros foram efetivamente gravados.

    Se a limpeza falhar, nao grava nada: os dados antigos ficam intactos.
    """
    nome = empresa["empresa"]
    print(f"Limpando base de dados antiga de {tabela} da empresa {nome}...")
    try:
        resp = requests.delete(
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

    gravados = 0
    for i in range(0, len(registros), tamanho_lote):
        lote = registros[i:i + tamanho_lote]
        n_lote = i // tamanho_lote + 1
        try:
            resp = requests.post(f"{url}/rest/v1/{tabela}", json=lote, headers=headers, timeout=60)
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
