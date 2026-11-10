"""Regressoes das janelas, liberacao do BI e conciliacao de envios sem resposta."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock
from datetime import datetime, timezone

import requests

import atualizar_powerbi as bi
import controle_execucao as controle
import decidir_execucao as decisao
import gravacao


def local(hora, minuto=0, dia=11):
    return datetime(2026, 11, dia, hora, minuto, tzinfo=controle.BRASILIA)


def fonte(estado="concluido"):
    carga = {"run_id": 40, "tentativa": 1, "estado": estado,
             "iniciado_em": "2026-11-11T14:00:00Z", "finalizado_em": "2026-11-11T16:00:00Z"}
    return {"execucao": carga, "ultima_carga": dict(carga), "powerbi": []}


MODELO = {"id": "modelo-1", "name": "Painel_Financeiro", "workspace_id": "workspace-1"}


def refresh(request_id, status, erro=None):
    return {"requestId": request_id, "status": status, "startTime": "2026-11-11T17:00:01Z",
            "endTime": "2026-11-11T17:01:00Z" if status in bi.TERMINAIS else None,
            "serviceExceptionJson": erro}


class Janelas(unittest.TestCase):
    def test_carga_noturna_nao_substitui_as_duas_cargas_diurnas(self):
        self.assertTrue(decisao.decidir("workflow_dispatch", True, local(0), local(11), 0, "manha")[0])
        self.assertTrue(decisao.decidir("workflow_dispatch", True, local(11), local(15), 0, "tarde")[0])

    def test_cada_ciclo_tem_uma_referencia_independente(self):
        self.assertEqual(controle.inicio_ciclo(local(2), "noturna"), local(20, dia=10))
        self.assertEqual(controle.inicio_ciclo(local(13), "manha"), local(11))
        self.assertEqual(controle.inicio_ciclo(local(18), "tarde"), local(15))

    def test_disparo_atrasado_da_manha_nao_inicia_carga_apos_as_15h(self):
        self.assertFalse(decisao.decidir("schedule", False, None, local(15), 0, "manha")[0])
        self.assertFalse(decisao.decidir("schedule", False, None, local(22), 0, "tarde")[0])

    def test_fim_de_semana_e_antes_do_horario_nao_rodam(self):
        self.assertFalse(decisao.decidir("workflow_dispatch", True, None, local(10), 0, "manha")[0])
        self.assertFalse(decisao.decidir("workflow_dispatch", True, None, local(15, dia=14), 0, "tarde")[0])

    def test_segunda_rodada_aguarda_a_fila_em_vez_de_ser_descartada(self):
        self.assertTrue(decisao.decidir("workflow_dispatch", True, None, local(15), 1, "tarde")[0])

    def test_reservas_tardias_seguem_o_ciclo_do_cron(self):
        self.assertEqual(decisao.ciclo_do_disparo("schedule", "7 14 * * 1-5", "noturna"), "manha")
        self.assertEqual(decisao.ciclo_do_disparo("schedule", "7 18 * * 1-5", "noturna"), "tarde")

    def test_horarios_do_powerbi_em_utc(self):
        self.assertEqual(controle.horario_powerbi("manha", "2026-11-11").astimezone(timezone.utc).hour, 17)
        self.assertEqual(controle.horario_powerbi("tarde", "2026-11-11").astimezone(timezone.utc).hour, 21)

    def test_resultado_parcial_nao_e_usado_como_carga_concluida(self):
        with self.assertRaises(RuntimeError):
            controle.validar_fonte(fonte("falhou"))

    def test_carga_mais_nova_bloqueia_retomada_do_bi_antigo(self):
        estado = fonte()
        estado["ultima_carga"]["run_id"] = 41
        with self.assertRaises(RuntimeError):
            controle.validar_fonte(estado)

    def test_carga_completa_ainda_pode_ter_powerbi_pendente(self):
        self.assertTrue(decisao.powerbi_pendente({"powerbi": []}))
        nomes = bi.config()["modelos"]
        self.assertFalse(decisao.powerbi_pendente({"powerbi": [{"nome": n, "estado": "concluido"} for n in nomes]}))

    def test_agenda_futura_nao_dispara_pela_reserva(self):
        estado = {"agenda": {"ativo": True, "inicio_em": "2026-11-12"}}
        ambiente = {"EVENTO": "schedule", "DISPARO": "7 14 * * 1-5", "CICLO": "noturna"}
        with mock.patch.dict(os.environ, ambiente, clear=True), \
             mock.patch.object(decisao, "consultar", return_value=estado), \
             mock.patch.object(decisao, "contar_anteriores_em_andamento", return_value=0), \
             mock.patch.object(decisao, "output") as output, \
             mock.patch.object(decisao, "datetime") as clock:
            clock.now.return_value = local(11)
            decisao.main()
        self.assertIn(mock.call("rodar", "false"), output.call_args_list)

    def test_reserva_da_manha_nao_cancela_a_fila_da_tarde_por_bi_pendente(self):
        estado = fonte()
        estado["agenda"] = {"ativo": True, "inicio_em": "2026-11-11"}
        ambiente = {"EVENTO": "schedule", "DISPARO": "7 14 * * 1-5"}
        with mock.patch.dict(os.environ, ambiente, clear=True), \
             mock.patch.object(decisao, "consultar", return_value=estado), \
             mock.patch.object(decisao, "contar_anteriores_em_andamento", return_value=1), \
             mock.patch.object(decisao, "output") as output, \
             mock.patch.object(decisao, "datetime") as clock:
            clock.now.return_value = local(15, 5)
            clock.strptime.side_effect = datetime.strptime
            decisao.main()
        self.assertIn(mock.call("rodar", "false"), output.call_args_list)

    def test_noite_aguarda_ciclo_diurno_que_ainda_esta_terminando(self):
        ambiente = {"EVENTO": "workflow_dispatch", "AGENDADOR": "true", "CICLO": "noturna"}
        with mock.patch.dict(os.environ, ambiente, clear=True), \
             mock.patch.object(decisao, "consultar", return_value={}), \
             mock.patch.object(decisao, "contar_anteriores_em_andamento", return_value=1), \
             mock.patch.object(decisao, "output") as output, \
             mock.patch.object(decisao, "datetime") as clock:
            clock.now.return_value = local(22)
            decisao.main()
        self.assertIn(mock.call("rodar", "true"), output.call_args_list)


class Completude(unittest.TestCase):
    def test_registro_incompleto_impede_liberacao_mesmo_com_etapas_verdes(self):
        with tempfile.TemporaryDirectory() as pasta:
            arquivo = Path(pasta) / "incompleto.jsonl"
            ambiente = {"ETL_INCOMPLETUDE_ARQUIVO": str(arquivo), "ETL_SUCESSO": "true"}
            with mock.patch.dict(os.environ, ambiente):
                self.assertFalse(gravacao.extracao_completa("Clientes", {"empresa": "Teste"}, 9, 10))
                with mock.patch("sys.argv", ["controle_execucao.py", "finalizar"]), \
                     mock.patch.object(controle, "registrar") as registrar, \
                     mock.patch.object(controle, "output"), mock.patch.object(controle, "resumo"):
                    with self.assertRaises(SystemExit):
                        controle.main()
                    registrar.assert_called_once_with("falhou")
            self.assertEqual(json.loads(arquivo.read_text())["baixados"], 9)


class Atualizacoes(unittest.TestCase):
    def setUp(self):
        self.rpc = mock.patch.object(controle, "rpc", return_value={}).start()
        self.sleep = mock.patch.object(bi.time, "sleep").start()
        self.clock = mock.patch.object(controle, "agora", return_value=local(14)).start()
        self.api = mock.Mock()
        self.api.atualizar.return_value = mock.Mock(status_code=202, headers={})
        self.rodada = bi.Rodada(self.api, "manha", "2026-11-11", fonte())
        self.addCleanup(mock.patch.stopall)

    def test_sucesso_fica_registrado_e_nao_e_reenviado(self):
        self.api.historico.side_effect = [[], [refresh("id-1", "Completed")]]
        self.assertEqual(self.rodada.processar(MODELO), "concluido")
        self.assertEqual(self.rodada.processar(MODELO), "ja concluido")
        self.api.atualizar.assert_called_once()

    def test_resposta_perdida_e_conciliada_sem_repetir_post(self):
        self.api.atualizar.side_effect = requests.Timeout()
        self.api.historico.side_effect = [[], [refresh("id-1", "Unknown")], [refresh("id-1", "Completed")]]
        self.assertEqual(self.rodada.processar(MODELO), "concluido")
        self.api.atualizar.assert_called_once()

    def test_retomada_segue_o_request_id_salvo(self):
        self.rodada.estados[MODELO["id"]] = {"estado": "executando", "request_id": "id-1",
            "anteriores": [], "tentativas": 1, "submetido_em": "2026-11-11T17:00:00Z"}
        self.api.historico.return_value = [refresh("id-1", "Completed")]
        self.assertEqual(self.rodada.processar(MODELO), "concluido")
        self.api.atualizar.assert_not_called()

    def test_erro_transitorio_repete_uma_vez_neste_ciclo(self):
        falha = refresh("id-1", "Failed", "EMAXCONNSESSION")
        self.api.historico.side_effect = [[], [falha], [falha], [refresh("id-2", "Completed"), falha]]
        self.assertEqual(self.rodada.processar(MODELO), "concluido")
        self.assertEqual(self.api.atualizar.call_count, 2)
        self.assertEqual(self.rodada.estados[MODELO["id"]]["tentativas"], 2)

    def test_credencial_invalida_nao_e_repetida(self):
        self.api.historico.side_effect = [[], [refresh("id-1", "Failed", "Invalid credentials timeout")]]
        with self.assertRaises(RuntimeError):
            self.rodada.processar(MODELO)
        self.api.atualizar.assert_called_once()

    def test_oito_solicitacoes_no_dia_impedem_novo_envio(self):
        linhas = [refresh(str(i), "Completed") for i in range(8)]
        with self.assertRaises(RuntimeError):
            self.rodada.enviar(MODELO, linhas)
        self.api.atualizar.assert_not_called()

    def test_corte_espera_a_carga_que_atrasou(self):
        estado = fonte()
        estado["execucao"]["finalizado_em"] = "2026-11-11T17:45:00Z"
        rodada = bi.Rodada(self.api, "manha", "2026-11-11", estado)
        self.assertEqual(rodada.corte, datetime(2026, 11, 11, 17, 45, tzinfo=timezone.utc))

    def test_cancelamento_do_usuario_nao_e_repetido(self):
        self.assertFalse(bi.pode_repetir("CancelledByUser timeout"))


if __name__ == "__main__":
    unittest.main()
