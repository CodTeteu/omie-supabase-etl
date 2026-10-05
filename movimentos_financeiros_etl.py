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
from gravacao import aviso, empresa_fora, encerrar, substituir_dados_empresa

def converter_data(data_br):
    if not data_br:
        return None
    try:
        partes = data_br.split('/')
        return f"{partes[2]}-{partes[1]}-{partes[0]}"
    except:
        return None

def puxar_movimentos_financeiros(empresa_config):
    pagina = 1
    tem_mais = True
    todos_registros = []
    url = "https://app.omie.com.br/api/v1/financas/mf/"
    
    while tem_mais:
        body = {
            "call": "ListarMovimentos",
            "app_key": empresa_config["app_key"],
            "app_secret": empresa_config["app_secret"],
            "param": [{"nPagina": pagina, "nRegPorPagina": 100, "cTpLancamento": "CR"}]
        }
        
        sucesso_na_pagina = False
        for tentativa in range(3):
            try:
                response = requests.post(url, json=body, timeout=30)
                if response.status_code == 200:
                    data = response.json()
                    if "movimentos" in data and len(data["movimentos"]) > 0:
                        for mov in data["movimentos"]:
                            det = mov.get("detalhes", {})
                            res = mov.get("resumo", {})
                            

                                
                            registro = {
                                "id_movimento": det.get("nCodTitulo"),
                                "empresa_nome": empresa_config["empresa"],
                                "empresa_cnpj": empresa_config["cnpj"],
                                "id_conta_corrente": det.get("nCodCC"),
                                "id_cliente_fornecedor": det.get("nCodCliente"),
                                "id_titulo_origem": det.get("nCodTitRepet"),
                                "grupo": det.get("cGrupo"),
                                "natureza": det.get("cNatureza"),
                                "tipo": det.get("cTipo"),
                                "origem": det.get("cOrigem"),
                                "categoria_codigo": det.get("cCodCateg"),
                                "numero_titulo": det.get("cNumTitulo"),
                                "numero_parcela": det.get("cNumParcela"),
                                "chave_nfe": det.get("cChaveNFe"),
                                "cpf_cnpj": det.get("cCPFCNPJCliente"),
                                "codigo_barras": det.get("cCodigoBarras"),
                                "data_emissao": converter_data(det.get("dDtEmissao")),
                                "data_vencimento": converter_data(det.get("dDtVenc")),
                                "data_previsao": converter_data(det.get("dDtPrevisao")),
                                "data_pagamento": converter_data(det.get("dDtPagamento")),
                                "data_registro": converter_data(det.get("dDtRegistro")),
                                "valor_titulo": det.get("nValorTitulo") or 0.0,
                                "valor_pago": res.get("nValPago") or 0.0,
                                "valor_liquido": res.get("nValLiquido") or 0.0,
                                "valor_aberto": res.get("nValAberto") or 0.0
                            }
                            todos_registros.append(registro)
                        
                        sucesso_na_pagina = True
                        pagina += 1
                        break # Sai do loop de retentativas
                    else:
                        tem_mais = False # Lista veio vazia, significa que acabou
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
            return None # Retorna None para avisar a função principal que houve erro crítico na extração
            
    return todos_registros

def deduplicar_por_titulo(movimentos, empresa):
    """
    Um titulo pode vir em mais de um movimento (ex.: duas notas fiscais no
    mesmo titulo). A tabela guarda um registro por titulo, e um lote com o
    mesmo titulo repetido e recusado inteiro pelo Supabase (erro 21000:
    "ON CONFLICT DO UPDATE command cannot affect row a second time").
    Mantem o ultimo de cada titulo e avisa quando as repeticoes divergem em
    algum campo gravado.
    """
    unicos, divergentes = {}, 0
    for m in movimentos:
        chave = (m["id_movimento"], m["empresa_cnpj"])
        if chave in unicos and unicos[chave] != m:
            divergentes += 1
        unicos[chave] = m
    repetidos = len(movimentos) - len(unicos)
    if divergentes:
        aviso(f"Movimentos Financeiros / {empresa['empresa']}: {divergentes} titulo(s) com movimentos divergentes; mantido o ultimo de cada")
    elif repetidos:
        print(f"   {repetidos} movimento(s) repetido(s) por titulo, identicos apos o mapeamento - consolidados")
    return list(unicos.values())


def rodar_rotina_mf():
    print("Iniciando rotina de Movimentos Financeiros (Multi-Tenant Omie -> Supabase)...")
    
    headers_supabase = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal, resolution=merge-duplicates"
    }

    # O DELETE GLOBAL FOI REMOVIDO DAQUI POR SEGURANÇA!

    for empresa in EMPRESAS:
        print(f"\nExtraindo Movimentos Financeiros de: {empresa['empresa']}...")
        movimentos = puxar_movimentos_financeiros(empresa)
        
        if movimentos is None:
            empresa_fora("Movimentos Financeiros", empresa, "falha na extracao do Omie")
            continue
            
        if movimentos:
            movimentos = deduplicar_por_titulo(movimentos, empresa)
            substituir_dados_empresa(SUPABASE_URL, headers_supabase, "movimentos_financeiros", movimentos, empresa, "Movimentos Financeiros")
        else:
            print(f"Nenhum registro encontrado para {empresa['empresa']}.")
            
    print("\nFIM DA ROTINA DE MOVIMENTOS FINANCEIROS!")
    encerrar("Movimentos Financeiros")

if __name__ == "__main__":
    rodar_rotina_mf()
