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

def tratar_json(obj):
    if not obj:
        return None
    if isinstance(obj, str):
        try:
            return json.loads(obj)
        except json.JSONDecodeError:
            return None
    return obj

def puxar_clientes(empresa_config):
    todos_registros = []
    url = "https://app.omie.com.br/api/v1/geral/clientes/"
    
    # 🚨 Correção: Fazendo duas passagens. Uma para Ativos (N) e outra para Inativos (S)
    for inativo in ["N", "S"]:
        print(f"    > Buscando Clientes Inativo='{inativo}'...")
        pagina = 1
        tem_mais = True
        
        while tem_mais:
            body = {
                "call": "ListarClientes",
                "app_key": empresa_config["app_key"],
                "app_secret": empresa_config["app_secret"],
                "param": [{
                    "pagina": pagina, 
                    "registros_por_pagina": 100, 
                    "apenas_importado_api": "N",
                    "clientesFiltro": {"inativo": inativo}
                }]
            }
            
            sucesso_na_pagina = False
            for tentativa in range(3):
                try:
                    response = requests.post(url, json=body, timeout=30)
                    if response.status_code == 200:
                        data = response.json()
                        if "clientes_cadastro" in data and len(data["clientes_cadastro"]) > 0:
                            for cliente in data["clientes_cadastro"]:
                                registro = {
                                    "codigo_cliente_omie": cliente.get("codigo_cliente_omie"),
                                    "empresa_nome": empresa_config["empresa"],
                                    "empresa_cnpj": empresa_config["cnpj"],
                                    "cnpj_cpf": cliente.get("cnpj_cpf"),
                                    "razao_social": cliente.get("razao_social"),
                                    "nome_fantasia": cliente.get("nome_fantasia")
                                }
                                todos_registros.append(registro)
                            sucesso_na_pagina = True
                            pagina += 1
                            break
                        else:
                            tem_mais = False
                            sucesso_na_pagina = True
                            break
                    else:
                        print(f"Tentativa {tentativa+1} falhou na página {pagina} (Inativo: {inativo}) com status {response.status_code}. Retentando em 5s...")
                        time.sleep(5)
                except Exception as e:
                    print(f"Tentativa {tentativa+1} falhou na página {pagina} (Inativo: {inativo}) com erro: {e}. Retentando em 5s...")
                    time.sleep(5)
                    
            if not sucesso_na_pagina:
                print(f"FALHA CRÍTICA: Não foi possível baixar a página {pagina} de clientes após 3 tentativas.")
                return None
                
    return todos_registros


def puxar_departamentos(empresa_config):
    pagina = 1
    tem_mais = True
    todos_registros = []
    url = "https://app.omie.com.br/api/v1/geral/departamentos/"
    
    while tem_mais:
        body = {
            "call": "ListarDepartamentos",
            "app_key": empresa_config["app_key"],
            "app_secret": empresa_config["app_secret"],
            "param": [{"pagina": pagina, "registros_por_pagina": 100}]
        }
        
        sucesso_na_pagina = False
        for tentativa in range(3):
            try:
                response = requests.post(url, json=body, timeout=30)
                if response.status_code == 200:
                    data = response.json()
                    if "departamentos" in data and len(data["departamentos"]) > 0:
                        for dept in data["departamentos"]:
                            registro = {
                                "codigo": dept.get("codigo"),
                                "empresa_nome": empresa_config["empresa"],
                                "empresa_cnpj": empresa_config["cnpj"],
                                "descricao": dept.get("descricao"),
                                "estrutura": dept.get("estrutura"),
                                "inativo": dept.get("inativo")
                            }
                            todos_registros.append(registro)
                        sucesso_na_pagina = True
                        pagina += 1
                        break
                    else:
                        tem_mais = False
                        sucesso_na_pagina = True
                        break
                else:
                    print(f"Tentativa {tentativa+1} falhou na página {pagina} com status {response.status_code}. Retentando em 5s...")
                    time.sleep(5)
            except Exception as e:
                print(f"Tentativa {tentativa+1} falhou na página {pagina} com erro: {e}. Retentando em 5s...")
                time.sleep(5)
                
        if not sucesso_na_pagina:
            print(f"FALHA CRÍTICA: Não foi possível baixar a página {pagina} de departamentos após 3 tentativas.")
            return None
            
    return todos_registros


def puxar_categorias(empresa_config):
    pagina = 1
    tem_mais = True
    todos_registros = []
    url = "https://app.omie.com.br/api/v1/geral/categorias/"
    
    while tem_mais:
        body = {
            "call": "ListarCategorias",
            "app_key": empresa_config["app_key"],
            "app_secret": empresa_config["app_secret"],
            "param": [{"pagina": pagina, "registros_por_pagina": 100}]
        }
        
        sucesso_na_pagina = False
        for tentativa in range(3):
            try:
                response = requests.post(url, json=body, timeout=30)
                if response.status_code == 200:
                    data = response.json()
                    if "categoria_cadastro" in data and len(data["categoria_cadastro"]) > 0:
                        for cat in data["categoria_cadastro"]:
                            registro = {
                                "codigo": cat.get("codigo"),
                                "empresa_nome": empresa_config["empresa"],
                                "empresa_cnpj": empresa_config["cnpj"],
                                "descricao": cat.get("descricao"),
                                "descricao_padrao": cat.get("descricao_padrao"),
                                "categoria_superior": cat.get("categoria_superior"),
                                "conta_despesa": cat.get("conta_despesa"),
                                "conta_receita": cat.get("conta_receita"),
                                "conta_inativa": cat.get("conta_inativa"),
                                "definida_pelo_usuario": cat.get("definida_pelo_usuario"),
                                "nao_exibir": cat.get("nao_exibir"),
                                "totalizadora": cat.get("totalizadora"),
                                "transferencia": cat.get("transferencia"),
                                "codigo_dre": cat.get("codigo_dre"),
                                "id_conta_contabil": cat.get("id_conta_contabil"),
                                "tag_conta_contabil": cat.get("tag_conta_contabil"),
                                "natureza": cat.get("natureza"),
                                "tipo_categoria": cat.get("tipo_categoria"),
                                "dados_dre": tratar_json(cat.get("dadosDRE")),
                                "codigo_valores_unidades": cat.get("codigo_valores_unidades", None),
                                "bandeiras": tratar_json(cat.get("bandeiras", None))
                            }
                            todos_registros.append(registro)
                        sucesso_na_pagina = True
                        pagina += 1
                        break
                    else:
                        tem_mais = False
                        sucesso_na_pagina = True
                        break
                else:
                    print(f"Tentativa {tentativa+1} falhou na página {pagina} com status {response.status_code}. Retentando em 5s...")
                    time.sleep(5)
            except Exception as e:
                print(f"Tentativa {tentativa+1} falhou na página {pagina} com erro: {e}. Retentando em 5s...")
                time.sleep(5)
                
        if not sucesso_na_pagina:
            print(f"FALHA CRÍTICA: Não foi possível baixar a página {pagina} de categorias após 3 tentativas.")
            return None
            
    return todos_registros


def rodar_rotina():
    print("Iniciando rotina de Cadastros Básicos (Clientes, Deptos, Categorias)...")
    
    headers_supabase = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal, resolution=merge-duplicates"
    }

    for empresa in EMPRESAS:
        print(f"\nExtraindo dados de: {empresa['empresa']}...")
        
        # 1. CLIENTES (Removido - Sincronizado isoladamente via sync_clientes.py)
        # 2. DEPARTAMENTOS (Removido - Sincronizado isoladamente via sync_departamentos.py)

        # 3. CATEGORIAS
        categorias = puxar_categorias(empresa)
        if categorias is None:
            print(f"⚠️ Pulo de segurança: Categorias da empresa {empresa['empresa']} não serão apagadas/inseridas.")
        elif categorias:
            try:
                requests.delete(f"{SUPABASE_URL}/rest/v1/categorias_omie", headers=headers_supabase, params={"empresa_cnpj": f"eq.{empresa['cnpj']}"})
                tamanho_lote = 500
                for i in range(0, len(categorias), tamanho_lote):
                    lote = categorias[i:i + tamanho_lote]
                    resp = requests.post(f"{SUPABASE_URL}/rest/v1/categorias_omie", json=lote, headers=headers_supabase)
                    if resp.status_code not in (200, 201):
                         print(f"❌ Erro na API do Supabase (Categorias): {resp.text}")
                print(f"✅ Inseridas {len(categorias)} Categorias para {empresa['empresa']}")
            except Exception as e:
                print(f"❌ Erro ao enviar Categorias da empresa {empresa['empresa']}: {e}")
            
    print("\nFIM DA ROTINA DE CADASTROS BÁSICOS!")

if __name__ == "__main__":
    rodar_rotina()
