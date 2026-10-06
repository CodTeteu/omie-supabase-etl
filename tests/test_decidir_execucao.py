"""
Testes da decisao de rodar ou nao a carga em cada disparo (agendador do Supabase, reservas do GitHub, manual).

Rodar na raiz do projeto:  python -m unittest discover -s tests -v
"""
import os
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from decidir_execucao import BRASILIA, converter_data, decidir, inicio_da_noite  # noqa: E402

AGENDADO = "schedule"           # disparo do agendamento do GitHub (reserva)
API = "workflow_dispatch"       # disparo pela API: manual, ou do agendador do Supabase


def brasilia(dia, hora, minuto=0):
    return datetime(2026, 10, dia, hora, minuto, tzinfo=BRASILIA)


class Decidir(unittest.TestCase):
    def test_manual_roda_sempre(self):
        rodar, _, _ = decidir(API, False, brasilia(5, 22, 30), brasilia(5, 23), 0)
        self.assertTrue(rodar)

    def test_agendador_das_22h_roda_se_a_ultima_carga_e_da_noite_anterior(self):
        rodar, _, aviso = decidir(API, True, brasilia(5, 9, 22), brasilia(5, 22, 0), 0)
        self.assertTrue(rodar)
        self.assertIsNone(aviso)

    def test_agendador_segue_as_regras_e_nao_repete_a_carga_da_noite(self):
        # a segunda tentativa das 22:30 nao pode fazer outra carga
        rodar, motivo, _ = decidir(API, True, brasilia(5, 22, 20), brasilia(5, 22, 30), 0)
        self.assertFalse(rodar)
        self.assertIn("ja feita", motivo)

    def test_reserva_do_github_de_manha_nao_repete_a_carga_das_22h(self):
        # o GitHub entrega o disparo das 22:07 so as 07:05 do dia seguinte
        rodar, motivo, _ = decidir(AGENDADO, False, brasilia(5, 22, 20), brasilia(6, 7, 5), 0)
        self.assertFalse(rodar)
        self.assertIn("ja feita", motivo)

    def test_reserva_do_github_roda_e_avisa_se_o_agendador_nao_disparou(self):
        rodar, _, aviso = decidir(AGENDADO, False, brasilia(5, 9, 22), brasilia(6, 3, 10), 0)
        self.assertTrue(rodar)
        self.assertIsNotNone(aviso)

    def test_carga_atrasada_ate_a_tarde_nao_engana_a_noite_seguinte(self):
        # so 5h30 de diferenca, mas a noite de carga recomeca as 20:00
        rodar, _, _ = decidir(API, True, brasilia(5, 16, 30), brasilia(5, 22, 0), 0)
        self.assertTrue(rodar)

    def test_a_noite_vira_as_20h(self):
        self.assertTrue(decidir(API, True, brasilia(5, 19, 59), brasilia(5, 20, 1), 0)[0])
        self.assertFalse(decidir(AGENDADO, False, brasilia(5, 20, 1), brasilia(6, 19, 59), 0)[0])

    def test_nao_roda_se_outra_execucao_anterior_esta_em_andamento(self):
        rodar, motivo, _ = decidir(AGENDADO, False, brasilia(4, 16, 37), brasilia(5, 4, 10), 1)
        self.assertFalse(rodar)
        self.assertIn("rodando", motivo)

    def test_agendador_tambem_espera_a_execucao_em_andamento(self):
        rodar, _, _ = decidir(API, True, None, brasilia(5, 22, 30), 1)
        self.assertFalse(rodar)

    def test_banco_vazio_roda(self):
        rodar, _, _ = decidir(AGENDADO, False, None, brasilia(5, 0, 10), 0)
        self.assertTrue(rodar)


class InicioDaNoite(unittest.TestCase):
    def test_antes_e_depois_das_20h(self):
        self.assertEqual(inicio_da_noite(brasilia(5, 21)), brasilia(5, 20))
        self.assertEqual(inicio_da_noite(brasilia(6, 3)), brasilia(5, 20))
        self.assertEqual(inicio_da_noite(brasilia(6, 19, 59)), brasilia(5, 20))

    def test_hora_em_utc(self):
        # 00:30 UTC de 06/10 = 21:30 de 05/10 em Brasilia
        self.assertEqual(inicio_da_noite(datetime(2026, 10, 6, 0, 30, tzinfo=timezone.utc)), brasilia(5, 20))


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
