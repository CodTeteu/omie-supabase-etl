"""
Recarga de contas a pagar com limpeza por empresa.

A rotina principal (contas_pagar_etl) so faz UPSERT: nunca remove titulos que
foram excluidos no Omie. Esta recarga limpa os dados de cada empresa e grava
de novo - mas so DEPOIS de extrair com sucesso.

A versao anterior apagava os titulos de todas as empresas logo ao ser
importada, antes de extrair qualquer coisa. Quando a extracao de uma empresa
falhava (ex.: STUDIO FACTORING, com a chave suspensa no Omie), o historico
dela era apagado e nada era gravado no lugar.
"""
import contas_pagar_etl
from gravacao import aviso, encerrar, substituir_dados_empresa


def rodar_recarga_cp():
    headers_supabase = {
        "apikey": contas_pagar_etl.SUPABASE_KEY,
        "Authorization": f"Bearer {contas_pagar_etl.SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal, resolution=merge-duplicates",
    }

    for empresa in contas_pagar_etl.EMPRESAS:
        print(f"\nExtraindo Contas a Pagar de: {empresa['empresa']}...")
        registros = contas_pagar_etl.puxar_contas_pagar(empresa)
        if not registros:
            aviso(f"Contas a Pagar / {empresa['empresa']}: nenhum registro retornado pelo Omie. Dados antigos preservados.")
            continue
        substituir_dados_empresa(contas_pagar_etl.SUPABASE_URL, headers_supabase, "contas_pagar",
                                 registros, empresa, "Contas a Pagar")

    print("\nFIM DA RECARGA DE CONTAS A PAGAR!")
    encerrar("Contas a Pagar (recarga)")


if __name__ == "__main__":
    rodar_recarga_cp()
