"""Baixa e salva respostas JSON da API pública do Cartola.
Execute na raiz do projeto: python carga/baixar_json.py
Por padrão tenta as rodadas 1 a 10; use --inicio e --fim para alterar.
"""
import argparse
import json
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

BASE = "https://api.cartola.globo.com"
PASTA = Path(__file__).resolve().parent / "dados"


def baixar(endpoint: str, nome: str) -> None:
    url = BASE + endpoint
    pedido = Request(url, headers={"User-Agent": "Mozilla/5.0 (compatible; LigaFACOMFantasy/1.0)"})
    try:
        with urlopen(pedido, timeout=40) as resposta:
            dados = json.loads(resposta.read().decode("utf-8"))
    except HTTPError as exc:
        raise RuntimeError(f"A API respondeu HTTP {exc.code} para {url}") from exc
    except URLError as exc:
        raise RuntimeError(f"Não foi possível acessar {url}: {exc.reason}") from exc
    destino = PASTA / nome
    destino.write_text(json.dumps(dados, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"OK  {destino.relative_to(PASTA.parent.parent)}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Salva dados da API Cartola em carga/dados.")
    parser.add_argument("--inicio", type=int, default=1, help="Primeira rodada (padrão: 1)")
    parser.add_argument("--fim", type=int, default=10, help="Última rodada (padrão: 10)")
    args = parser.parse_args()
    if not (1 <= args.inicio <= args.fim <= 38):
        parser.error("Informe rodadas entre 1 e 38, com início menor ou igual ao fim.")
    PASTA.mkdir(parents=True, exist_ok=True)
    endpoints = [
        ("/mercado/status", "mercado_status.json"),
        ("/atletas/mercado", "atletas_mercado.json"),
        ("/esquemas", "esquemas.json"),
    ]
    for rodada in range(args.inicio, args.fim + 1):
        endpoints.extend([
            (f"/partidas/{rodada}", f"partidas_{rodada}.json"),
            (f"/atletas/pontuados/{rodada}", f"pontuados_{rodada}.json"),
        ])
    for indice, (endpoint, nome) in enumerate(endpoints):
        try:
            baixar(endpoint, nome)
        except RuntimeError as exc:
            print(f"ERRO {exc}")
            print("O download foi interrompido. Os arquivos já salvos continuam em carga/dados.")
            raise SystemExit(1)
        if indice < len(endpoints) - 1:
            time.sleep(1)
    print(f"\nConcluído. JSONs salvos em: {PASTA}")


if __name__ == "__main__":
    main()
