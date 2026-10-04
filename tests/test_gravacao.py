"""
Testes da gravacao com falha visivel e da deduplicacao de movimentos.

Rodar na raiz do projeto:  python -m unittest discover -s tests -v
Nao precisa de banco nem de rede: as respostas do Supabase sao simuladas.
"""
import json
import os
import sys
import unittest
from unittest import mock

import requests

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# os scripts de ETL validam o ambiente ao serem importados
os.environ.setdefault("SUPABASE_URL", "https://teste.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "chave-de-teste")
os.environ.setdefault("OMIE_CREDENCIAIS", json.dumps(
    {"12.340.921/0001-82": {"app_key": "k", "app_secret": "s"}}))

import gravacao  # noqa: E402

EMPRESA = {"empresa": "EMPRESA TESTE", "cnpj": "00.000.000/0001-00"}
URL = "https://teste.supabase.co"


def resposta(status, texto=""):
    r = mock.Mock()
    r.status_code = status
    r.text = texto
    return r


class SubstituirDadosEmpresa(unittest.TestCase):
    def setUp(self):
        gravacao._falhas.clear()

    def test_banco_inacessivel_registra_falha_e_nao_grava(self):
        # o caso de 16/09 a 04/10/2026: DNS do projeto nao resolvia
        with mock.patch.object(gravacao.requests, "delete",
                               side_effect=requests.ConnectionError("getaddrinfo failed")), \
             mock.patch.object(gravacao.requests, "post") as post:
            gravados = gravacao.substituir_dados_empresa(URL, {}, "tab", [{"a": 1}], EMPRESA, "Teste")
        self.assertEqual(gravados, 0)
        post.assert_not_called()
        self.assertEqual(len(gravacao._falhas), 1)

    def test_limpeza_recusada_nao_grava_por_cima(self):
        with mock.patch.object(gravacao.requests, "delete", return_value=resposta(401, "JWT invalido")), \
             mock.patch.object(gravacao.requests, "post") as post:
            gravados = gravacao.substituir_dados_empresa(URL, {}, "tab", [{"a": 1}], EMPRESA, "Teste")
        self.assertEqual(gravados, 0)
        post.assert_not_called()
        self.assertEqual(len(gravacao._falhas), 1)

    def test_tudo_gravado_sem_falha(self):
        registros = [{"a": i} for i in range(1200)]  # 3 lotes de 500
        with mock.patch.object(gravacao.requests, "delete", return_value=resposta(204)), \
             mock.patch.object(gravacao.requests, "post", return_value=resposta(201)) as post:
            gravados = gravacao.substituir_dados_empresa(URL, {}, "tab", registros, EMPRESA, "Teste")
        self.assertEqual(gravados, 1200)
        self.assertEqual(post.call_count, 3)
        self.assertEqual(gravacao._falhas, [])

    def test_lote_recusado_conta_so_o_que_entrou(self):
        # o caso de setembro: lote com PK repetida recusado com erro 21000
        registros = [{"a": i} for i in range(1200)]
        respostas = [resposta(201), resposta(500, '{"code":"21000"}'), resposta(201)]
        with mock.patch.object(gravacao.requests, "delete", return_value=resposta(204)), \
             mock.patch.object(gravacao.requests, "post", side_effect=respostas):
            gravados = gravacao.substituir_dados_empresa(URL, {}, "tab", registros, EMPRESA, "Teste")
        self.assertEqual(gravados, 700)  # 500 + 200; o lote do meio caiu
        self.assertEqual(len(gravacao._falhas), 1)


class Encerrar(unittest.TestCase):
    def setUp(self):
        gravacao._falhas.clear()

    def test_sai_com_codigo_1_quando_houve_falha(self):
        gravacao.falha("algo nao foi gravado")
        with self.assertRaises(SystemExit) as ctx:
            gravacao.encerrar("Teste")
        self.assertEqual(ctx.exception.code, 1)

    def test_aviso_nao_derruba_a_execucao(self):
        gravacao.aviso("empresa com chave suspensa")
        gravacao.encerrar("Teste")  # nao deve levantar SystemExit
        self.assertEqual(gravacao._falhas, [])


class DeduplicarMovimentos(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import movimentos_financeiros_etl
        cls.dedup = staticmethod(movimentos_financeiros_etl.deduplicar_por_titulo)

    def mov(self, titulo, **extra):
        return {"id_movimento": titulo, "empresa_cnpj": EMPRESA["cnpj"], "valor_pago": 10, **extra}

    def test_repeticoes_identicas_viram_uma_sem_aviso(self):
        # caso real da ALIANCA LEGAL: dois movimentos que so diferem em nCodNF,
        # campo que nao e gravado - depois do mapeamento ficam identicos
        with mock.patch("movimentos_financeiros_etl.aviso") as aviso:
            saida = self.dedup([self.mov(1), self.mov(1), self.mov(2)], EMPRESA)
        self.assertEqual(len(saida), 2)
        aviso.assert_not_called()

    def test_repeticoes_divergentes_mantem_a_ultima_e_avisam(self):
        with mock.patch("movimentos_financeiros_etl.aviso") as aviso:
            saida = self.dedup([self.mov(1, valor_pago=10), self.mov(1, valor_pago=99)], EMPRESA)
        self.assertEqual(saida, [self.mov(1, valor_pago=99)])
        aviso.assert_called_once()

    def test_sem_repeticao_nao_muda_nada(self):
        entrada = [self.mov(1), self.mov(2), self.mov(3)]
        self.assertEqual(self.dedup(entrada, EMPRESA), entrada)


if __name__ == "__main__":
    unittest.main()
