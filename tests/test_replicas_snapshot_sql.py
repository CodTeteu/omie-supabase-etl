"""Contrato SQL do marcador; integra somente com PostgreSQL local *_test."""

import os
import unittest
from pathlib import Path
from urllib.parse import urlsplit

DSN = os.environ.get("TEST_DATABASE_URL")


@unittest.skipUnless(DSN, "PostgreSQL de teste local nao configurado")
class SnapshotSQL(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import psycopg
        from psycopg.types.json import Jsonb

        endpoint = urlsplit(DSN)
        if endpoint.hostname not in (
            "localhost",
            "127.0.0.1",
        ) or not endpoint.path.endswith("_test"):
            raise RuntimeError("Integração aceita somente banco local *_test")
        cls.psycopg, cls.Jsonb = psycopg, staticmethod(Jsonb)
        cls.conn = psycopg.connect(DSN, autocommit=True)
        for role in ("anon", "authenticated", "service_role"):
            cls.conn.execute(
                f"CREATE ROLE {role} NOLOGIN"
                + (" BYPASSRLS" if role == "service_role" else "")
            )
        for table in (
            "categorias_omie",
            "departamentos_omie",
            "clientes_grupo",
            "contas_receber_grupo",
            "conta_corrente",
            "movimentos_financeiros",
            "contas_pagar",
            "extrato_bancario",
        ):
            cls.conn.execute(f"CREATE TABLE public.{table} (id integer PRIMARY KEY)")
        cls.conn.execute(
            (Path(__file__).parents[1] / "replicas_snapshot.sql").read_text(
                encoding="utf-8"
            )
        )

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    def setUp(self):
        self.conn.execute("RESET ROLE")
        self.conn.execute(
            "UPDATE public.omie_replica_snapshot SET geracao=0,estado='aguardando',run_id=NULL,tentativa=NULL"
        )
        self.payload = {
            "run_id": 123,
            "tentativa": 1,
            "ciclo": "manha",
            "referencia": "2026-11-13",
            "estado": "concluido",
            "finalizado_em": "2026-11-13T16:00:00Z",
            "geracao": 0,
        }

    def publish(self, **changes):
        return self.conn.execute(
            "SELECT public.publicar_snapshot_omie(%s)",
            (self.Jsonb({**self.payload, **changes}),),
        ).fetchone()[0]

    def test_service_role_can_publish_and_anonymous_cannot_read(self):
        self.conn.execute("SET ROLE service_role")
        self.assertTrue(self.publish()["publicado"])
        self.conn.execute("SET ROLE anon")
        with self.assertRaises(self.psycopg.errors.InsufficientPrivilege):
            self.conn.execute("SELECT * FROM public.omie_replica_snapshot")
        self.conn.execute("RESET ROLE")

    def test_generation_change_blocks_old_publication(self):
        self.publish()
        self.conn.execute(
            "INSERT INTO public.categorias_omie VALUES (1) ON CONFLICT DO NOTHING"
        )
        self.assertEqual(
            self.conn.execute(
                "SELECT estado,geracao FROM public.omie_replica_snapshot"
            ).fetchone(),
            ("aguardando", 1),
        )
        with self.assertRaises(self.psycopg.Error):
            self.publish()
        self.assertTrue(self.publish(geracao=1)["publicado"])

    def test_data_and_invalidation_rollback_together(self):
        self.publish()
        self.conn.execute("BEGIN")
        self.conn.execute("UPDATE public.categorias_omie SET id=id")
        self.assertEqual(
            self.conn.execute(
                "SELECT estado FROM public.omie_replica_snapshot"
            ).fetchone()[0],
            "aguardando",
        )
        self.conn.execute("ROLLBACK")
        self.assertEqual(
            self.conn.execute(
                "SELECT estado FROM public.omie_replica_snapshot"
            ).fetchone()[0],
            "pronto",
        )

    def test_incomplete_and_older_attempt_are_rejected(self):
        for value in (None, "falhou", "executando"):
            with self.assertRaises(self.psycopg.Error):
                self.publish(estado=value)
        self.publish(tentativa=2)
        with self.assertRaises(self.psycopg.Error):
            self.publish()


if __name__ == "__main__":
    unittest.main()
