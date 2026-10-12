"""
Testes da consulta diaria ao banco das aprovacoes do BI de Repasse (checar_saude.py).

Rodar na raiz do projeto:  python -m unittest discover -s tests -v
Sem rede: as respostas sao simuladas.
"""
import os
import sys
import unittest
from unittest import mock

import requests

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import checar_saude  # noqa: E402

CONFIG = {"APROVACOES_URL": "https://aprovacoes.supabase.co/", "APROVACOES_KEY": "chave-publica"}


def resposta(status, texto=""):
    r = mock.Mock()
    r.status_code = status
    r.text = texto
    return r


def contagem(total):
    r = resposta(206)
    r.headers = {"Content-Range": f"0-0/{total}"}
    return r


class Contar(unittest.TestCase):
    """Em 11/10/2026 a contagem de contas_pagar estourou o limite da API logo depois da carga."""

    def test_tempo_esgotado_repete_e_conta(self):
        estouro = resposta(500, '{"code":"57014","message":"canceling statement due to statement timeout"}')
        with mock.patch.object(checar_saude.requests, "get", side_effect=[estouro, contagem(70395)]) as get, \
             mock.patch.object(checar_saude.time, "sleep") as dormir:
            self.assertEqual(checar_saude.contar("https://x", {}, "contas_pagar"), (70395, None))
        self.assertEqual(get.call_count, 2)
        dormir.assert_called_once_with(15)

    def test_erro_de_permissao_nao_repete(self):
        with mock.patch.object(checar_saude.requests, "get", return_value=resposta(401, "Invalid API key")) as get, \
             mock.patch.object(checar_saude.time, "sleep"):
            total, problema = checar_saude.contar("https://x", {}, "contas_pagar")
        self.assertIsNone(total)
        self.assertIn("401", problema)
        self.assertEqual(get.call_count, 1)

    def test_rede_fora_tres_vezes_devolve_o_problema(self):
        with mock.patch.object(checar_saude.requests, "get", side_effect=requests.ConnectionError("fora")) as get, \
             mock.patch.object(checar_saude.time, "sleep"):
            total, problema = checar_saude.contar("https://x", {}, "contas_pagar")
        self.assertIsNone(total)
        self.assertIn("fora", problema)
        self.assertEqual(get.call_count, 3)


class ManterAprovacoesAtivo(unittest.TestCase):
    def test_sem_configuracao_nao_consulta(self):
        with mock.patch.dict(os.environ, {}, clear=True), \
             mock.patch.object(checar_saude.requests, "get") as get:
            self.assertIsNone(checar_saude.manter_aprovacoes_ativo())
        get.assert_not_called()

    def test_respondeu_na_primeira(self):
        with mock.patch.dict(os.environ, CONFIG), \
             mock.patch.object(checar_saude.requests, "get", return_value=resposta(200)) as get:
            self.assertIsNone(checar_saude.manter_aprovacoes_ativo())
        url = get.call_args[0][0]
        self.assertEqual(url, "https://aprovacoes.supabase.co/rest/v1/repasse_aprovacoes?select=*&limit=1")
        self.assertEqual(get.call_args[1]["headers"], {"apikey": "chave-publica"})

    def test_instabilidade_passageira_nao_e_problema(self):
        respostas = [requests.ConnectionError("reset"), resposta(503), resposta(200)]
        with mock.patch.dict(os.environ, CONFIG), \
             mock.patch.object(checar_saude.requests, "get", side_effect=respostas) as get, \
             mock.patch.object(checar_saude.time, "sleep"):
            self.assertIsNone(checar_saude.manter_aprovacoes_ativo())
        self.assertEqual(get.call_count, 3)

    def test_projeto_pausado_devolve_o_problema(self):
        with mock.patch.dict(os.environ, CONFIG), \
             mock.patch.object(checar_saude.requests, "get", return_value=resposta(540, "project paused")) as get, \
             mock.patch.object(checar_saude.time, "sleep"):
            problema = checar_saude.manter_aprovacoes_ativo()
        self.assertIn("540", problema)
        self.assertEqual(get.call_count, 3)


if __name__ == "__main__":
    unittest.main()
