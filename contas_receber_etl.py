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
from gravacao import empresa_fora, encerrar, substituir_dados_empresa
import omie_api

def converter_data(data_br):
    if not data_br:
        return None
    try:
        partes = data_br.split('/')
        return f"{partes[2]}-{partes[1]}-{partes[0]}"
    except:
        return None

def tratar_json(obj):
    if not obj:
        return None
    if isinstance(obj, str):
        try:
            return json.loads(obj)
        except json.JSONDecodeError:
            return None
    return obj

def puxar_contas_receber(empresa_config):
    pagina = 1
    tem_mais = True
    todos_registros = []
    url = "https://app.omie.com.br/api/v1/financas/contareceber/"
    
    while tem_mais:
        body = {
            "call": "ListarContasReceber",
            "app_key": empresa_config["app_key"],
            "app_secret": empresa_config["app_secret"],
            "param": [{"pagina": pagina, "registros_por_pagina": 100, "apenas_importado_api": "N"}]
        }
        
        sucesso_na_pagina = False
        for tentativa in range(3):
            try:
                response = requests.post(url, json=body, timeout=30)
                if response.status_code == 200:
                    data = response.json()
                    if "conta_receber_cadastro" in data and len(data["conta_receber_cadastro"]) > 0:
                        for conta in data["conta_receber_cadastro"]:
                            registro = {
                                "codigo_lancamento_omie": conta.get("codigo_lancamento_omie"),
                                "empresa_nome": empresa_config["empresa"],
                                "empresa_cnpj": empresa_config["cnpj"],
                                "codigo_cliente_fornecedor": conta.get("codigo_cliente_fornecedor"),
                                "numero_documento": conta.get("numero_documento"),
                                "numero_documento_fiscal": conta.get("numero_documento_fiscal"),
                                "data_emissao": converter_data(conta.get("data_emissao")),
                                "data_vencimento": converter_data(conta.get("data_vencimento")),
                                "valor_documento": conta.get("valor_documento"),
                                "status_titulo": conta.get("status_titulo"),
                                "codigo_categoria": conta.get("codigo_categoria"),
                                "numero_contrato": conta.get("numero_contrato") or conta.get("cNumeroContrato"),
                                "categorias": tratar_json(conta.get("categorias")),
                                "distribuicao": tratar_json(conta.get("distribuicao"))
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
                    tipo, espera = omie_api.classificar(response.status_code, response.text, tentativa)
                    if tipo == omie_api.PERMANENTE:
                        print(f"Erro permanente do Omie na página {pagina} (HTTP {response.status_code}), sem repetir: {response.text[:150]}")
                        return None
                    if tipo == omie_api.VAZIO:
                        tem_mais = False
                        sucesso_na_pagina = True
                        break
                    print(f"Tentativa {tentativa+1} falhou na página {pagina} com status {response.status_code}. Retentando em {espera}s...")
                    time.sleep(espera)
            except Exception as e:
                espera = omie_api.espera_transitoria(tentativa)
                print(f"Tentativa {tentativa+1} falhou na página {pagina} com erro: {e}. Retentando em {espera}s...")
                time.sleep(espera)
                
        if not sucesso_na_pagina:
            print(f"FALHA CRÍTICA: Não foi possível baixar a página {pagina} da Omie após 3 tentativas.")
            return None # Sinaliza erro crítico na extração
            
    return todos_registros

def rodar_rotina_cr():
    print("Iniciando rotina de Contas a Receber (Multi-Tenant Omie -> Supabase)...")
    
    headers_supabase = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal, resolution=merge-duplicates"
    }

    # O DELETE GLOBAL FOI REMOVIDO DAQUI POR SEGURANÇA!

    for empresa in EMPRESAS:
        print(f"\nExtraindo Contas a Receber de: {empresa['empresa']}...")
        contas = puxar_contas_receber(empresa)
        
        if contas is None:
            empresa_fora("Contas a Receber", empresa, "falha na extracao do Omie")
            continue
            
        if contas:
            substituir_dados_empresa(SUPABASE_URL, headers_supabase, "contas_receber_grupo", contas, empresa, "Contas a Receber")
        else:
            print(f"Nenhum registro encontrado para {empresa['empresa']}.")

    print("\nFIM DA ROTINA DE CONTAS A RECEBER!")
    encerrar("Contas a Receber")

if __name__ == "__main__":
    rodar_rotina_cr()
