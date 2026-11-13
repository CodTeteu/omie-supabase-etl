"""O produtor somente libera uma carga completa; respostas HTTP sao sinteticas."""

import os
import unittest
from unittest.mock import Mock, patch

import publicar_snapshot_replicas as replicas


class PublicarSnapshot(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(
            os.environ,
            {
                "REPLICAS_ATIVAS": "true",
                "SUPABASE_URL_ESPELHO": "https://fixture.invalid",
                "SUPABASE_KEY_ESPELHO": "fixture-key",
                "CICLO": "manha",
                "REFERENCIA": "2026-11-13",
            },
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.carga = {
            "run_id": 123,
            "tentativa": 1,
            "estado": "concluido",
            "finalizado_em": "2026-11-13T16:30:00Z",
        }
        self.estado = {"execucao": self.carga, "ultima_carga": self.carga}

    @patch("publicar_snapshot_replicas.snapshot")
    def test_disabled_does_not_use_network(self, snapshot):
        with patch.dict(os.environ, {"REPLICAS_ATIVAS": "false"}):
            self.assertFalse(replicas.pendente(self.estado))
            replicas.main()
        snapshot.assert_not_called()

    @patch("publicar_snapshot_replicas.snapshot")
    def test_incomplete_or_superseded_cycle_is_not_published(self, snapshot):
        for state in ({}, {"execucao": self.carga, "ultima_carga": {"run_id": 999}}):
            self.assertFalse(replicas.pendente(state))
        snapshot.assert_not_called()

    @patch("publicar_snapshot_replicas.snapshot")
    def test_pending_publication_can_resume_without_extracting(self, snapshot):
        snapshot.return_value = {"estado": "aguardando", "run_id": 123, "tentativa": 1}
        self.assertTrue(replicas.pendente(self.estado))
        snapshot.return_value["estado"] = "pronto"
        self.assertFalse(replicas.pendente(self.estado))
        snapshot.return_value["tentativa"] = 2
        self.assertTrue(replicas.pendente(self.estado))

    @patch("publicar_snapshot_replicas.requests.post")
    @patch("publicar_snapshot_replicas.snapshot", return_value={"geracao": 77})
    @patch("publicar_snapshot_replicas.consultar")
    def test_publish_contains_cycle_generation_and_complete_proof(
        self, consultar, snapshot, post
    ):
        consultar.return_value = self.estado
        post.return_value = Mock(status_code=200)
        replicas.main()
        dados = post.call_args.kwargs["json"]["p_dados"]
        self.assertEqual(
            (dados["run_id"], dados["geracao"], dados["ciclo"]), (123, 77, "manha")
        )
        self.assertEqual(dados["estado"], "concluido")

    @patch("publicar_snapshot_replicas.requests.post")
    @patch("publicar_snapshot_replicas.snapshot", return_value={"geracao": 77})
    @patch("publicar_snapshot_replicas.consultar")
    def test_new_complete_run_blocks_old_publication(self, consultar, snapshot, post):
        newer = {**self.carga, "run_id": 124}
        consultar.side_effect = [
            self.estado,
            {"execucao": newer, "ultima_carga": newer},
        ]
        with self.assertRaises(RuntimeError):
            replicas.main()
        post.assert_not_called()

    @patch("publicar_snapshot_replicas.requests.post")
    @patch("publicar_snapshot_replicas.snapshot", return_value={"geracao": 77})
    @patch("publicar_snapshot_replicas.consultar")
    def test_http_generation_rejection_fails_visibly(self, consultar, snapshot, post):
        consultar.return_value = self.estado
        post.return_value = Mock(status_code=400)
        with self.assertRaises(RuntimeError):
            replicas.main()
        self.assertEqual(post.call_count, 1)


if __name__ == "__main__":
    unittest.main()
