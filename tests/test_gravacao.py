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
        sem_espera = mock.patch.object(gravacao.time, "sleep")
        sem_espera.start()
        self.addCleanup(sem_espera.stop)

    def test_banco_inacessivel_registra_falha_e_nao_grava(self):
        # o caso de 16/09 a 04/10/2026: DNS do projeto nao resolvia
        with mock.patch.object(gravacao.requests, "delete",
                               side_effect=requests.ConnectionError("getaddrinfo failed")) as delete, \
             mock.patch.object(gravacao.requests, "post") as post:
            gravados = gravacao.substituir_dados_empresa(URL, {}, "tab", [{"a": 1}], EMPRESA, "Teste")
        self.assertEqual(gravados, 0)
        self.assertEqual(delete.call_count, 3)  # tentou 3 vezes antes de desistir
        post.assert_not_called()
        self.assertEqual(len(gravacao._falhas), 1)

    def test_extracao_incompleta_nao_apaga_so_atualiza(self):
        registros = [{"a": i} for i in range(700)]
        with mock.patch.object(gravacao.requests, "delete") as delete, \
             mock.patch.object(gravacao.requests, "post", return_value=resposta(201)) as post:
            gravados = gravacao.substituir_dados_empresa(URL, {}, "tab", registros, EMPRESA, "Teste",
                                                         apagar_antes=False)
        delete.assert_not_called()
        self.assertEqual(post.call_count, 2)
        self.assertEqual(gravados, 700)
        self.assertEqual(gravacao._falhas, [])

    def test_rede_instavel_repete_o_lote(self):
        with mock.patch.object(gravacao.requests, "delete", return_value=resposta(204)), \
             mock.patch.object(gravacao.requests, "post",
                               side_effect=[requests.ConnectionError("reset"), resposta(503), resposta(201)]) as post:
            gravados = gravacao.substituir_dados_empresa(URL, {}, "tab", [{"a": 1}], EMPRESA, "Teste")
        self.assertEqual(gravados, 1)
        self.assertEqual(post.call_count, 3)
        self.assertEqual(gravacao._falhas, [])

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
        # o caso de setembro: lote com PK repetida recusado com erro 21000 (repetido 3 vezes, sem sucesso)
        registros = [{"a": i} for i in range(1200)]
        recusa = resposta(500, '{"code":"21000"}')
        respostas = [resposta(201), recusa, recusa, recusa, resposta(201)]
        with mock.patch.object(gravacao.requests, "delete", return_value=resposta(204)), \
             mock.patch.object(gravacao.requests, "post", side_effect=respostas):
            gravados = gravacao.substituir_dados_empresa(URL, {}, "tab", registros, EMPRESA, "Teste")
        self.assertEqual(gravados, 700)  # 500 + 200; o lote do meio caiu
        self.assertEqual(len(gravacao._falhas), 1)


class ExtracaoCompleta(unittest.TestCase):
    """A trava de antes de apagar: so apaga a empresa se veio tudo o que o Omie diz ter."""

    def setUp(self):
        gravacao._falhas.clear()

    def test_veio_tudo(self):
        with mock.patch.object(gravacao, "aviso") as aviso:
            self.assertTrue(gravacao.extracao_completa("Teste", EMPRESA, 120, 120))
        aviso.assert_not_called()

    def test_faltou_registro_nao_apaga_e_avisa(self):
        # ex.: o zoom progressivo nao recuperou um titulo, ou a lista veio cortada
        with mock.patch.object(gravacao, "aviso") as aviso:
            self.assertFalse(gravacao.extracao_completa("Teste", EMPRESA, 119, 120))
        aviso.assert_called_once()
        self.assertEqual(gravacao._falhas, [])  # nada se perde: e aviso, nao falha

    def test_veio_a_mais_nao_e_falta(self):
        # lancamento incluido no Omie enquanto a extracao rodava
        self.assertTrue(gravacao.extracao_completa("Teste", EMPRESA, 121, 120))

    def test_sem_total_informado_confia_na_paginacao(self):
        self.assertTrue(gravacao.extracao_completa("Teste", EMPRESA, 50, None))


class SegundaChance(unittest.TestCase):
    """Instabilidade do Omie costuma passar em minutos: quem falhou tenta de novo no fim."""

    def setUp(self):
        gravacao._falhas.clear()

    def test_empresa_que_falhou_tenta_de_novo_no_fim(self):
        chamadas = []

        def processar(empresa, ultima_chance):
            chamadas.append((empresa["empresa"], ultima_chance))
            return ultima_chance or empresa["empresa"] != "B"  # B falha na primeira passada

        with mock.patch.object(gravacao.time, "sleep") as dormir:
            gravacao.com_segunda_chance([{"empresa": "A"}, {"empresa": "B"}, {"empresa": "C"}], processar)
        self.assertEqual(chamadas, [("A", False), ("B", False), ("C", False), ("B", True)])
        dormir.assert_called_once_with(120)

    def test_sem_falha_nao_espera(self):
        with mock.patch.object(gravacao.time, "sleep") as dormir:
            gravacao.com_segunda_chance([{"empresa": "A"}], lambda empresa, ultima_chance: True)
        dormir.assert_not_called()

    def test_suspensa_conhecida_nao_espera_segunda_chance(self):
        chamadas = []

        def processar(empresa, ultima_chance):
            chamadas.append((empresa["empresa"], ultima_chance))
            return ultima_chance

        with mock.patch.object(gravacao.time, "sleep") as dormir:
            gravacao.com_segunda_chance([{"empresa": "GROWTH", "suspensa_desde": "2026-09-22"}], processar)
        self.assertEqual(chamadas, [("GROWTH", True)])
        dormir.assert_not_called()

    def test_conta_corrente_se_recupera_sem_falha(self):
        # o caso de 07/10/2026: HTTP 500 na pagina 122 da STUDIO OPERACIONAL, que voltou depois
        import conta_corrente_etl as m
        with mock.patch.object(m, "EMPRESAS", [EMPRESA]), \
             mock.patch.object(m, "puxar_conta_corrente", side_effect=[None, ([{"codigo_lancamento": 1}], 1)]), \
             mock.patch.object(m, "substituir_dados_empresa") as gravar, \
             mock.patch.object(gravacao.time, "sleep"):
            m.rodar_rotina_cc()  # nao deve sair com erro
        gravar.assert_called_once()
        self.assertEqual(gravacao._falhas, [])

    def test_conta_corrente_falha_duas_vezes_vira_falha(self):
        import conta_corrente_etl as m
        with mock.patch.object(m, "EMPRESAS", [EMPRESA]), \
             mock.patch.object(m, "puxar_conta_corrente", return_value=None) as puxar, \
             mock.patch.object(m, "substituir_dados_empresa") as gravar, \
             mock.patch.object(gravacao.time, "sleep"):
            with self.assertRaises(SystemExit):
                m.rodar_rotina_cc()
        self.assertEqual(puxar.call_count, 2)
        gravar.assert_not_called()


class DeduplicarContasPagar(unittest.TestCase):
    def test_um_titulo_por_codigo_fica_o_ultimo(self):
        import contas_pagar_etl
        saida = contas_pagar_etl.deduplicar([{"codigo_lancamento_omie": 1, "v": "a"},
                                             {"codigo_lancamento_omie": 2, "v": "b"},
                                             {"codigo_lancamento_omie": 1, "v": "c"}])
        self.assertEqual(sorted((r["codigo_lancamento_omie"], r["v"]) for r in saida), [(1, "c"), (2, "b")])


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


class EmpresaFora(unittest.TestCase):
    def setUp(self):
        gravacao._falhas.clear()

    def test_suspensa_conhecida_gera_so_aviso(self):
        # FACTORING e GROWTH: chave suspensa no Omie, ausencia ja conhecida
        suspensa = {**EMPRESA, "suspensa_desde": "2026-09-22"}
        gravacao.empresa_fora("Teste", suspensa, "falha na extracao do Omie")
        self.assertEqual(gravacao._falhas, [])
        gravacao.encerrar("Teste")  # nao deve levantar SystemExit

    def test_empresa_nova_fora_vira_falha(self):
        # o caso da GROWTH antes de ser marcada: 12 dias fora sem ninguem saber
        gravacao.empresa_fora("Teste", EMPRESA, "falha na extracao do Omie")
        self.assertEqual(len(gravacao._falhas), 1)
        with self.assertRaises(SystemExit):
            gravacao.encerrar("Teste")


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
