"""
Provisiona o banco do zero a partir do repositorio.

  DATABASE_URL="postgresql://..." python provisionar.py

Aplica provisionar_banco_completo.sql (idempotente: pode rodar mais de uma
vez), confere os 25 objetos com verificar_setup.sql e mostra o espaco usado.

Com isso, perder o projeto Supabase deixa de ser catastrofico: cria-se um
projeto novo, roda-se este script e a rotina diaria repovoa os dados a
partir do Omie. Foi o que faltou em setembro/2026, quando o banco sumiu
levando a unica copia das views.

DATABASE_URL deve ser a connection string do "Session pooler" do Supabase
(botao Connect do projeto). A conexao direta (db.<ref>.supabase.co) usa so
IPv6, que os runners do GitHub Actions nao suportam.
"""
import os
import pathlib
import sys

import psycopg2

RAIZ = pathlib.Path(__file__).resolve().parent
LIMITE_FREE_MB = 500


def erro(msg):
    print(f"❌ {msg}")
    print(f"::error::{msg[:500]}")
    sys.exit(1)


def main():
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        erro("DATABASE_URL nao configurada. Use a connection string do Session pooler do Supabase.")

    try:
        conn = psycopg2.connect(dsn, connect_timeout=30)
    except psycopg2.OperationalError as e:
        erro(f"Nao foi possivel conectar ao banco: {e}")

    # tudo numa transacao: se qualquer comando falhar, nada fica pela metade
    print("Aplicando provisionar_banco_completo.sql ...")
    try:
        with conn, conn.cursor() as cur:
            cur.execute((RAIZ / "provisionar_banco_completo.sql").read_text(encoding="utf-8"))
    except psycopg2.Error as e:
        erro(f"Falha ao aplicar o schema (nada foi alterado): {e}")
    print("✅ Schema aplicado.\n")

    with conn.cursor() as cur:
        cur.execute((RAIZ / "verificar_setup.sql").read_text(encoding="utf-8"))
        objetos = cur.fetchall()
        cur.execute("SELECT pg_database_size(current_database())")
        mb = cur.fetchone()[0] / 1024 / 1024
    conn.close()

    faltando = [o for o in objetos if o[2] != "OK"]
    for tipo, nome, status, detalhe in objetos:
        print(f"  {status:<16} {tipo:<11} {nome:<30} {detalhe or ''}")
    print(f"\n{len(objetos) - len(faltando)} de {len(objetos)} objetos OK.")

    uso = 100 * mb / LIMITE_FREE_MB
    print(f"Espaco usado: {mb:.0f} MB de {LIMITE_FREE_MB} MB do plano Free ({uso:.0f}%).")
    if uso > 80:
        print(f"::warning::Banco com {mb:.0f} MB, acima de 80% do limite do plano Free.")

    if faltando:
        erro(f"Objetos faltando: {', '.join(o[1] for o in faltando)}")


if __name__ == "__main__":
    main()
