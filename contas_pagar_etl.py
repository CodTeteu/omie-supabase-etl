import os
import sys
import requests
import json
import time

# Configurações do Supabase
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("ERRO: Variáveis de ambiente SUPABASE_URL e SUPABASE_KEY não configuradas.")
    exit(1)

SUPABASE_URL = SUPABASE_URL.rstrip('/')

# Lista de Empresas
from empresas import EMPRESAS
from gravacao import aviso, encerrar, falha

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
        "valor_juros": conta.get("valor_juros"),
        "valor_multa": conta.get("valor_multa"),
        "valor_desconto": conta.get("valor_desconto"),
        "distribuicao": tratar_json(conta.get("distribuicao")),
        "info": tratar_json(conta.get("info")),
        "categorias": tratar_json(conta.get("categorias")),
        "resumo": tratar_json(conta.get("resumo")),
        "json_bruto": tratar_json(conta)
    }

# ---------------------------------------------------------------------------
# CAMADA 1: ZOOM PROGRESSIVO - Recuperação registro a registro
# ---------------------------------------------------------------------------

def tentar_pagina(url, empresa_config, pagina, tamanho, max_tentativas=10):
    """Tenta baixar uma página específica da Omie com retries."""
    body = {
        "call": "ListarContasPagar",
        "app_key": empresa_config["app_key"],
        "app_secret": empresa_config["app_secret"],
        "param": [{"pagina": pagina, "registros_por_pagina": tamanho, "apenas_importado_api": "N"}]
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

def zoom_progressivo(url, empresa_config, pagina_falha, tamanho_original):
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
        sucesso, registros, _ = tentar_pagina(url, empresa_config, sub_pag, tamanho_zoom1, max_tentativas=5)
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
                ok, regs, _ = tentar_pagina(url, empresa_config, micro_pag, tamanho_zoom2, max_tentativas=3)
                if ok:
                    registros_recuperados.extend(regs)
                else:
                    print(f"      ❌ Micro-página {micro_pag}: registro irrecuperável (defeito interno da Omie)")
    
    return registros_recuperados

def puxar_contas_pagar(empresa_config):
    """Extrai todas as contas a pagar da Omie com Zoom Progressivo."""
    TAMANHO_PAGINA = 50
    pagina = 1
    tem_mais = True
    total_paginas_conhecido = 999999
    todos_registros = []
    url = "https://app.omie.com.br/api/v1/financas/contapagar/"
    
    while tem_mais:
        sucesso, registros_brutos, total_paginas = tentar_pagina(url, empresa_config, pagina, TAMANHO_PAGINA)
        
        if sucesso:
            total_paginas_conhecido = total_paginas
            for conta in registros_brutos:
                todos_registros.append(formatar_registro(conta, empresa_config))
            
            if pagina >= total_paginas_conhecido:
                tem_mais = False
            else:
                pagina += 1
        else:
            # Página falhou após todas as tentativas normais
            if pagina >= total_paginas_conhecido:
                print(f"  AVISO: Falha na página {pagina}, mas já atingimos o limite ({total_paginas_conhecido}). Encerrando.")
                tem_mais = False
            else:
                # ZOOM PROGRESSIVO: Tenta recuperar registro a registro
                print(f"  ⚠️ Página {pagina} falhou! Ativando Zoom Progressivo...")
                registros_zoom = zoom_progressivo(url, empresa_config, pagina, TAMANHO_PAGINA)
                for conta in registros_zoom:
                    todos_registros.append(formatar_registro(conta, empresa_config))
                print(f"  🔬 Zoom recuperou {len(registros_zoom)} de {TAMANHO_PAGINA} registros da página {pagina}")
                
                if len(registros_zoom) == 0 and total_paginas_conhecido == 999999:
                    print("  🛑 Nenhuma página foi carregada com sucesso e o zoom retornou 0 registros. Interrompendo loop para evitar repetição infinita.")
                    tem_mais = False
                else:
                    pagina += 1
    
    return todos_registros

# ---------------------------------------------------------------------------
# CAMADA 3: UPSERT ANTI-PERDA (sem DELETE)
# ---------------------------------------------------------------------------

def enviar_para_supabase(registros, empresa_nome):
    """Envia registros para o Supabase usando UPSERT (nunca deleta dados antigos)."""
    headers_supabase = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal, resolution=merge-duplicates"
    }
    
    tamanho_lote = 500
    total_enviado = 0
    
    for i in range(0, len(registros), tamanho_lote):
        lote = registros[i:i + tamanho_lote]
        for tentativa in range(5):
            try:
                resp = requests.post(f"{SUPABASE_URL}/rest/v1/contas_pagar", json=lote, headers=headers_supabase, timeout=60)
                if resp.status_code in (200, 201):
                    total_enviado += len(lote)
                    break
                else:
                    print(f"  ❌ Erro Supabase (lote {i}-{i+len(lote)}): {resp.text}. Tentativa {tentativa+1}/5...")
                    time.sleep(3)
            except Exception as e:
                print(f"  ❌ Exceção Supabase (lote {i}-{i+len(lote)}): {e}. Tentativa {tentativa+1}/5...")
                time.sleep(3)
        else:
            falha(f"Contas a Pagar / {empresa_nome}: lote {i}-{i+len(lote)} nao gravado apos 5 tentativas")
    
    return total_enviado

# ---------------------------------------------------------------------------
# CAMADA 2: SUPORTE A PARALELISMO (aceita nome da empresa como argumento)
# ---------------------------------------------------------------------------

def rodar_rotina_cp():
    # Se recebeu o nome de uma empresa como argumento, roda só ela
    empresa_filtro = None
    if len(sys.argv) > 1:
        empresa_filtro = sys.argv[1]
        print(f"🎯 Modo Paralelo: Processando apenas '{empresa_filtro}'")
    
    empresas_para_processar = EMPRESAS
    if empresa_filtro:
        empresas_para_processar = [e for e in EMPRESAS if e["empresa"] == empresa_filtro]
        if not empresas_para_processar:
            print(f"❌ Empresa '{empresa_filtro}' não encontrada na lista!")
            exit(1)
    
    print("Iniciando rotina de Contas a Pagar (com Zoom Progressivo + UPSERT)...\n")
    
    total_geral = 0
    for empresa in empresas_para_processar:
        print(f"{'='*60}")
        print(f"Extraindo Contas a Pagar de: {empresa['empresa']}...")
        print(f"{'='*60}")
        
        contas_pagar = puxar_contas_pagar(empresa)
        
        if contas_pagar:
            enviados = enviar_para_supabase(contas_pagar, empresa['empresa'])
            if enviados == len(contas_pagar):
                print(f"✅ {enviados} registros salvos via UPSERT para {empresa['empresa']}")
            else:
                print(f"⚠️ Apenas {enviados} de {len(contas_pagar)} registros salvos para {empresa['empresa']}")
            total_geral += enviados
        else:
            aviso(f"Contas a Pagar / {empresa['empresa']}: nenhum registro retornado pelo Omie (sem titulos ou falha de acesso). Dados antigos preservados.")
    
    print(f"\n{'='*60}")
    print(f"FIM! Total geral: {total_geral} registros processados.")
    print(f"{'='*60}")
    encerrar("Contas a Pagar")

if __name__ == "__main__":
    rodar_rotina_cp()
