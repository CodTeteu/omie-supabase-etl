"""Conferencia somente de leitura da rede Actions -> Rundeck."""
import os
import sys

import requests


def main():
    base = os.environ["RUNDECK_URL"].rstrip("/")
    if not base.startswith("https://"):
        raise RuntimeError("Rundeck deve usar HTTPS")
    session = requests.Session()
    response = session.get(base + "/user/login", timeout=25, allow_redirects=False)
    print(f"Pagina de login: HTTP {response.status_code}")
    if response.status_code != 200:
        return 1
    response = session.post(base + "/j_security_check", data={
        "j_username": os.environ["RUNDECK_USERNAME"],
        "j_password": os.environ["RUNDECK_PASSWORD"],
    }, timeout=25, allow_redirects=False)
    print(f"Autenticacao: HTTP {response.status_code}")
    if response.status_code not in (200, 302):
        return 1
    response = session.get(base + "/api/45/projects", headers={"Accept": "application/json"},
                           timeout=25, allow_redirects=False)
    print(f"API de projetos: HTTP {response.status_code}")
    if response.status_code != 200:
        return 1
    projects = response.json()
    available = any(p.get("name") == "DATALAKE_COMERCIAL" for p in projects)
    print(f"Projeto Data Lake acessivel: {available}")
    return 0 if available else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except requests.RequestException:
        raise SystemExit("Conexao Actions/Rundeck indisponivel") from None
