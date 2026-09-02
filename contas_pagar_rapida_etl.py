import os
import requests
import contas_pagar_etl

SUPABASE_URL = os.environ.get("SUPABASE_URL").rstrip('/')
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")

# Focar apenas na empresa STUDIO OPERACIONAL
# contas_pagar_etl.EMPRESAS = [
# ]

# LIMPAR a tabela contas_pagar ANTES de inserir (por empresa)
headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=minimal"
}

for empresa in contas_pagar_etl.EMPRESAS:
    cnpj = empresa["cnpj"]
    print(f"Limpando contas_pagar da empresa {empresa['empresa']} ({cnpj})...")
    resp = requests.delete(
        f"{SUPABASE_URL}/rest/v1/contas_pagar",
        headers=headers,
        params={"empresa_cnpj": f"eq.{cnpj}"}
    )
    print(f"  Status: {resp.status_code}")

if __name__ == "__main__":
    contas_pagar_etl.rodar_rotina_cp()
