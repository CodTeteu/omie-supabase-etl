"""
Empresas do grupo e carregamento das credenciais da API Omie.

As credenciais NAO ficam no codigo. Vem da variavel de ambiente
OMIE_CREDENCIAIS, um JSON no formato:

    {"<cnpj>": {"app_key": "...", "app_secret": "..."}, ...}

No GitHub Actions isso vem do secret OMIE_CREDENCIAIS. Para rodar local,
exporte a variavel antes:  export OMIE_CREDENCIAIS="$(cat credenciais.json)"

Nome e CNPJ nao sao segredo e ficam versionados aqui.
"""
import os
import sys
import json

# "suspensa_desde" marca uma empresa cuja chave do Omie esta suspensa e cuja
# ausencia ja e conhecida: ela gera so aviso. Qualquer OUTRA empresa que deixe
# de carregar deixa a execucao vermelha e o GitHub manda email.
# Quando a chave for reativada no Omie, apague a marcacao.
_EMPRESAS_BASE = [
    {"empresa": 'ALIANÇA LEGAL', "cnpj": '12.340.921/0001-82'},
    {"empresa": 'AUDIT TECNOLOGIA', "cnpj": '44.158.057/0001-99'},
    {"empresa": 'BRAGA E MONTEIRO', "cnpj": '01.501.108/0001-20'},
    {"empresa": 'E-FISCAL OPERACIONAL', "cnpj": '42.622.192/0001-18'},
    {"empresa": 'FERREIRA & MONTEIRO', "cnpj": '56.378.880/0001-99'},
    {"empresa": 'GS EDUCAÇÃO', "cnpj": '36.657.397/0001-36'},
    {"empresa": 'SF CONSULTORIA', "cnpj": '39.287.808/0001-37'},
    {"empresa": 'SPACE W', "cnpj": '36.480.461/0001-56'},
    {"empresa": 'STUDIO ADMINISTRAÇÃO', "cnpj": '27.057.563/0001-72'},
    {"empresa": 'STUDIO AGRONEGÓCIOS', "cnpj": '36.530.240/0001-45'},
    {"empresa": 'STUDIO BANK', "cnpj": '37.852.789/0001-19'},
    {"empresa": 'STUDIO BROKERS', "cnpj": '14.723.195/0001-02'},
    {"empresa": 'STUDIO CONTABILIDADE LTDA', "cnpj": '53.192.862/0001-20'},
    {"empresa": 'STUDIO ENERGY', "cnpj": '34.349.108/0001-06'},
    {"empresa": 'STUDIO FACTORING', "cnpj": '42.275.720/0001-00', "suspensa_desde": "2026-07"},
    {"empresa": 'STUDIO FISCAL', "cnpj": '08.865.854/0001-42'},
    {"empresa": 'STUDIO GROWTH', "cnpj": '36.685.910/0001-00', "suspensa_desde": "2026-09-22"},
    {"empresa": 'STUDIO OPERACIONAL', "cnpj": '23.448.109/0001-91'},
    {"empresa": 'STUDIO OPERACIONAL 01', "cnpj": '62.700.834/0001-67'},
    {"empresa": 'STUDIO PAR', "cnpj": '11.863.345/0001-95'},
    {"empresa": 'STUDIO FAMILY', "cnpj": '39.349.860/0001-70'},
    {"empresa": 'STUDIO SBS STORE', "cnpj": '58.420.510/0001-06'},
    {"empresa": 'STUDIO STORE', "cnpj": '48.552.493/0001-07'},
    {"empresa": 'STUDIO VAREJO', "cnpj": '44.189.727/0001-34'}
]


def carregar_empresas():
    """Monta a lista de empresas com credenciais. Encerra se nao houver nenhuma."""
    bruto = os.environ.get("OMIE_CREDENCIAIS")
    if not bruto:
        print("ERRO: variavel de ambiente OMIE_CREDENCIAIS nao configurada.")
        sys.exit(1)
    try:
        creds = json.loads(bruto)
    except json.JSONDecodeError as e:
        print(f"ERRO: OMIE_CREDENCIAIS nao e um JSON valido: {e}")
        sys.exit(1)

    saida, faltando = [], []
    for emp in _EMPRESAS_BASE:
        c = creds.get(emp["cnpj"]) or {}
        if not c.get("app_key") or not c.get("app_secret"):
            faltando.append(f'{emp["empresa"]} ({emp["cnpj"]})')
            continue
        saida.append({**emp, "app_key": c["app_key"], "app_secret": c["app_secret"]})

    if faltando:
        print(f"AVISO: {len(faltando)} empresa(s) sem credencial em OMIE_CREDENCIAIS, serao puladas:")
        for f in faltando:
            print(f"   - {f}")
    if not saida:
        print("ERRO: nenhuma empresa com credencial valida em OMIE_CREDENCIAIS.")
        sys.exit(1)
    return saida


EMPRESAS = carregar_empresas()
