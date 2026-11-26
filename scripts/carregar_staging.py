"""
UNIFACS — Projeto Integrador de Banco de Dados — A3
Time Índice — Grupo 4 | Cenário: USUPORT

carregar_staging.py — ALTERNATIVA ao LOAD DATA LOCAL INFILE do 02_staging.sql.

Use quando o LOAD DATA não puder ser usado (servidor com local_infile=0,
DBeaver sem acesso ao arquivo etc.). Faz exatamente o mesmo trabalho:
cria a tabela stg_acidente_csv (lendo o CREATE TABLE do próprio
02_staging.sql) e insere as 603.215 linhas do CSV, em lotes, com INSERT
parametrizado (executemany). Depois rode 03_carga.sql e 04_validacao.sql.

Credenciais: usa DB_ADMIN_USER/DB_ADMIN_PASSWORD do .env se existirem
(é preciso permissão de CREATE TABLE); senão DB_USER/DB_PASSWORD.

Uso, da raiz do projeto:
    python scripts/carregar_staging.py [caminho_do_csv]
"""

import csv
import os
import re
import sys
import time
from pathlib import Path

import mysql.connector

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "app"))
import db  # noqa: E402

CSV_PADRAO = RAIZ / "dados" / "acidentes2024_todas_causas_tipos_Usuport.csv"
LOTE = 5000


def main() -> None:
    caminho = Path(sys.argv[1]) if len(sys.argv) > 1 else CSV_PADRAO
    cfg = db.configuracao()
    cfg["user"] = os.getenv("DB_ADMIN_USER", cfg["user"])
    cfg["password"] = os.getenv("DB_ADMIN_PASSWORD", cfg["password"])

    # Reaproveita o DROP/CREATE da staging escrito no 02_staging.sql (fonte única).
    sql02 = (RAIZ / "sql" / "02_staging.sql").read_text(encoding="utf-8")
    create = re.search(r"CREATE TABLE stg_acidente_csv \(.*?\n\) ENGINE.*?;", sql02, re.S).group(0)

    cn = mysql.connector.connect(**cfg)
    cur = cn.cursor()
    cur.execute("DROP TABLE IF EXISTS stg_acidente_csv")
    cur.execute(create)

    # Latin-1, ";" como separador, aspas duplas — o mesmo formato do LOAD DATA.
    with open(caminho, encoding="latin-1", newline="") as f:
        leitor = csv.reader(f, delimiter=";", quotechar='"')
        colunas = next(leitor)                          # cabeçalho = nomes das colunas
        sql = (f"INSERT INTO stg_acidente_csv ({', '.join(colunas)}) "
               f"VALUES ({', '.join(['%s'] * len(colunas))})")
        lote, total, inicio = [], 0, time.time()
        for linha in leitor:
            lote.append(linha)
            if len(lote) == LOTE:
                cur.executemany(sql, lote)
                cn.commit()
                total += len(lote)
                lote.clear()
                print(f"\r{total:,} linhas...", end="", flush=True)
        if lote:
            cur.executemany(sql, lote)
            cn.commit()
            total += len(lote)

    cur.execute("SELECT COUNT(*), COUNT(DISTINCT id) FROM stg_acidente_csv")
    linhas, acidentes = cur.fetchone()
    print(f"\nStaging carregada: {linhas:,} linhas, {acidentes:,} acidentes "
          f"em {time.time() - inicio:.0f} s (esperado: 603.215 e 73.156).")
    cur.close()
    cn.close()


if __name__ == "__main__":
    main()
