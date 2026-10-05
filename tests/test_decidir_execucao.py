"""
Testes da decisao de rodar ou nao a carga em cada disparo agendado.

Rodar na raiz do projeto:  python -m unittest discover -s tests -v
"""
import os
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from decidir_execucao import BRASILIA, PRINCIPAL, converter_data, decidir  # noqa: E402

RESERVA = "7 7 * * *"


def brasilia(dia, hora, minuto=0):
    return datetime(2026, 10, dia, hora, minuto, tzinfo=BRASILIA)


class Decidir(unittest.TestCase):
    def test_manual_roda_sempre(self):
        rodar, _, _ = decidir("workflow_dispatch", "", brasilia(5, 9), brasilia(5, 9, 30), 0)
        self.assertTrue(rodar)

    def test_meia_noite_com_dados_de_ontem_roda_sem_aviso(self):
        rodar, _, aviso = decidir("schedule", PRINCIPAL, brasilia(4, 16, 37), brasilia(5, 0, 10), 0)
        self.assertTrue(rodar)
        self.assertIsNone(aviso)

    def test_reserva_sem_carga_hoje_roda_e_avisa(self):
        # a das 00:07 atrasou (ou nao veio) e a reserva chegou antes dela
        rodar, _, aviso = decidir("schedule", RESERVA, brasilia(4, 16, 37), brasilia(5, 4, 10), 0)
        self.assertTrue(rodar)
        self.assertIsNotNone(aviso)

    def test_reserva_nao_repete_se_a_meia_noite_ja_rodou(self):
        rodar, motivo, _ = decidir("schedule", RESERVA, brasilia(5, 0, 40), brasilia(5, 4, 10), 0)
        self.assertFalse(rodar)
        self.assertIn("atualizados hoje", motivo)

    def test_carga_atrasada_ate_a_tarde_nao_engana_a_madrugada_seguinte(self):
        # so 9h30 de diferenca, mas e outro dia: tem que rodar
        rodar, _, _ = decidir("schedule", PRINCIPAL, brasilia(4, 14, 30), brasilia(5, 0, 7), 0)
        self.assertTrue(rodar)

    def test_nao_roda_se_outra_execucao_anterior_esta_em_andamento(self):
        rodar, motivo, _ = decidir("schedule", RESERVA, brasilia(4, 16, 37), brasilia(5, 4, 10), 1)
        self.assertFalse(rodar)
        self.assertIn("rodando", motivo)

    def test_banco_vazio_roda(self):
        rodar, _, _ = decidir("schedule", PRINCIPAL, None, brasilia(5, 0, 10), 0)
        self.assertTrue(rodar)


class ConverterData(unittest.TestCase):
    def test_formatos_que_o_supabase_devolve(self):
        esperado = datetime(2026, 10, 4, 19, 37, 12, tzinfo=timezone.utc)
        for texto in ("2026-10-04T19:37:12.12345+00:00", "2026-10-04T19:37:12.123456+00:00",
                      "2026-10-04T19:37:12+00:00", "2026-10-04T19:37:12Z", "2026-10-04T19:37:12+0000"):
            self.assertEqual(converter_data(texto), esperado, texto)

    def test_fuso_diferente_de_utc(self):
        self.assertEqual(converter_data("2026-10-04T16:37:12-03:00"),
                         datetime(2026, 10, 4, 19, 37, 12, tzinfo=timezone.utc))

    def test_virada_do_dia_em_brasilia(self):
        # 02:00 UTC de 05/10 ainda e 04/10 em Brasilia
        self.assertEqual(converter_data("2026-10-05T02:00:00+00:00").astimezone(BRASILIA).date().day, 4)


if __name__ == "__main__":
    unittest.main()
