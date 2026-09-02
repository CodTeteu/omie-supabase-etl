import os
import requests
import json
import time
from datetime import datetime, timedelta

# Configurações do Supabase
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("ERRO: Variáveis de ambiente SUPABASE_URL e SUPABASE_KEY não configuradas.")
    exit(1)

SUPABASE_URL = SUPABASE_URL.rstrip('/')

# Lista de Empresas
from empresas import EMPRESAS

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

def formatar_registro(conta, empresa_config):
    """Transforma um registro bruto da Omie em formato Supabase."""
    return {
        "empresa_cnpj": empresa_config["cnpj"],
        "empresa_nome": empresa_config["empresa"],
        "codigo_lancamento_omie": conta.get("codigo_lancamento_omie"),
        "bandeira_id": conta.get("bandeira_id", 0),
        "codigo_lancamento_integracao": conta.get("codigo_lancamento_integracao"),
        "codigo_cliente_fornecedor": conta.get("codigo_cliente_fornecedor"),
        "data_emissao": converter_data(conta.get("data_emissao")),
        "data_vencimento": converter_data(conta.get("data_vencimento")),
        "data_previsao": converter_data(conta.get("data_previsao")),
        "data_registro": converter_data(conta.get("data_registro")),
        "data_entrada": converter_data(conta.get("data_entrada")),
        "valor_documento": conta.get("valor_documento"),
        "numero_documento": conta.get("numero_documento"),
        "numero_parcela": conta.get("numero_parcela"),
        "numero_pedido": conta.get("numero_pedido"),
        "chave_nfe": conta.get("chave_nfe"),
        "codigo_barras_ficha_compensacao": conta.get("codigo_barras_ficha_compensacao"),
        "codigo_categoria": conta.get("codigo_categoria"),
        "codigo_projeto": conta.get("codigo_projeto"),
        "codigo_vendedor": conta.get("codigo_vendedor"),
        "id_origem": conta.get("id_origem"),
        "id_conta_corrente": conta.get("id_conta_corrente"),
        "status_titulo": conta.get("status_titulo"),
        "codigo_tipo_documento": conta.get("codigo_tipo_documento"),
        "operacao": conta.get("operacao"),
        "situacao": conta.get("situacao"),
        "retem_pis": conta.get("retem_pis"),
        "retem_cofins": conta.get("retem_cofins"),
        "retem_csll": conta.get("retem_csll"),
        "retem_ir": conta.get("retem_ir"),
        "retem_iss": conta.get("retem_iss"),
        "retem_inss": conta.get("retem_inss"),
        "baixa_bloqueada": conta.get("baixa_bloqueada"),
        "bloqueado": conta.get("bloqueado"),
        "last_update": None,
        "codigo_cmc7_cheque": conta.get("codigo_cmc7_cheque"),
        "numero_documento_fiscal": conta.get("numero_documento_fiscal"),
        "nsu": conta.get("nsu"),
        "boleto_gerado": conta.get("boleto_gerado"),
        "pix_gerado": conta.get("pix_gerado"),
        "valor_cofins": conta.get("valor_cofins"),
        "valor_csll": conta.get("valor_csll"),
        "valor_ir": conta.get("valor_ir"),
        "valor_inss": conta.get("valor_inss"),
        "valor_pis": conta.get("valor_pis"),
        "valor_iss": conta.get("valor_iss"),
        "distribuicao": tratar_json(conta.get("distribuicao")),
        "info": tratar_json(conta.get("info")),
        "categorias": tratar_json(conta.get("categorias"))
    }

# ---------------------------------------------------------------------------
# ZOOM PROGRESSIVO - Recuperação registro a registro
# ---------------------------------------------------------------------------

def tentar_pagina(url, empresa_config, pagina, tamanho, filtros_extra=None, max_tentativas=10):
    """Tenta baixar uma página específica da Omie com retries."""
    param = {"pagina": pagina, "registros_por_pagina": tamanho, "apenas_importado_api": "N"}
    if filtros_extra:
        param.update(filtros_extra)
    
    body = {
        "call": "ListarContasPagar",
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
                if "conta_pagar_cadastro" in data and len(data["conta_pagar_cadastro"]) > 0:
                    registros = data["conta_pagar_cadastro"]
                return True, registros, total_paginas
            else:
                print(f"    Tentativa {tentativa+1} falhou na página {pagina} (tamanho {tamanho}) com status {response.status_code}. Retentando em 5s...")
                time.sleep(5)
        except Exception as e:
            print(f"    Tentativa {tentativa+1} falhou na página {pagina} (tamanho {tamanho}) com erro: {e}. Retentando em 5s...")
            time.sleep(5)
    return False, [], 0

def zoom_progressivo(url, empresa_config, pagina_falha, tamanho_original, filtros_extra=None):
    """
    Quando uma página falha, "dá zoom" com tamanhos menores para recuperar registros.
    Página 5 de 50 → tenta páginas 21-25 de 10 → se falhar, tenta de 1 em 1.
    """
    registros_recuperados = []
    
    # ZOOM NÍVEL 1: Divide a página em sub-páginas de 10
    tamanho_zoom1 = 10
    fator = tamanho_original // tamanho_zoom1
    pag_inicio = (pagina_falha - 1) * fator + 1
    pag_fim = pagina_falha * fator
    
    print(f"  🔬 ZOOM NÍVEL 1: Tentando recuperar página {pagina_falha} como sub-páginas {pag_inicio}-{pag_fim} (de {tamanho_zoom1} registros cada)...")
    
    for sub_pag in range(pag_inicio, pag_fim + 1):
        sucesso, registros, _ = tentar_pagina(url, empresa_config, sub_pag, tamanho_zoom1, filtros_extra, max_tentativas=5)
        if sucesso:
            registros_recuperados.extend(registros)
            print(f"    ✅ Sub-página {sub_pag}: {len(registros)} registros recuperados")
        else:
            # ZOOM NÍVEL 2: Divide a sub-página em micro-páginas de 1
            tamanho_zoom2 = 1
            fator2 = tamanho_zoom1 // tamanho_zoom2
            micro_inicio = (sub_pag - 1) * fator2 + 1
            micro_fim = sub_pag * fator2
            
            print(f"    🔬 ZOOM NÍVEL 2: Tentando sub-página {sub_pag} como micro-páginas {micro_inicio}-{micro_fim} (1 registro cada)...")
            
            for micro_pag in range(micro_inicio, micro_fim + 1):
                ok, regs, _ = tentar_pagina(url, empresa_config, micro_pag, tamanho_zoom2, filtros_extra, max_tentativas=3)
                if ok:
                    registros_recuperados.extend(regs)
                else:
                    print(f"      ❌ Micro-página {micro_pag}: registro irrecuperável (defeito interno da Omie)")
    
    return registros_recuperados

# ---------------------------------------------------------------------------
# EXTRAÇÃO INCREMENTAL COM ZOOM
# ---------------------------------------------------------------------------

def puxar_contas_pagar_incrementais(empresa_config, data_corte):
    TAMANHO_PAGINA = 50
    todos_registros_brutos = []
    url = "https://app.omie.com.br/api/v1/financas/contapagar/"
    
    filtros = [
        {"apenas_inclusao": "S", "apenas_alteracao": "N", "nome_filtro": "Inclusões"},
        {"apenas_inclusao": "N", "apenas_alteracao": "S", "nome_filtro": "Alterações"}
    ]

    for f in filtros:
        print(f"  > Buscando {f['nome_filtro']} a partir de {data_corte}...")
        pagina = 1
        tem_mais = True
        total_paginas_conhecido = 999999
        
        filtros_extra = {
            "filtrar_por_data_de": data_corte,
            "filtrar_apenas_inclusao": f["apenas_inclusao"],
            "filtrar_apenas_alteracao": f["apenas_alteracao"]
        }
        
        while tem_mais:
            sucesso, registros_pagina, total_paginas = tentar_pagina(url, empresa_config, pagina, TAMANHO_PAGINA, filtros_extra)
            
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
                    # ZOOM PROGRESSIVO
                    print(f"  ⚠️ Página {pagina} falhou! Ativando Zoom Progressivo...")
                    registros_zoom = zoom_progressivo(url, empresa_config, pagina, TAMANHO_PAGINA, filtros_extra)
                    todos_registros_brutos.extend(registros_zoom)
                    print(f"  🔬 Zoom recuperou {len(registros_zoom)} de {TAMANHO_PAGINA} registros da página {pagina}")
                    pagina += 1

    # Formatando e limpando duplicatas
    todos_registros = []
    chaves_processadas = set()

    for conta in todos_registros_brutos:
        pk = (conta.get("codigo_lancamento_omie"), conta.get("bandeira_id", 0))
        if pk in chaves_processadas:
            continue
        chaves_processadas.add(pk)
        todos_registros.append(formatar_registro(conta, empresa_config))
            
    return todos_registros

def rodar_rotina_cp_incremental():
    data_corte = (datetime.now() - timedelta(days=3)).strftime('%d/%m/%Y')
    
    print(f"Iniciando rotina INCREMENTAL de Contas a Pagar (A partir de: {data_corte})")
    print(f"COM Zoom Progressivo + UPSERT Anti-Perda\n")
    
    headers_supabase = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal, resolution=merge-duplicates"
    }

    total_processado = 0

    for empresa in EMPRESAS:
        print(f"\nVerificando Deltas de: {empresa['empresa']}...")
        contas_pagar = puxar_contas_pagar_incrementais(empresa, data_corte)
        
        if contas_pagar is None:
            print(f"⚠️ ERRO DETECTADO NA EXTRAÇÃO DA {empresa['empresa']}.")
            continue 
            
        if contas_pagar:
            try:
                tamanho_lote = 500
                for i in range(0, len(contas_pagar), tamanho_lote):
                    lote = contas_pagar[i:i + tamanho_lote]
                    for tentativa in range(5):
                        resp = requests.post(f"{SUPABASE_URL}/rest/v1/contas_pagar", json=lote, headers=headers_supabase)
                        if resp.status_code in (200, 201):
                            break
                        else:
                            print(f"  ❌ Erro Supabase: {resp.text}. Tentativa {tentativa+1}/5...")
                            time.sleep(3)
                
                print(f"✅ UPSERT: {len(contas_pagar)} registros novos/alterados de {empresa['empresa']}")
                total_processado += len(contas_pagar)
            except Exception as e:
                print(f"❌ Erro ao enviar Contas a Pagar da empresa {empresa['empresa']}: {e}")
        else:
            print(f"  Nenhum delta encontrado para {empresa['empresa']}.")

    print(f"\nFIM DA ROTINA INCREMENTAL! Total processado: {total_processado} registros")

if __name__ == "__main__":
    rodar_rotina_cp_incremental()
