import os
import requests
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
    if not data_br: return None
    try:
        p = data_br.split('/')
        return f"{p[2]}-{p[1]}-{p[0]}"
    except:
        return None

def obter_contas_correntes(empresa_config):
    """Busca todas as contas correntes da empresa para podermos iterar sobre elas."""
    pagina = 1
    contas = []
    url = "https://app.omie.com.br/api/v1/financas/contacorrente/"
    
    while True:
        body = {
            "call": "ListarResumoContasCorrentes",
            "app_key": empresa_config["app_key"],
            "app_secret": empresa_config["app_secret"],
            "param": [{"nPagina": pagina, "nRegPorPagina": 100}]
        }
        
        try:
            resp = requests.post(url, json=body, timeout=30)
            if resp.status_code == 200:
                data = resp.json()
                if "conta_corrente_resumo" in data and len(data["conta_corrente_resumo"]) > 0:
                    for cc in data["conta_corrente_resumo"]:
                        contas.append({
                            "nCodCC": cc.get("nCodCC"),
                            "cDescricao": cc.get("cDescricao")
                        })
                    pagina += 1
                else:
                    break
            else:
                print(f"Erro ao buscar contas correntes {empresa_config['empresa']}: {resp.status_code}")
                break
        except Exception as e:
            print(f"Exceção ao buscar contas correntes {empresa_config['empresa']}: {e}")
            time.sleep(5)
            break
            
    return contas

def puxar_extrato(empresa_config):
    todos_registros = []
    url_extrato = "https://app.omie.com.br/api/v1/financas/extrato/"
    
    # 1. Pega contas correntes
    contas = obter_contas_correntes(empresa_config)
    if not contas:
        return None
        
    hoje_br = datetime.now().strftime("%d/%m/%Y")
    
    for cc in contas:
        body = {
            "call": "ListarExtrato",
            "app_key": empresa_config["app_key"],
            "app_secret": empresa_config["app_secret"],
            "param": [{
                "nCodCC": cc["nCodCC"],
                "dPeriodoInicial": "01/01/2000",
                "dPeriodoFinal": hoje_br
            }]
        }
        
        for tentativa in range(3):
            try:
                response = requests.post(url_extrato, json=body, timeout=60)
                if response.status_code == 200:
                    data = response.json()
                    lista_movs = data.get("listaMovimentos", [])
                    
                    for mov in lista_movs:
                        registro = {
                            "empresa_cnpj": empresa_config["cnpj"],
                            "empresa_nome": empresa_config["empresa"],
                            "id_conta_corrente": cc["nCodCC"],
                            "descricao_conta": cc["cDescricao"],
                            "data_lancamento": converter_data(mov.get("dDataLancamento")),
                            "id_lancamento": mov.get("nCodLancamento") or 0,
                            "id_lancamento_relacionado": mov.get("nCodLancRelac"),
                            "situacao": mov.get("cSituacao"),
                            "nome_fantasia_cliente": mov.get("cDesCliente"),
                            "tipo_documento": mov.get("cTipoDocumento"),
                            "numero_documento": mov.get("cNumero"),
                            "valor_documento": mov.get("nValorDocumento"),
                            "saldo_realizado": mov.get("nSaldo"),
                            "codigo_categoria": mov.get("cCodCategoria"),
                            "descricao_categoria": mov.get("cDesCategoria"),
                            "numero_documento_fiscal": mov.get("cDocumentoFiscal"),
                            "parcela": mov.get("cParcela"),
                            "nosso_numero": mov.get("cNossoNumero"),
                            "origem": mov.get("cOrigem"),
                            "vendedor": mov.get("cVendedor"),
                            "projeto": mov.get("cProjeto"),
                            "id_cliente_fornecedor": mov.get("nCodCliente"),
                            "razao_social_cliente": mov.get("cRazCliente")
                        }
                        todos_registros.append(registro)
                    break # sucesso
                else:
                    print(f"Falha ao buscar extrato CC {cc['nCodCC']} da {empresa_config['empresa']}: {response.text}")
                    time.sleep(5)
            except Exception as e:
                print(f"Exceção no extrato da {empresa_config['empresa']} (CC {cc['nCodCC']}): {e}")
                time.sleep(5)
                
    return todos_registros

def rodar_rotina_extrato():
    print("Iniciando rotina de Extrato Bancário (Multi-Tenant Omie -> Supabase)...")
    
    headers_supabase = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal, resolution=merge-duplicates"
    }

    for empresa in EMPRESAS:
        print(f"\nExtraindo Extrato de: {empresa['empresa']}...")
        movimentos = puxar_extrato(empresa)
        
        if movimentos is None:
            print(f"⚠️ ERRO DETECTADO NA EXTRAÇÃO DA {empresa['empresa']}.")
            continue
            
        if movimentos:
            try:
                # 1. Apaga apenas os dados DAQUELA EMPRESA
                print(f"Limpando base antiga de extrato da empresa {empresa['empresa']}...")
                requests.delete(
                    f"{SUPABASE_URL}/rest/v1/extrato_bancario", 
                    headers=headers_supabase, 
                    params={"empresa_cnpj": f"eq.{empresa['cnpj']}"}
                )
                
                # 2. Insere os novos dados daquela empresa
                tamanho_lote = 500
                for i in range(0, len(movimentos), tamanho_lote):
                    lote = movimentos[i:i + tamanho_lote]
                    resp = requests.post(f"{SUPABASE_URL}/rest/v1/extrato_bancario", json=lote, headers=headers_supabase, timeout=60)
                    if resp.status_code not in (200, 201):
                         print(f"❌ Erro na API do Supabase (Extrato): {resp.text}")
                print(f"✅ Inseridos {len(movimentos)} movimentos de extrato para {empresa['empresa']}")
            except Exception as e:
                print(f"❌ Erro ao enviar Extrato da empresa {empresa['empresa']}: {e}")
        else:
            print(f"Nenhum registro encontrado para {empresa['empresa']}.")

    print("\nFIM DA ROTINA DE EXTRATO BANCÁRIO!")

if __name__ == "__main__":
    rodar_rotina_extrato()
