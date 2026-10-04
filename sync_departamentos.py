import os
import requests
import time
import sys
from supabase import create_client, Client
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("ERRO: Variáveis de ambiente SUPABASE_URL ou SUPABASE_KEY não configuradas.")
    exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

from empresas import EMPRESAS as TODAS_EMPRESAS
from gravacao import aviso, encerrar, falha

def formatar_registro(dept, empresa_config):
    return {
        "codigo": dept.get("codigo"),
        "empresa_nome": empresa_config["empresa"],
        "empresa_cnpj": empresa_config["cnpj"],
        "descricao": dept.get("descricao"),
        "estrutura": dept.get("estrutura"),
        "inativo": dept.get("inativo")
    }

def tentar_pagina(url, empresa_config, pagina, tamanho, max_tentativas=10):
    """Tenta baixar uma página específica da Omie com retries."""
    body = {
        "call": "ListarDepartamentos",
        "app_key": empresa_config["app_key"],
        "app_secret": empresa_config["app_secret"],
        "param": [{"pagina": pagina, "registros_por_pagina": tamanho}]
    }
    for tentativa in range(max_tentativas):
        try:
            response = requests.post(url, json=body, timeout=30)
            if response.status_code == 200:
                data = response.json()
                total_paginas = data.get("total_de_paginas", 1)
                registros = []
                if "departamentos" in data and len(data["departamentos"]) > 0:
                    registros = data["departamentos"]
                return True, registros, total_paginas
            else:
                print(f"    Tentativa {tentativa+1} falhou na página {pagina} (tamanho {tamanho}) com status {response.status_code}. Retentando em 5s...")
                time.sleep(5)
        except Exception as e:
            print(f"    Tentativa {tentativa+1} falhou na página {pagina} (tamanho {tamanho}) com erro: {e}. Retentando em 5s...")
            time.sleep(5)
    return False, [], 0

def zoom_progressivo(url, empresa_config, pagina_falha, tamanho_original):
    """Quando uma página falha, divide em lotes menores para isolar o registro corrompido e resgatar os bons."""
    registros_recuperados = []
    tamanho_zoom1 = 10
    fator = tamanho_original // tamanho_zoom1
    pag_inicio = (pagina_falha - 1) * fator + 1
    pag_fim = pagina_falha * fator
    
    print(f"  🔬 ZOOM NÍVEL 1: Tentando recuperar página {pagina_falha} como sub-páginas {pag_inicio}-{pag_fim} (de {tamanho_zoom1} registros)...")
    
    for sub_pag in range(pag_inicio, pag_fim + 1):
        sucesso, registros, _ = tentar_pagina(url, empresa_config, sub_pag, tamanho_zoom1, max_tentativas=5)
        if sucesso:
            registros_recuperados.extend(registros)
            print(f"    ✅ Sub-página {sub_pag}: {len(registros)} departamentos recuperados")
        else:
            tamanho_zoom2 = 1
            fator2 = tamanho_zoom1 // tamanho_zoom2
            micro_inicio = (sub_pag - 1) * fator2 + 1
            micro_fim = sub_pag * fator2
            
            print(f"    🔬 ZOOM NÍVEL 2: Tentando sub-página {sub_pag} como micro-páginas {micro_inicio}-{micro_fim} (1 dept cada)...")
            
            for micro_pag in range(micro_inicio, micro_fim + 1):
                ok, regs, _ = tentar_pagina(url, empresa_config, micro_pag, tamanho_zoom2, max_tentativas=3)
                if ok:
                    registros_recuperados.extend(regs)
                else:
                    print(f"      ❌ Micro-página {micro_pag}: departamento irrecuperável (defeito na Omie)")
    return registros_recuperados

def puxar_departamentos_isolado(empresa_config):
    TAMANHO_PAGINA = 50
    pagina = 1
    tem_mais = True
    total_paginas_conhecido = 999999
    todos_registros_brutos = []
    url = "https://app.omie.com.br/api/v1/geral/departamentos/"
    
    while tem_mais:
        sucesso, registros_pagina, total_paginas = tentar_pagina(url, empresa_config, pagina, TAMANHO_PAGINA)
        
        if sucesso:
            total_paginas_conhecido = total_paginas
            todos_registros_brutos.extend(registros_pagina)
            
            if pagina >= total_paginas_conhecido:
                tem_mais = False
            else:
                pagina += 1
        else:
            if pagina >= total_paginas_conhecido:
                print(f"  AVISO: Falha na página {pagina}, mas já atingimos o limite ({total_paginas_conhecido}). Encerrando.")
                tem_mais = False
            else:
                print(f"  ⚠️ Página {pagina} falhou! Ativando Zoom Progressivo...")
                registros_zoom = zoom_progressivo(url, empresa_config, pagina, TAMANHO_PAGINA)
                todos_registros_brutos.extend(registros_zoom)
                print(f"  🔬 Zoom recuperou {len(registros_zoom)} de {TAMANHO_PAGINA} departamentos da página {pagina}")
                if len(registros_zoom) == 0 and total_paginas_conhecido == 999999:
                    print("  🛑 Nenhuma página foi carregada com sucesso e o zoom retornou 0 registros. Interrompendo loop para evitar repetição infinita.")
                    tem_mais = False
                else:
                    pagina += 1
                
    todos_registros = []
    chaves_processadas = set()
    for dept in todos_registros_brutos:
        pk = dept.get("codigo")
        if pk in chaves_processadas:
            continue
        chaves_processadas.add(pk)
        todos_registros.append(formatar_registro(dept, empresa_config))
        
    return todos_registros

def main(empresa_alvo=None):
    print("=== INICIANDO SINCRONIZAÇÃO DE DEPARTAMENTOS ===")
    
    empresas_para_rodar = TODAS_EMPRESAS
    if empresa_alvo:
        empresas_para_rodar = [e for e in TODAS_EMPRESAS if e["empresa"] == empresa_alvo]
        if not empresas_para_rodar:
            print(f"ERRO: Empresa '{empresa_alvo}' não encontrada na lista.")
            return

    for empresa in empresas_para_rodar:
        print(f"\nSincronizando departamentos da empresa: {empresa['empresa']}")
        
        departamentos = puxar_departamentos_isolado(empresa)
        
        if departamentos is None:
            aviso(f"Departamentos / {empresa['empresa']}: falha na extracao do Omie. Dados antigos preservados.")
            continue
            
        if len(departamentos) == 0:
            print(f"   ℹ Nenhum departamento retornado pela API da Omie para a {empresa['empresa']}.")
            continue
            
        if departamentos:
            print(f"   ✓ {len(departamentos)} departamentos obtidos da Omie. Enviando ao Supabase (UPSERT)...")
            
            try:
                headers_supabase = {
                    "apikey": SUPABASE_KEY,
                    "Authorization": f"Bearer {SUPABASE_KEY}",
                    "Content-Type": "application/json",
                    "Prefer": "return=minimal, resolution=merge-duplicates" # UPSERT
                }
                
                # Insere em lotes
                gravados = 0
                for i in range(0, len(departamentos), 500):
                    lote = departamentos[i:i+500]
                    for tentativa in range(10):
                        try:
                            resp = requests.post(f"{SUPABASE_URL}/rest/v1/departamentos_omie", json=lote, headers=headers_supabase, timeout=60)
                            if resp.status_code not in (200, 201):
                                raise Exception(f"Erro na API do Supabase: {resp.text}")
                            gravados += len(lote)
                            break
                        except Exception as e:
                            print(f"     [!] Erro ao salvar lote {i} a {i+len(lote)}: {e}. Retentando ({tentativa+1}/10)...")
                            time.sleep(5)
                    else:
                        falha(f"Departamentos / {empresa['empresa']}: lote {i} a {i+len(lote)} nao gravado apos 10 tentativas")
                if gravados == len(departamentos):
                    print(f"   ✅ Departamentos sincronizados com sucesso!")
                else:
                    print(f"   ⚠️ Apenas {gravados} de {len(departamentos)} departamentos gravados para {empresa['empresa']}")
            except Exception as e:
                falha(f"Departamentos / {empresa['empresa']}: erro de rede ao se comunicar com o Supabase ({e})")

    print("\n=== SINCRONIZAÇÃO CONCLUÍDA ===")
    encerrar("Departamentos")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        empresa_cli = sys.argv[1]
        main(empresa_cli)
    else:
        main()
