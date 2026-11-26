"""
UNIFACS — Projeto Integrador de Banco de Dados — A3
Time Índice — Grupo 4 | Cenário: USUPORT

montar_sql_completo.py — concatena sql/01_ddl.sql ... sql/07_views.sql em
sql/00_completo.sql (o edital aceita pacote SQL único ou modular; entregamos
os dois). Rode sempre que alterar um dos scripts modulares.

Uso, da raiz do projeto:
    python scripts/montar_sql_completo.py
"""

from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
PARTES = ["01_ddl.sql", "02_staging.sql", "03_carga.sql", "04_validacao.sql",
          "05_dml_exemplos.sql", "06_dql_consultas.sql", "07_views.sql",
          "08_rotinas.sql"]       # procedures e triggers (versão 2); entra só se existir

CABECALHO = """-- =============================================================================
--  UNIFACS — Campus CTN, Salvador
--  UC Projeto Integrador de Banco de Dados — Avaliação A3
--  Professores: Sergio Spinola e Alexandre Anunciação
--  Equipe: Time Índice — Grupo 4 | Cenário: USUPORT
--
--  Arquivo: 00_completo.sql — PACOTE SQL ÚNICO (DDL + carga + validação +
--  DML + DQL + views + rotinas). Gerado por scripts/montar_sql_completo.py a
--  partir dos scripts modulares 01..08 (não edite este arquivo diretamente).
--
--  Execução (da RAIZ do projeto, com o CSV em dados/), SEMPRE como root:
--  criar trigger com o log binário ligado (padrão do MySQL 8) exige SUPER.
--     mysql --local-infile=1 --default-character-set=utf8mb4 -u root -p < sql/00_completo.sql
--  Na VM Ubuntu:  sudo mysql --local-infile=1 --default-character-set=utf8mb4 < sql/00_completo.sql
-- =============================================================================
"""


def main() -> None:
    blocos = [CABECALHO]
    for nome in PARTES:
        if not (RAIZ / "sql" / nome).exists():
            continue
        texto = (RAIZ / "sql" / nome).read_text(encoding="utf-8").rstrip() + "\n"
        blocos.append(f"\n\n-- #############################################################################\n"
                      f"-- ##  {nome}\n"
                      f"-- #############################################################################\n\n"
                      + texto)
    destino = RAIZ / "sql" / "00_completo.sql"
    destino.write_text("".join(blocos), encoding="utf-8")
    print(f"Gerado: {destino} ({sum(b.count(chr(10)) for b in blocos)} linhas)")


if __name__ == "__main__":
    main()
