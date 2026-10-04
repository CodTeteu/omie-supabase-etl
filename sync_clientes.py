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

def tentar_pagina(url, empresa_config, pagina, tamanho, filtros_extra=None, max_tentativas=10):
    """Tenta baixar uma página específica da Omie com retries."""
    param = {"pagina": pagina, "registros_por_pagina": tamanho, "apenas_importado_api": "N"}
    if filtros_extra:
        param.update(filtros_extra)
    
    body = {
        "call": "ListarClientes",
        "app_key": empresa_config["app_key"],
        "app_secret": empresa_config["app_secret"],
        "param": [param]
    }
    for tentativa in range(max_tentativas):
        try:
            response = requests.post(url, json=body, timeout=30)
            if response.status_code == 200:
                data = response.json()
                total_paginas = data.get("total_de_paginas", 1)
                registros = []
                if "clientes_cadastro" in data and len(data["clientes_cadastro"]) > 0:
                    registros = data["clientes_cadastro"]
                return True, registros, total_paginas, False
            else:
                if "chave de acesso est" in response.text or "aplicativo est" in response.text:
                    print(f"    ❌ ERRO CRÍTICO DA OMIE: Chave da empresa {empresa_config['empresa']} inválida ou sem permissão para listar clientes.")
                    return False, [], 0, True # Retorna 4º elemento para indicar bloqueio definitivo
                elif "ERROR: Nenhum registro encontrado" in response.text or "registros para a p" in response.text:
                    # A Omie as vezes devolve 500 quando não tem nenhum registro. Assumimos sucesso com 0 resultados.
                    return True, [], 1, False
                
                print(f"    Tentativa {tentativa+1} falhou na página {pagina} (tamanho {tamanho}) com status {response.status_code}. Motivo: {response.text}")
                
                # Se for bloqueio de redundância ou API bloqueada (425), devemos esperar MAIS TEMPO
                if "REDUNDANT" in response.text or "consumo indevido" in response.text or response.status_code == 425:
                    print("      ⏳ Pausa forçada de 60s por Rate Limiting da Omie...")
                    time.sleep(60)
                else:
                    time.sleep(5)
        except Exception as e:
            wait_time = min(5 * (2 ** tentativa), 60) # Backoff: 5, 10, 20, 40, 60s
            print(f"    Tentativa {tentativa+1} falhou na página {pagina} (tamanho {tamanho}) com erro: {e}. Retentando em {wait_time}s...")
            time.sleep(wait_time)
    return False, [], 0, False

def zoom_progressivo(url, empresa_config, pagina_falha, tamanho_original, filtros_extra=None):
    """Quando uma página falha, divide em lotes menores para isolar o registro corrompido e resgatar os bons."""
    registros_recuperados = []
    tamanho_zoom1 = 10
    fator = tamanho_original // tamanho_zoom1
    pag_inicio = (pagina_falha - 1) * fator + 1
    pag_fim = pagina_falha * fator
    
    print(f"  🔬 ZOOM NÍVEL 1: Tentando recuperar página {pagina_falha} como sub-páginas {pag_inicio}-{pag_fim} (de {tamanho_zoom1} registros)...")
    
    for sub_pag in range(pag_inicio, pag_fim + 1):
        sucesso, registros, _, bloqueio = tentar_pagina(url, empresa_config, sub_pag, tamanho_zoom1, filtros_extra, max_tentativas=5)
        if sucesso:
            registros_recuperados.extend(registros)
            print(f"    ✅ Sub-página {sub_pag}: {len(registros)} clientes recuperados")
        else:
            tamanho_zoom2 = 1
            fator2 = tamanho_zoom1 // tamanho_zoom2
            micro_inicio = (sub_pag - 1) * fator2 + 1
            micro_fim = sub_pag * fator2
            
            print(f"    🔬 ZOOM NÍVEL 2: Tentando sub-página {sub_pag} como micro-páginas {micro_inicio}-{micro_fim} (1 cliente cada)...")
            
            for micro_pag in range(micro_inicio, micro_fim + 1):
                ok, regs, _, bloq = tentar_pagina(url, empresa_config, micro_pag, tamanho_zoom2, filtros_extra, max_tentativas=3)
                if ok:
                    registros_recuperados.extend(regs)
                else:
                    print(f"      ❌ Micro-página {micro_pag}: cliente irrecuperável (defeito na Omie)")
    return registros_recuperados

def formatar_registro(cliente, empresa_config):
    return {
        "codigo_cliente_omie": cliente.get("codigo_cliente_omie"),
        "empresa_nome": empresa_config["empresa"],
        "empresa_cnpj": empresa_config["cnpj"],
        "cnpj_cpf": cliente.get("cnpj_cpf"),
        "razao_social": cliente.get("razao_social"),
        "nome_fantasia": cliente.get("nome_fantasia")
    }

def puxar_clientes(empresa_config):
    TAMANHO_PAGINA = 50
    todos_registros_brutos = []
    url = "https://app.omie.com.br/api/v1/geral/clientes/"
    
    for inativo in ["N", "S"]:
        print(f"    > Buscando Clientes Inativo='{inativo}'...")
        pagina = 1
        tem_mais = True
        total_paginas_conhecido = 999999
        filtros_extra = {"clientesFiltro": {"inativo": inativo}}
        
        while tem_mais:
            sucesso, registros_pagina, total_paginas, bloqueio_definitivo = tentar_pagina(url, empresa_config, pagina, TAMANHO_PAGINA, filtros_extra)
            
            if bloqueio_definitivo:
                return [] # Interrompe a busca desta empresa imediatamente
                
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
                    registros_zoom = zoom_progressivo(url, empresa_config, pagina, TAMANHO_PAGINA, filtros_extra)
                    todos_registros_brutos.extend(registros_zoom)
                    print(f"  🔬 Zoom recuperou {len(registros_zoom)} de {TAMANHO_PAGINA} clientes da página {pagina}")
                    pagina += 1
                
    todos_registros = []
    chaves_processadas = set()
    for cliente in todos_registros_brutos:
        pk = cliente.get("codigo_cliente_omie")
        if pk in chaves_processadas:
            continue
        chaves_processadas.add(pk)
        todos_registros.append(formatar_registro(cliente, empresa_config))
        
    return todos_registros


def run_sync_clientes(empresa_alvo=None):
    print("=== INICIANDO SINCRONIZAÇÃO DE CLIENTES ===")
    
    empresas_para_rodar = TODAS_EMPRESAS
    if empresa_alvo:
        empresas_para_rodar = [e for e in TODAS_EMPRESAS if e["empresa"] == empresa_alvo]
        if not empresas_para_rodar:
            print(f"ERRO: Empresa '{empresa_alvo}' não encontrada na lista.")
            return

    for empresa in empresas_para_rodar:
        print(f"\nSincronizando clientes da empresa: {empresa['empresa']}")
        clientes = puxar_clientes(empresa)
        
        if clientes is None:
            aviso(f"Clientes / {empresa['empresa']}: falha na extracao do Omie. Dados antigos preservados.")
            continue
            
        if clientes:
            print(f"   ✓ {len(clientes)} clientes obtidos da Omie. Enviando ao Supabase...")
            gravados = 0
            for i in range(0, len(clientes), 100):
                lote = clientes[i:i+100]
                for tentativa in range(5):
                    try:
                        supabase.table('clientes_grupo').upsert(
                            lote, on_conflict="codigo_cliente_omie, empresa_cnpj"
                        ).execute()
                        gravados += len(lote)
                        break
                    except Exception as e:
                        print(f"     [!] Erro ao salvar lote {i} a {i+len(lote)}: {e}. Retentando ({tentativa+1}/5)...")
                        time.sleep(5)
                else:
                    falha(f"Clientes / {empresa['empresa']}: lote {i} a {i+len(lote)} nao gravado apos 5 tentativas")
            if gravados == len(clientes):
                print(f"   ✓ Clientes da {empresa['empresa']} sincronizados com sucesso!")
            else:
                print(f"   ⚠️ Apenas {gravados} de {len(clientes)} clientes gravados para {empresa['empresa']}")
        else:
            print(f"   [!] Nenhum cliente encontrado na Omie para {empresa['empresa']}.")
            
    print("\n=== SINCRONIZAÇÃO CONCLUÍDA ===")
    encerrar("Clientes")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        empresa_cli = sys.argv[1]
        run_sync_clientes(empresa_cli)
    else:
        run_sync_clientes()
