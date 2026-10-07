import os
import requests
import time
import sys
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("ERRO: Variáveis de ambiente SUPABASE_URL ou SUPABASE_KEY não configuradas.")
    exit(1)

HEADERS_SUPABASE = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=minimal, resolution=merge-duplicates"  # sem apagar (extracao incompleta) vira upsert
}

from empresas import EMPRESAS as TODAS_EMPRESAS
from gravacao import empresa_fora, encerrar, extracao_completa, substituir_dados_empresa
import omie_api

def formatar_registro(dept, empresa_config):
    return {
        "codigo": dept.get("codigo"),
        "empresa_nome": empresa_config["empresa"],
        "empresa_cnpj": empresa_config["cnpj"],
        "descricao": dept.get("descricao"),
        "estrutura": dept.get("estrutura"),
        "inativo": dept.get("inativo")
    }

def tentar_pagina(url, empresa_config, pagina, tamanho, max_tentativas=4):
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
                return True, registros, total_paginas, omie_api.total_informado(data)
            else:
                tipo, espera = omie_api.classificar(response.status_code, response.text, tentativa)
                if tipo == omie_api.PERMANENTE:
                    raise omie_api.ErroPermanente(f"HTTP {response.status_code}: {response.text[:150]}")
                if tipo == omie_api.VAZIO:
                    return True, [], 1, None
                print(f"    Tentativa {tentativa+1} falhou na página {pagina} (tamanho {tamanho}) com status {response.status_code}. Retentando em {espera}s...")
                time.sleep(espera)
        except omie_api.ErroPermanente:
            raise
        except Exception as e:
            espera = omie_api.espera_transitoria(tentativa)
            print(f"    Tentativa {tentativa+1} falhou na página {pagina} (tamanho {tamanho}) com erro: {e}. Retentando em {espera}s...")
            time.sleep(espera)
    return False, [], 0, None

def zoom_progressivo(url, empresa_config, pagina_falha, tamanho_original):
    """Quando uma página falha, divide em lotes menores para isolar o registro corrompido e resgatar os bons."""
    registros_recuperados = []
    tamanho_zoom1 = 10
    fator = tamanho_original // tamanho_zoom1
    pag_inicio = (pagina_falha - 1) * fator + 1
    pag_fim = pagina_falha * fator
    
    print(f"  🔬 ZOOM NÍVEL 1: Tentando recuperar página {pagina_falha} como sub-páginas {pag_inicio}-{pag_fim} (de {tamanho_zoom1} registros)...")
    
    for sub_pag in range(pag_inicio, pag_fim + 1):
        sucesso, registros, _, _ = tentar_pagina(url, empresa_config, sub_pag, tamanho_zoom1, max_tentativas=3)
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
                ok, regs, _, _ = tentar_pagina(url, empresa_config, micro_pag, tamanho_zoom2, max_tentativas=2)
                if ok:
                    registros_recuperados.extend(regs)
                else:
                    print(f"      ❌ Micro-página {micro_pag}: departamento irrecuperável (defeito na Omie)")
    return registros_recuperados

def _puxar_departamentos_isolado(empresa_config):
    TAMANHO_PAGINA = 50
    pagina = 1
    tem_mais = True
    total_paginas_conhecido = 999999
    total_omie = None
    todos_registros_brutos = []
    url = "https://app.omie.com.br/api/v1/geral/departamentos/"
    
    while tem_mais:
        sucesso, registros_pagina, total_paginas, total_registros = tentar_pagina(url, empresa_config, pagina, TAMANHO_PAGINA)

        if sucesso:
            total_paginas_conhecido = total_paginas
            if total_registros is not None:
                total_omie = total_registros
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

    return todos_registros, total_omie

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
        
        resultado = puxar_departamentos_isolado(empresa)

        if resultado is None:
            empresa_fora("Departamentos", empresa, "falha na extracao do Omie")
            continue
        departamentos, total_omie = resultado

        if len(departamentos) == 0:
            print(f"   ℹ Nenhum departamento retornado pela API da Omie para a {empresa['empresa']}.")
            continue

        # do zero por empresa: departamento excluido no Omie sai do banco
        print(f"   ✓ {len(departamentos)} departamentos obtidos da Omie. Enviando ao Supabase...")
        completo = extracao_completa("Departamentos", empresa, len(departamentos), total_omie)
        substituir_dados_empresa(SUPABASE_URL.rstrip("/"), HEADERS_SUPABASE, "departamentos_omie", departamentos, empresa,
                                 "Departamentos", apagar_antes=completo)

    print("\n=== SINCRONIZAÇÃO CONCLUÍDA ===")
    encerrar("Departamentos")

def puxar_departamentos_isolado(empresa_config):
    """Extrai departamentos da empresa: (registros, total que o Omie informa).
    Devolve None se o Omie recusar de forma permanente (chave suspensa,
    bloqueio 425) - sem insistir."""
    try:
        return _puxar_departamentos_isolado(empresa_config)
    except omie_api.ErroPermanente as e:
        print(f"  ❌ Erro permanente do Omie, empresa interrompida sem repetir: {e}")
        return None


if __name__ == "__main__":
    if len(sys.argv) > 1:
        empresa_cli = sys.argv[1]
        main(empresa_cli)
    else:
        main()
