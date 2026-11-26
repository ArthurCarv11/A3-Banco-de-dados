"""
UNIFACS — Projeto Integrador de Banco de Dados — A3
Time Índice — Grupo 4 | Cenário: USUPORT

empacotar_entrega.py — gera entrega/A3_TimeIndice_Grupo4_USUPORT.zip com o
que o edital pede (relatório PDF, scripts SQL, código da aplicação, pasta de
certificados) e o necessário para reproduzir.

Ficam de fora: .env (senha), o CSV descompactado de 222 MB (vai o .csv.gz de
13 MB), caches do Python e arquivos locais de ferramentas.

Uso, da raiz do projeto:
    python scripts/empacotar_entrega.py
"""

import zipfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
NOME = "A3_TimeIndice_Grupo4_USUPORT"
INCLUIR = ["README.md", "requirements.txt", ".env.example", ".gitignore",
           "sql", "app", "scripts", "docs", "certificados", "dados/README.md",
           "dados/acidentes2024_todas_causas_tipos_Usuport.csv.gz"]   # CSV compactado (13 MB)
EXCLUIR_NOMES = {"__pycache__", ".env", "relatorio.html"}
EXCLUIR_SUFIXOS = {".pyc", ".csv"}


def arquivos():
    for item in INCLUIR:
        caminho = RAIZ / item
        candidatos = [caminho] if caminho.is_file() else sorted(caminho.rglob("*"))
        for arq in candidatos:
            if (arq.is_file() and not EXCLUIR_NOMES.intersection(arq.relative_to(RAIZ).parts)
                    and arq.suffix not in EXCLUIR_SUFIXOS):
                yield arq


def main() -> None:
    destino = RAIZ / "entrega" / f"{NOME}.zip"
    destino.parent.mkdir(exist_ok=True)
    lista = list(arquivos())
    with zipfile.ZipFile(destino, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for arq in lista:
            z.write(arq, f"{NOME}/{arq.relative_to(RAIZ).as_posix()}")
    print(f"Gerado: {destino} — {len(lista)} arquivos, {destino.stat().st_size / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    main()
