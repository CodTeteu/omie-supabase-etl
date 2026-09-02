import os
import requests
import json
import time
from datetime import datetime

# Configurações do Supabase
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("ERRO: Variáveis de ambiente SUPABASE_URL e SUPABASE_KEY não configuradas.")
    exit(1)

SUPABASE_URL = SUPABASE_URL.rstrip('/')

from empresas import EMPRESAS

def converter_data(data_br):
    if not data_br:
        return None
    try:
        partes = data_br.split('/')
        return f"{partes[2]}-{partes[1]}-{partes[0]}"
    except:
        return None

def converter_data_hora(data_br, hora_br):
    if not data_br or not hora_br:
        return None
    try:
        data_fmt = converter_data(data_br)
        return f"{data_fmt}T{hora_br}Z"
    except:
        return None

def puxar_conta_corrente(empresa_config):
    pagina = 1
    tem_mais = True
    todos_registros = []
    url = "https://app.omie.com.br/api/v1/financas/contacorrentelancamentos/"
    
    while tem_mais:
        body = {
            "call": "ListarLancCC",
            "app_key": empresa_config["app_key"],
            "app_secret": empresa_config["app_secret"],
            "param": [{"nPagina": pagina, "nRegPorPagina": 100}]
        }
        
        sucesso_na_pagina = False
        for tentativa in range(3):
            try:
                response = requests.post(url, json=body, timeout=30)
                if response.status_code == 200:
                    data = response.json()
                    if "listaLancamentos" in data and len(data["listaLancamentos"]) > 0:
                        for lanc in data["listaLancamentos"]:
                            cabecalho = lanc.get("cabecalho", {})
                            detalhes = lanc.get("detalhes", {})
                            diversos = lanc.get("diversos", {})
                            info = lanc.get("info", {})
                            
                            registro = {
                                "codigo_lancamento": lanc.get("nCodLanc"),
                                "empresa_nome": empresa_config["empresa"],
                                "empresa_cnpj": empresa_config["cnpj"],
                                "id_conta_corrente": cabecalho.get("nCodCC"),
                                "data_lancamento": converter_data(cabecalho.get("dDtLanc")),
                                "valor": cabecalho.get("nValorLanc"),
                                "codigo_categoria": detalhes.get("cCodCateg"),
                                "numero_documento": detalhes.get("cNumDoc"),
                                "tipo_documento": detalhes.get("cTipo"),
                                "observacao": detalhes.get("cObs"),
                                "id_cliente_fornecedor": detalhes.get("nCodCliente"),
                                "id_projeto": detalhes.get("nCodProjeto"),
                                "natureza": diversos.get("cNatureza"),
                                "origem": diversos.get("cOrigem"),
                                "data_conciliacao": converter_data(diversos.get("dDtConc")),
                                "data_inclusao": converter_data(info.get("dInc")),
                                "usuario_inclusao": info.get("uInc"),
                                "last_update": converter_data_hora(info.get("dAlt"), info.get("hAlt")),
                                "departamentos": lanc.get("departamentos"),
                                "categorias": lanc.get("categorias"),
                                "id_origem_receber": diversos.get("nCodLancCR", None),
                                "id_origem_pagar": diversos.get("nCodLancCP", None)
                            }
                            todos_registros.append(registro)
                        
                        sucesso_na_pagina = True
                        pagina += 1
                        break # Sai do retry
                    else:
                        tem_mais = False # Fim das páginas
                        sucesso_na_pagina = True
                        break
                else:
                    print(f"Tentativa {tentativa+1} falhou na página {pagina} com status {response.status_code}. Retentando em 5s...")
                    time.sleep(5)
            except Exception as e:
                print(f"Tentativa {tentativa+1} falhou na página {pagina} com erro: {e}. Retentando em 5s...")
                time.sleep(5)
                
        if not sucesso_na_pagina:
            print(f"FALHA CRÍTICA: Não foi possível baixar a página {pagina} da Omie após 3 tentativas.")
            return None # Sinaliza erro crítico na extração
            
    return todos_registros

def rodar_rotina_cc():
    print("Iniciando rotina de Conta Corrente (Multi-Tenant Omie -> Supabase)...")
    
    headers_supabase = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal, resolution=merge-duplicates"
    }

    # O DELETE GLOBAL FOI REMOVIDO DAQUI POR SEGURANÇA!

    for empresa in EMPRESAS:
        print(f"\nExtraindo Conta Corrente de: {empresa['empresa']}...")
        lancamentos_cc = puxar_conta_corrente(empresa)
        
        if lancamentos_cc is None:
            print(f"⚠️ ERRO DETECTADO NA EXTRAÇÃO DA {empresa['empresa']}.")
            print("PULANDO deleção e inserção para preservar os dados antigos no banco de dados!")
            continue # Pula a deleção e inserção desta empresa
            
        if lancamentos_cc:
            try:
                # 1. Apaga apenas os dados DAQUELA EMPRESA
                print(f"Limpando base de dados antiga de conta_corrente da empresa {empresa['empresa']}...")
                requests.delete(
                    f"{SUPABASE_URL}/rest/v1/conta_corrente", 
                    headers=headers_supabase, 
                    params={"empresa_cnpj": f"eq.{empresa['cnpj']}"}
                )
                
                # 2. Insere os novos dados daquela empresa
                tamanho_lote = 500
                for i in range(0, len(lancamentos_cc), tamanho_lote):
                    lote = lancamentos_cc[i:i + tamanho_lote]
                    resp = requests.post(f"{SUPABASE_URL}/rest/v1/conta_corrente", json=lote, headers=headers_supabase, timeout=60)
                    if resp.status_code not in (200, 201):
                         print(f"❌ Erro na API do Supabase (Conta Corrente): {resp.text}")
                print(f"✅ Inseridos {len(lancamentos_cc)} Lançamentos CC para {empresa['empresa']}")
            except Exception as e:
                print(f"❌ Erro ao enviar Conta Corrente da empresa {empresa['empresa']}: {e}")
        else:
            print(f"Nenhum registro encontrado para {empresa['empresa']}.")

    print("\nFIM DA ROTINA DE CONTA CORRENTE!")

if __name__ == "__main__":
    rodar_rotina_cc()
