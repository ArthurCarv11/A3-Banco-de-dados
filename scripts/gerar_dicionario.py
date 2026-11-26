"""
UNIFACS — Projeto Integrador de Banco de Dados — A3
Time Índice — Grupo 4 | Cenário: USUPORT

gerar_dicionario.py — gera docs/dicionario_dados.md lendo o INFORMATION_SCHEMA
do MySQL (o dicionário sai do banco real, não de uma cópia manual).

Para cada tabela: finalidade (COMMENT da tabela), colunas com tipo, nulidade,
chave, padrão e finalidade (COMMENT da coluna), restrições CHECK, chaves
estrangeiras e índices.

Uso (da raiz do projeto, com o .env configurado):
    python scripts/gerar_dicionario.py
"""

import sys
from collections import defaultdict
from pathlib import Path

import pandas as pd

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "app"))
import db  # noqa: E402  (reaproveita a conexão configurada pelo .env)


def corrigir_acentos(texto: str) -> str:
    """O MySQL 8 devolve INFORMATION_SCHEMA.CHECK_CONSTRAINTS.CHECK_CLAUSE com
    os acentos codificados duas vezes ('Ã“bito' em vez de 'Óbito'); a
    restrição em si está correta (veja SHOW CREATE TABLE). Desfaz a dupla
    codificação só para exibir."""
    try:
        return texto.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return texto

ORDEM = ["superintendencia", "delegacia", "uop", "cidade", "condicao_meteorologica", "fase_dia",
         "causa", "tipo_acidente", "tracado", "tipo_veiculo", "acidente", "causa_acidente",
         "acidente_tipo", "acidente_tracado", "veiculo", "pessoa"]


def main() -> None:
    tabelas = db.consultar("""
        SELECT table_name AS tabela, table_comment AS finalidade
          FROM information_schema.tables
         WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'
    """).set_index("tabela")["finalidade"].to_dict()

    colunas = db.consultar("""
        SELECT table_name AS tabela, column_name AS coluna, column_type AS tipo,
               is_nullable AS nulo, column_key AS chave, column_default AS padrao,
               extra AS extra, column_comment AS finalidade, ordinal_position AS pos
          FROM information_schema.columns
         WHERE table_schema = DATABASE()
         ORDER BY table_name, ordinal_position
    """)

    checks = db.consultar("""
        SELECT tc.table_name AS tabela, cc.constraint_name AS nome, cc.check_clause AS regra
          FROM information_schema.check_constraints cc
          JOIN information_schema.table_constraints tc
            ON tc.constraint_schema = cc.constraint_schema
           AND tc.constraint_name   = cc.constraint_name
         WHERE cc.constraint_schema = DATABASE()
         ORDER BY tc.table_name, cc.constraint_name
    """)

    fks = db.consultar("""
        SELECT k.table_name AS tabela, k.constraint_name AS nome,
               GROUP_CONCAT(k.column_name ORDER BY k.ordinal_position) AS colunas,
               k.referenced_table_name AS ref_tabela,
               GROUP_CONCAT(k.referenced_column_name ORDER BY k.ordinal_position) AS ref_colunas,
               r.delete_rule AS ao_excluir
          FROM information_schema.key_column_usage k
          JOIN information_schema.referential_constraints r
            ON r.constraint_schema = k.constraint_schema AND r.constraint_name = k.constraint_name
         WHERE k.table_schema = DATABASE() AND k.referenced_table_name IS NOT NULL
         GROUP BY k.table_name, k.constraint_name, k.referenced_table_name, r.delete_rule
         ORDER BY k.table_name, k.constraint_name
    """)

    indices = db.consultar("""
        SELECT table_name AS tabela, index_name AS nome, non_unique AS non_unique,
               GROUP_CONCAT(column_name ORDER BY seq_in_index) AS colunas
          FROM information_schema.statistics
         WHERE table_schema = DATABASE()
         GROUP BY table_name, index_name, non_unique
         ORDER BY table_name, index_name
    """)

    col_fk = defaultdict(set)
    for r in fks.itertuples():
        for c in r.colunas.split(","):
            col_fk[r.tabela].add(c)

    linhas = [
        "# Dicionário de dados — banco `usuport`",
        "",
        "> Time Índice — Grupo 4 · Cenário USUPORT. Gerado automaticamente por "
        "`scripts/gerar_dicionario.py` a partir do `INFORMATION_SCHEMA` do MySQL; as finalidades "
        "são os `COMMENT` definidos no `sql/01_ddl.sql`.",
        "",
        "Legenda da coluna **Chave**: PK = chave primária · FK = chave estrangeira · "
        "UQ = participa de restrição UNIQUE · IX = indexada. "
        "**Nulo**: NÃO = `NOT NULL`.",
        "",
        "## Visão geral",
        "",
        "| # | Tabela | Finalidade |",
        "|---|---|---|",
    ]
    for i, t in enumerate(ORDEM, start=1):
        linhas.append(f"| {i} | `{t}` | {tabelas.get(t, '')} |")
    linhas.append("")

    for i, t in enumerate(ORDEM, start=1):
        linhas += [f"## {i}. `{t}`", "", f"**Finalidade:** {tabelas.get(t, '')}", "",
                   "| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |",
                   "|---|---|---|---|---|---|"]
        for c in colunas[colunas.tabela == t].itertuples():
            chave = {"PRI": "PK", "UNI": "UQ", "MUL": "IX"}.get(c.chave, "")
            if c.coluna in col_fk[t]:
                chave = (chave + " FK").strip() if chave != "IX" else "FK"
            extra = " ".join(x for x in [
                f"padrão {c.padrao}" if pd.notna(c.padrao) else "",
                (c.extra or "").replace("DEFAULT_GENERATED", "").replace("VIRTUAL GENERATED",
                                                                         "gerada (virtual)").strip()
            ] if x)
            linhas.append(f"| `{c.coluna}` | {c.tipo} | {'SIM' if c.nulo == 'YES' else 'NÃO'} | "
                          f"{chave} | {extra} | {c.finalidade} |")
        linhas.append("")

        fk_t = fks[fks.tabela == t]
        if not fk_t.empty:
            linhas += ["**Chaves estrangeiras**", ""]
            for r in fk_t.itertuples():
                linhas.append(f"- `{r.nome}`: ({r.colunas}) → `{r.ref_tabela}` ({r.ref_colunas}), "
                              f"ON DELETE {r.ao_excluir}")
            linhas.append("")

        ck_t = checks[checks.tabela == t]
        if not ck_t.empty:
            linhas += ["**Restrições CHECK**", ""]
            for r in ck_t.itertuples():
                regra = corrigir_acentos(r.regra).replace("`", "").replace("_utf8mb4", "").replace("\\'", "'")
                linhas.append(f"- `{r.nome}`: `{regra}`")
            linhas.append("")

        ix_t = indices[indices.tabela == t]
        if not ix_t.empty:
            linhas += ["**Índices**", ""]
            for r in ix_t.itertuples():
                tipo = "PRIMARY KEY" if r.nome == "PRIMARY" else ("UNIQUE" if r.non_unique == 0
                                                                  else "índice")
                linhas.append(f"- `{r.nome}` ({tipo}): {r.colunas}")
            linhas.append("")

    destino = RAIZ / "docs" / "dicionario_dados.md"
    destino.write_text("\n".join(linhas), encoding="utf-8")
    print(f"Gerado: {destino} ({len(colunas)} colunas, {len(checks)} CHECKs, {len(fks)} FKs)")


if __name__ == "__main__":
    main()
