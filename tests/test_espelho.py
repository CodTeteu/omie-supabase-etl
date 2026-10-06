"""
Testes do espelho (gravacao repetida no banco da Audit) e da comparacao no fim da rotina.

Rodar na raiz do projeto:  python -m unittest discover -s tests -v
Nao precisa de banco nem de rede: as respostas do Supabase sao simuladas.
"""
import json
import os
import sys
import unittest
from unittest import mock

import httpx
import requests

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("SUPABASE_URL", "https://teste.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "chave-de-teste")
os.environ.setdefault("OMIE_CREDENCIAIS", json.dumps(
    {"12.340.921/0001-82": {"app_key": "k", "app_secret": "s"}}))

REQUEST_ORIGINAL = requests.sessions.Session.request
SEND_ORIGINAL = httpx.Client.send

import espelho  # noqa: E402
import gravacao  # noqa: E402
import sincronizar_espelho  # noqa: E402

PRINCIPAL = "https://principal.supabase.co"
ESPELHO = "https://espelho.supabase.co"
AMBIENTE = {"SUPABASE_URL": PRINCIPAL, "SUPABASE_KEY": "chave-principal",
            "SUPABASE_URL_ESPELHO": ESPELHO, "SUPABASE_KEY_ESPELHO": "chave-espelho"}


def resposta(status, texto=""):
    r = mock.Mock()
    r.status_code = status
    r.text = texto
    return r


class Base(unittest.TestCase):
    def setUp(self):
        gravacao._falhas.clear()
        espelho._estado.update(ativo=False, parado=False, repetidas=0, falhas=0, seguidas=0)
        requests.sessions.Session.request = REQUEST_ORIGINAL
        httpx.Client.send = SEND_ORIGINAL

    def tearDown(self):
        requests.sessions.Session.request = REQUEST_ORIGINAL
        httpx.Client.send = SEND_ORIGINAL
        espelho._estado.update(ativo=False, parado=False, repetidas=0, falhas=0, seguidas=0)
        gravacao._falhas.clear()

    def ligar(self):
        with mock.patch.dict(os.environ, AMBIENTE):
            self.assertTrue(espelho.ligar())


class SemConfiguracao(Base):
    def test_sem_variaveis_nao_liga_nem_mexe_no_requests(self):
        with mock.patch.dict(os.environ, {"SUPABASE_URL": PRINCIPAL}, clear=False):
            os.environ.pop("SUPABASE_URL_ESPELHO", None)
            os.environ.pop("SUPABASE_KEY_ESPELHO", None)
            self.assertFalse(espelho.ligar())
        self.assertFalse(espelho.ativo())
        self.assertIs(requests.sessions.Session.request, REQUEST_ORIGINAL)
        self.assertIsNone(espelho.alvo(PRINCIPAL + "/rest/v1/contas_pagar"))

    def test_espelho_igual_ao_principal_nao_liga(self):
        with mock.patch.dict(os.environ, {**AMBIENTE, "SUPABASE_URL_ESPELHO": PRINCIPAL}):
            self.assertFalse(espelho.ligar())


class Requests(Base):
    def chamadas(self, respostas):
        """Simula o requests: devolve a resposta conforme o host e guarda cada chamada."""
        feitas = []

        def falso(sessao, method, url, *args, **kwargs):
            feitas.append((method, url, kwargs))
            return respostas["espelho" if url.startswith(ESPELHO) else "principal"]
        return feitas, falso

    def test_gravacao_aceita_e_repetida_no_espelho_com_a_chave_do_espelho(self):
        self.ligar()
        feitas, falso = self.chamadas({"principal": resposta(201), "espelho": resposta(201)})
        with mock.patch.object(espelho, "_request_original", falso):
            r = requests.post(PRINCIPAL + "/rest/v1/contas_receber_grupo", json=[{"a": 1}],
                              headers={"apikey": "chave-principal", "Authorization": "Bearer chave-principal"},
                              timeout=60)
        self.assertEqual(r.status_code, 201)
        self.assertEqual(len(feitas), 2)
        metodo, url, kw = feitas[1]
        self.assertEqual(url, ESPELHO + "/rest/v1/contas_receber_grupo")
        self.assertEqual(kw["json"], [{"a": 1}])
        self.assertEqual(kw["headers"]["apikey"], "chave-espelho")
        self.assertEqual(kw["headers"]["Authorization"], "Bearer chave-espelho")
        self.assertEqual(espelho.resumo()["repetidas"], 1)
        self.assertEqual(gravacao._falhas, [])

    def test_delete_repete_o_filtro(self):
        self.ligar()
        feitas, falso = self.chamadas({"principal": resposta(204), "espelho": resposta(204)})
        with mock.patch.object(espelho, "_request_original", falso):
            requests.delete(PRINCIPAL + "/rest/v1/conta_corrente", params={"empresa_cnpj": "eq.1"},
                            headers={"apikey": "chave-principal"}, timeout=60)
        self.assertEqual(feitas[1][1], ESPELHO + "/rest/v1/conta_corrente")
        self.assertEqual(feitas[1][2]["params"], {"empresa_cnpj": "eq.1"})

    def test_leitura_omie_e_recusa_do_principal_nao_sao_repetidas(self):
        self.ligar()
        feitas, falso = self.chamadas({"principal": resposta(409, "duplicada"), "espelho": resposta(201)})
        with mock.patch.object(espelho, "_request_original", falso):
            requests.get(PRINCIPAL + "/rest/v1/contas_pagar?select=*", timeout=60)
            requests.post("https://app.omie.com.br/api/v1/geral/clientes/", json={}, timeout=60)
            requests.post(PRINCIPAL + "/rest/v1/contas_pagar", json=[{}], timeout=60)
        self.assertEqual(len(feitas), 3)
        self.assertFalse(any(u.startswith(ESPELHO) for _, u, _ in feitas))

    def test_falha_no_espelho_vira_falha_mas_o_principal_responde_igual(self):
        self.ligar()
        feitas, falso = self.chamadas({"principal": resposta(201), "espelho": resposta(500, "fora do ar")})
        with mock.patch.object(espelho, "_request_original", falso):
            r = requests.post(PRINCIPAL + "/rest/v1/clientes_grupo", json=[{}], timeout=60)
        self.assertEqual(r.status_code, 201)
        self.assertEqual(len(gravacao._falhas), 1)
        self.assertIn("Espelho", gravacao._falhas[0])

    def test_espelho_para_depois_de_falhas_seguidas(self):
        self.ligar()
        feitas, falso = self.chamadas({"principal": resposta(201), "espelho": resposta(503)})
        with mock.patch.object(espelho, "_request_original", falso):
            for _ in range(espelho.MAX_FALHAS_SEGUIDAS + 3):
                requests.post(PRINCIPAL + "/rest/v1/clientes_grupo", json=[{}], timeout=60)
        no_espelho = [u for _, u, _ in feitas if u.startswith(ESPELHO)]
        self.assertEqual(len(no_espelho), espelho.MAX_FALHAS_SEGUIDAS)
        self.assertTrue(espelho.resumo()["parado"])
        self.assertFalse(espelho.ativo())

    def test_rede_fora_no_espelho_vira_falha(self):
        self.ligar()

        def falso(sessao, method, url, *args, **kwargs):
            if url.startswith(ESPELHO):
                raise requests.ConnectionError("getaddrinfo failed")
            return resposta(201)
        with mock.patch.object(espelho, "_request_original", falso):
            r = requests.post(PRINCIPAL + "/rest/v1/clientes_grupo", json=[{}], timeout=60)
        self.assertEqual(r.status_code, 201)
        self.assertEqual(len(gravacao._falhas), 1)


class Httpx(Base):
    def test_cliente_supabase_py_tambem_e_espelhado(self):
        self.ligar()
        vistos = []

        def servidor(request):
            vistos.append(request)
            return httpx.Response(201, json=[])
        cliente = httpx.Client(transport=httpx.MockTransport(servidor))
        r = cliente.post(PRINCIPAL + "/rest/v1/categorias_omie?on_conflict=codigo,empresa_cnpj",
                         json=[{"codigo": "1.01"}], headers={"apikey": "chave-principal", "Authorization": "Bearer chave-principal"})
        cliente.get(PRINCIPAL + "/rest/v1/categorias_omie?select=*")
        self.assertEqual(r.status_code, 201)
        self.assertEqual(len(vistos), 3)
        copia = vistos[1]
        self.assertEqual(str(copia.url), ESPELHO + "/rest/v1/categorias_omie?on_conflict=codigo,empresa_cnpj")
        self.assertEqual(copia.headers["apikey"], "chave-espelho")
        self.assertEqual(copia.headers["authorization"], "Bearer chave-espelho")
        self.assertEqual(json.loads(copia.content), [{"codigo": "1.01"}])
        self.assertEqual(str(vistos[2].url).split("?")[0], PRINCIPAL + "/rest/v1/categorias_omie")

    def test_falha_httpx_no_espelho_vira_falha(self):
        self.ligar()

        def servidor(request):
            return httpx.Response(500 if str(request.url).startswith(ESPELHO) else 204)
        cliente = httpx.Client(transport=httpx.MockTransport(servidor))
        r = cliente.delete(PRINCIPAL + "/rest/v1/departamentos_omie?empresa_cnpj=eq.1")
        self.assertEqual(r.status_code, 204)
        self.assertEqual(len(gravacao._falhas), 1)


class Sincronizar(unittest.TestCase):
    def test_valores_do_filtro_in_vao_entre_aspas(self):
        self.assertEqual(sincronizar_espelho.valor_in("1.01.02"), '"1.01.02"')
        self.assertEqual(sincronizar_espelho.valor_in('a"b'), '"a\\"b"')
        self.assertEqual(sincronizar_espelho.valor_in(123), '"123"')

    def test_todas_as_tabelas_da_checagem_estao_na_sincronizacao(self):
        import checar_saude
        self.assertTrue(set(checar_saude.TABELAS) <= set(sincronizar_espelho.TABELAS))


class ChecagemFinal(unittest.TestCase):
    def test_diferenca_entre_os_bancos_deixa_a_execucao_vermelha(self):
        import checar_saude

        def contar(url, headers, tabela):
            return (100 if tabela == "clientes_grupo" and url == ESPELHO else 200), None
        with mock.patch.dict(os.environ, AMBIENTE), mock.patch.object(checar_saude, "contar", side_effect=contar), \
                mock.patch.object(sys, "argv", ["checar_saude.py"]):
            with self.assertRaises(SystemExit) as fim:
                checar_saude.main()
        self.assertEqual(fim.exception.code, 1)

    def test_bancos_iguais_passam(self):
        import checar_saude
        with mock.patch.dict(os.environ, AMBIENTE), \
                mock.patch.object(checar_saude, "contar", return_value=(200, None)), \
                mock.patch.object(sys, "argv", ["checar_saude.py"]):
            checar_saude.main()


if __name__ == "__main__":
    unittest.main()
