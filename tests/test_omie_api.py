"""
Testes das regras de consumo da API do Omie (omie_api.py) e de como os
scripts reagem a cada tipo de erro. Sem rede: as respostas sao simuladas.

Rodar na raiz do projeto:  python -m unittest discover -s tests -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("SUPABASE_URL", "https://teste.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "chave-de-teste")
os.environ.setdefault("OMIE_CREDENCIAIS", json.dumps(
    {"12.340.921/0001-82": {"app_key": "k", "app_secret": "s"}}))
# os scripts de cadastro criam um cliente Supabase ao serem importados; aqui ele nao e usado
sys.modules.setdefault("supabase", mock.MagicMock())

import omie_api  # noqa: E402

EMPRESA = {"empresa": "EMPRESA TESTE", "cnpj": "00.000.000/0001-00", "app_key": "k", "app_secret": "s"}
SUSPENSA = '{"faultstring": "A chave de acesso está inválida ou o aplicativo está suspenso"}'


def resposta(status, texto="", dados=None):
    r = mock.Mock()
    r.status_code = status
    r.text = texto or json.dumps(dados or {}, ensure_ascii=False)
    r.json = mock.Mock(return_value=dados or {})
    return r


class Classificar(unittest.TestCase):
    def test_chave_suspensa_e_permanente(self):
        self.assertEqual(omie_api.classificar(403, SUSPENSA)[0], omie_api.PERMANENTE)

    def test_bloqueio_425_e_permanente(self):
        self.assertEqual(omie_api.classificar(425, "Bloqueado")[0], omie_api.PERMANENTE)

    def test_obedece_o_aguarde_n_segundos(self):
        self.assertEqual(omie_api.classificar(500, "Consumo redundante detectado. Aguarde 37 segundos."),
                         (omie_api.AGUARDAR, 38))

    def test_sem_registros_nao_e_erro(self):
        self.assertEqual(omie_api.classificar(500, "ERROR: Não existem registros para a página [3]!")[0],
                         omie_api.VAZIO)

    def test_instabilidade_espera_crescente(self):
        esperas = [omie_api.classificar(500, "Erro interno", t)[1] for t in range(4)]
        self.assertEqual(esperas, [5, 10, 20, 40])


class TotalInformado(unittest.TestCase):
    def test_nome_do_campo_muda_conforme_a_api(self):
        self.assertEqual(omie_api.total_informado({"total_de_registros": 120}), 120)
        self.assertEqual(omie_api.total_informado({"nTotRegistros": "35"}), 35)

    def test_sem_total_na_resposta(self):
        self.assertIsNone(omie_api.total_informado({}))
        self.assertIsNone(omie_api.total_informado({"total_de_registros": "x"}))

    def test_extracao_devolve_o_total_que_o_omie_informa(self):
        import contas_receber_etl as m
        pagina = resposta(200, dados={"total_de_registros": 2, "conta_receber_cadastro": [
            {"codigo_lancamento_omie": 1}, {"codigo_lancamento_omie": 2}]})
        fim = resposta(200, dados={"total_de_registros": 2, "conta_receber_cadastro": []})
        with mock.patch.object(m.requests, "post", side_effect=[pagina, fim]), mock.patch.object(m.time, "sleep"):
            registros, total = m.puxar_contas_receber(EMPRESA)
        self.assertEqual((len(registros), total), (2, 2))


class ChaveSuspensaUmaRequisicaoSo(unittest.TestCase):
    """
    Chave suspensa ou bloqueio 425: uma requisicao e para. Antes eram ate 10
    por pagina - e, em contas a pagar e departamentos, mais o zoom progressivo -
    o que gerava bloqueios de 30 minutos em serie.
    """

    def extrair(self, modulo, funcao, resp):
        mod = __import__(modulo)
        with mock.patch.object(mod.requests, "post", return_value=resp) as post, \
             mock.patch.object(mod.time, "sleep"):
            resultado = getattr(mod, funcao)(EMPRESA)
        return resultado, post.call_count

    def checar(self, modulo, funcao, resp=None):
        resultado, chamadas = self.extrair(modulo, funcao, resp or resposta(403, SUSPENSA))
        self.assertIsNone(resultado, f"{modulo} deveria devolver None (empresa fora)")
        self.assertEqual(chamadas, 1, f"{modulo} insistiu: {chamadas} requisicoes")

    def test_contas_pagar(self):
        self.checar("contas_pagar_etl", "puxar_contas_pagar")

    def test_contas_pagar_bloqueio_425(self):
        self.checar("contas_pagar_etl", "puxar_contas_pagar", resposta(425, "Bloqueado"))

    def test_departamentos(self):
        self.checar("sync_departamentos", "puxar_departamentos_isolado")

    def test_contas_receber(self):
        self.checar("contas_receber_etl", "puxar_contas_receber")

    def test_conta_corrente(self):
        self.checar("conta_corrente_etl", "puxar_conta_corrente")

    def test_movimentos(self):
        self.checar("movimentos_financeiros_etl", "puxar_movimentos_financeiros")

    def test_clientes(self):
        # antes devolvia [] e a empresa sumia em silencio, sem nem aviso
        self.checar("sync_clientes", "puxar_clientes")


class OutrosErros(unittest.TestCase):
    def test_categorias_erro_500_comum_nao_e_chave_suspensa(self):
        # antes, QUALQUER 500 era tratado como chave suspensa e a empresa era pulada
        import sync_categorias
        ok = resposta(200, dados={"total_de_paginas": 1, "categoria_cadastro": [{"codigo": "1.01"}]})
        with mock.patch.object(sync_categorias.requests, "post",
                               side_effect=[resposta(500, "Erro interno do servidor"), ok]) as post, \
             mock.patch.object(sync_categorias.time, "sleep"), \
             mock.patch.object(sync_categorias, "empresa_fora") as fora:
            sucesso, registros, _, bloqueio, _ = sync_categorias.tentar_pagina("url", EMPRESA, 1, 50)
        fora.assert_not_called()
        self.assertTrue(sucesso)
        self.assertFalse(bloqueio)
        self.assertEqual(len(registros), 1)
        self.assertEqual(post.call_count, 2)

    def test_espera_o_tempo_que_o_omie_pede(self):
        import contas_receber_etl as m
        fim = resposta(200, dados={"total_de_paginas": 1, "conta_receber_cadastro": []})
        with mock.patch.object(m.requests, "post",
                               side_effect=[resposta(500, "Consumo redundante detectado. Aguarde 3 segundos."), fim]), \
             mock.patch.object(m.time, "sleep") as dormir:
            resultado = m.puxar_contas_receber(EMPRESA)
        dormir.assert_any_call(4)
        self.assertEqual(resultado, ([], None))

    def test_sem_registros_devolve_lista_vazia_e_nao_falha(self):
        import contas_receber_etl as m
        with mock.patch.object(m.requests, "post",
                               return_value=resposta(500, "ERROR: Não existem registros para a página [1]!")) as post, \
             mock.patch.object(m.time, "sleep"):
            resultado = m.puxar_contas_receber(EMPRESA)
        self.assertEqual(resultado, ([], None))
        self.assertEqual(post.call_count, 1)


if __name__ == "__main__":
    unittest.main()
