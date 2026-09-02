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

def formatar_registro(cat, empresa_config):
    return {
        "codigo": str(cat.get("codigo", "")),
        "empresa_nome": empresa_config["empresa"],
        "empresa_cnpj": empresa_config["cnpj"],
        "descricao": cat.get("descricao")
    }

def tentar_pagina(url, empresa_config, pagina, tamanho, max_tentativas=10):
    body = {
        "call": "ListarCategorias",
        "app_key": empresa_config["app_key"],
        "app_secret": empresa_config["app_secret"],
        "param": [{"pagina": pagina, "registros_por_pagina": tamanho}]
    }
    for tentativa in range(max_tentativas):
        try:
            response = requests.post(url, json=body, timeout=30)
            
            # BLOQUEIO DE CHAVE INVÁLIDA
            if "chave de acesso est" in response.text or "aplicativo est" in response.text or response.status_code == 500:
                print(f"    ❌ ERRO CRÍTICO DA OMIE: Chave da empresa {empresa_config['empresa']} inválida ou suspensa. Pulando empresa.")
                return False, [], 0, True # O 4º parametro avisa que é bloqueio definitivo
                
            if response.status_code == 200:
                data = response.json()
                total_paginas = data.get("total_de_paginas", 1)
                registros = []
                if "categoria_cadastro" in data and len(data["categoria_cadastro"]) > 0:
                    registros = data["categoria_cadastro"]
                return True, registros, total_paginas, False
            else:
                print(f"    Tentativa {tentativa+1} falhou na página {pagina} (tamanho {tamanho}) com status {response.status_code}. Retentando em 5s...")
                time.sleep(5)
        except Exception as e:
            print(f"    Tentativa {tentativa+1} falhou na página {pagina} (tamanho {tamanho}) com erro: {e}. Retentando em 5s...")
            time.sleep(5)
    return False, [], 0, False

def zoom_progressivo(url, empresa_config, pagina_falha, tamanho_original):
    registros_recuperados = []
    tamanho_zoom1 = 10
    fator = tamanho_original // tamanho_zoom1
    pag_inicio = (pagina_falha - 1) * fator + 1
    pag_fim = pagina_falha * fator
    
    print(f"  🔬 ZOOM NÍVEL 1: Tentando recuperar página {pagina_falha} como sub-páginas {pag_inicio}-{pag_fim} (de {tamanho_zoom1} registros)...")
    
    for sub_pag in range(pag_inicio, pag_fim + 1):
        sucesso, registros, _, bloqueio = tentar_pagina(url, empresa_config, sub_pag, tamanho_zoom1, max_tentativas=5)
        if bloqueio:
            break
        if sucesso:
            registros_recuperados.extend(registros)
            print(f"    ✅ Sub-página {sub_pag}: {len(registros)} categorias recuperadas")
        else:
            tamanho_zoom2 = 1
            fator2 = tamanho_zoom1 // tamanho_zoom2
            micro_inicio = (sub_pag - 1) * fator2 + 1
            micro_fim = sub_pag * fator2
            
            print(f"    🔬 ZOOM NÍVEL 2: Tentando sub-página {sub_pag} como micro-páginas {micro_inicio}-{micro_fim} (1 cat cada)...")
            
            for micro_pag in range(micro_inicio, micro_fim + 1):
                ok, regs, _, _ = tentar_pagina(url, empresa_config, micro_pag, tamanho_zoom2, max_tentativas=3)
                if ok:
                    registros_recuperados.extend(regs)
                else:
                    print(f"      ❌ Micro-página {micro_pag}: categoria irrecuperável (defeito na Omie)")
    return registros_recuperados

def puxar_categorias_isolado(empresa_config):
    TAMANHO_PAGINA = 50
    pagina = 1
    tem_mais = True
    total_paginas_conhecido = 999999
    todos_registros_brutos = []
    url = "https://app.omie.com.br/api/v1/geral/categorias/"
    
    while tem_mais:
        sucesso, registros_pagina, total_paginas, bloqueio_definitivo = tentar_pagina(url, empresa_config, pagina, TAMANHO_PAGINA)
        
        if bloqueio_definitivo:
            return [] # Corta imediatamente e devolve nada
            
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
                print(f"  🔬 Zoom recuperou {len(registros_zoom)} de {TAMANHO_PAGINA} categorias da página {pagina}")
                pagina += 1
                
    todos_registros = []
    chaves_processadas = set()
    for cat in todos_registros_brutos:
        pk = cat.get("codigo")
        if pk in chaves_processadas:
            continue
        chaves_processadas.add(pk)
        todos_registros.append(formatar_registro(cat, empresa_config))
        
    return todos_registros

def deletar_categorias_empresa(empresa_cnpj):
    try:
        res = supabase.table("categorias_omie").delete().eq("empresa_cnpj", empresa_cnpj).execute()
        return True
    except Exception as e:
        print(f"  ❌ Erro ao deletar categorias: {e}")
        return False

def rodar_rotina_categorias():
    print("Iniciando rotina de Categorias (Multi-Tenant)...")
    for emp in TODAS_EMPRESAS:
        print(f"\\n--- Extraindo de {emp['empresa']} ---")
        try:
            regs = puxar_categorias_isolado(emp)
            if regs:
                print(f"  Total resgatado: {len(regs)}")
                deletar_categorias_empresa(emp["cnpj"])
                
                LOTE = 500
                for i in range(0, len(regs), LOTE):
                    lote_atual = regs[i:i+LOTE]
                    try:
                        res = supabase.table("categorias_omie").upsert(lote_atual).execute()
                        print(f"  Lote de {len(lote_atual)} inserido no banco.")
                    except Exception as err_insert:
                        print(f"  ❌ Erro ao inserir lote: {err_insert}")
            else:
                print("  Nenhum registro para subir.")
        except Exception as err:
            print(f"  ❌ Erro geral para a empresa {emp['empresa']}: {err}")
    print("\\n=== Rotina Finalizada ===")

if __name__ == "__main__":
    rodar_rotina_categorias()
