"""
Regras oficiais de consumo da API do Omie, num lugar so.
https://ajuda.omie.com.br/pt-BR/articles/8112984-limites-de-consumo-da-api-do-omie

- 10 requisicoes com erro seguidas (mesmo IP + chave + metodo) bloqueiam por
  30 minutos (HTTP 425). Insistir em erro so prolonga o bloqueio.
- Chave invalida ou aplicativo suspenso (HTTP 403) e erro PERMANENTE: repetir
  nao adianta.
- "Consumo redundante ... aguarde N segundos": esperar exatamente N.
- "Nao existem registros para a pagina": o Omie as vezes responde 500 quando
  simplesmente nao ha dados. Nao e erro.

Antes, os scripts repetiam cada pagina com erro ate 10 vezes a cada 5 s - e
contas a pagar e departamentos ainda dividiam a pagina e repetiam de novo.
Para uma chave suspensa isso virava dezenas de erros por noite e bloqueios
de 30 minutos em serie.
"""
import re

PERMANENTE = "permanente"    # nao repetir
VAZIO = "vazio"              # sem registros: tratar como sucesso com zero itens
AGUARDAR = "aguardar"        # o Omie mandou esperar
TRANSITORIO = "transitorio"  # instabilidade: repetir com espera crescente


class ErroPermanente(Exception):
    """Erro do Omie que nao adianta repetir agora (chave suspensa, bloqueio 425)."""


def espera_transitoria(tentativa):
    """Espera crescente entre tentativas: 5, 10, 20, 40 s (no maximo 60)."""
    return min(5 * 2 ** tentativa, 60)


def classificar(status, texto, tentativa=0):
    """
    Diz o que fazer com uma resposta de ERRO do Omie (status diferente de 200).
    Devolve (tipo, segundos_de_espera).
    """
    t = (texto or "").lower()

    if status in (403, 425) or "chave de acesso est" in t or "aplicativo est" in t:
        return PERMANENTE, 0

    if "nenhum registro encontrado" in t or "registros para a p" in t:
        return VAZIO, 0

    pedido = re.search(r"aguarde\s+(\d+)\s*segundo", t)
    if pedido:
        return AGUARDAR, int(pedido.group(1)) + 1
    if "redundant" in t or "consumo redundante" in t or "consumo indevido" in t or "existe uma requisi" in t:
        return AGUARDAR, 60

    return TRANSITORIO, espera_transitoria(tentativa)
