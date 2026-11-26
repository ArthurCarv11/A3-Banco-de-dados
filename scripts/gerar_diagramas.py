"""
UNIFACS — Projeto Integrador de Banco de Dados — A3
Time Índice — Grupo 4 | Cenário: USUPORT

gerar_diagramas.py — gera os diagramas do relatório com Graphviz:

  docs/der_conceitual.dot/.png  DER conceitual (notação de Chen): entidades,
                                relacionamentos, atributos-chave (sublinhados),
                                multivalorados (elipse dupla), compostos
                                (atributo com sub-atributos), derivados
                                (tracejados) e cardinalidades.
  docs/der_logico.dot/.png      Modelo lógico (tabelas, colunas, PK/FK e
                                cardinalidade pé-de-galinha), lido do
                                INFORMATION_SCHEMA do banco real.

Renderização: usa o "dot" local se existir; senão roda o Graphviz num
contêiner Docker (alpine). Uso, da raiz do projeto:
    python scripts/gerar_diagramas.py
"""

import shutil
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DOCS = RAIZ / "docs"
sys.path.insert(0, str(RAIZ / "app"))
import db  # noqa: E402

FONTE = "DejaVu Sans"

# =============================================================================
# 1. DER conceitual (Chen) — escrito à mão em docs/der_conceitual.dot, porque
#    é o modelo do NEGÓCIO (entidades, multivalorados, compostos, derivados),
#    não uma cópia das tabelas. Este script só o renderiza.


# =============================================================================
# 2. Modelo lógico — gerado do banco
# =============================================================================
GRUPOS = {
    "superintendencia": "#6250d6", "delegacia": "#6250d6", "uop": "#6250d6",
    "acidente": "#2a78d6", "pessoa": "#2a78d6", "veiculo": "#2a78d6",
    "causa_acidente": "#008300", "acidente_tipo": "#008300", "acidente_tracado": "#008300",
}
COR_CATALOGO = "#52514e"


def gerar_logico() -> str:
    colunas = db.consultar("""
        SELECT c.table_name AS tabela, c.column_name AS coluna, c.column_type AS tipo,
               c.is_nullable AS nulo, c.column_key AS chave, c.ordinal_position AS pos,
               c.extra AS extra
          FROM information_schema.columns c
          JOIN information_schema.tables t
            ON t.table_schema = c.table_schema AND t.table_name = c.table_name
         WHERE c.table_schema = DATABASE() AND t.table_type = 'BASE TABLE'
         ORDER BY c.table_name, c.ordinal_position
    """)
    fks = db.consultar("""
        SELECT k.table_name AS tabela, k.constraint_name AS nome,
               GROUP_CONCAT(k.column_name ORDER BY k.ordinal_position) AS colunas,
               k.referenced_table_name AS ref_tabela,
               GROUP_CONCAT(k.referenced_column_name ORDER BY k.ordinal_position) AS ref_colunas
          FROM information_schema.key_column_usage k
         WHERE k.table_schema = DATABASE() AND k.referenced_table_name IS NOT NULL
         GROUP BY k.table_name, k.constraint_name, k.referenced_table_name
    """)
    fk_cols = {(r.tabela, c) for r in fks.itertuples() for c in r.colunas.split(",")}

    linhas = [
        "digraph DER_logico {",
        f'  graph [rankdir=LR, splines=spline, nodesep=0.35, ranksep=1.1, pad=0.4, '
        f'fontname="{FONTE}", fontsize=22, labelloc=t, label=<<B>USUPORT — modelo lógico '
        f'(3FN)</B><BR/><FONT POINT-SIZE="13">16 tabelas · PK/FK · pé-de-galinha · gerado do '
        f'INFORMATION_SCHEMA</FONT>>];',
        f'  node [shape=plain, fontname="{FONTE}", fontsize=11];',
        f'  edge [fontname="{FONTE}", fontsize=9, color="#52514e", dir=both, penwidth=1.2];',
    ]
    for tabela, grupo in colunas.groupby("tabela", sort=False):
        cor = GRUPOS.get(tabela, COR_CATALOGO)
        cel = [f'<TR><TD BGCOLOR="{cor}" COLSPAN="3"><FONT COLOR="white"><B>{tabela}'
               f'</B></FONT></TD></TR>']
        for c in grupo.itertuples():
            marca = []
            if c.chave == "PRI":
                marca.append("PK")
            if (tabela, c.coluna) in fk_cols:
                marca.append("FK")
            if "GENERATED" in (c.extra or ""):
                marca.append("GER")
            nome = f"<B>{c.coluna}</B>" if c.chave == "PRI" else c.coluna
            nulo = "" if c.nulo == "NO" else " ?"
            # duas portas por linha: _w (borda esquerda, onde CHEGA a FK que
            # aponta para esta PK) e _e (borda direita, de onde SAI a FK)
            cel.append(f'<TR><TD ALIGN="LEFT" PORT="{c.coluna}_w">{" ".join(marca)}</TD>'
                       f'<TD ALIGN="LEFT">{nome}</TD>'
                       f'<TD ALIGN="LEFT" PORT="{c.coluna}_e"><FONT COLOR="#6b6a66">'
                       f'{c.tipo}{nulo}</FONT></TD></TR>')
        linhas.append(f'  {tabela} [label=<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="0" '
                      f'CELLPADDING="3" COLOR="{cor}">' + "".join(cel) + "</TABLE>>];")

    nulos = {(r.tabela, r.coluna): r.nulo == "YES" for r in colunas.itertuples()}
    for r in fks.itertuples():
        col = r.colunas.split(",")[0]
        ref = r.ref_colunas.split(",")[0]
        opcional = nulos.get((r.tabela, col), False)
        # lado do pai (head): 1 obrigatório = teetee | 0..1 = teeodot
        # lado do filho (tail): 0..N = crowodot
        rotulo = f'label="{r.colunas}"' if "," in r.colunas else ""
        estilo = ', style=dashed' if opcional else ""
        linhas.append(f'  {r.tabela}:{col}_e:e -> {r.ref_tabela}:{ref}_w:w '
                      f'[arrowtail=crowodot, arrowhead={"teeodot" if opcional else "teetee"}'
                      f'{estilo}{", " + rotulo if rotulo else ""}];')

    linhas.append('''  legenda [label=<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="2" CELLPADDING="3" COLOR="#8a8984">
      <TR><TD COLSPAN="2"><B>Legenda</B></TD></TR>
      <TR><TD BGCOLOR="#2a78d6"> </TD><TD ALIGN="LEFT">entidades principais</TD></TR>
      <TR><TD BGCOLOR="#008300"> </TD><TD ALIGN="LEFT">associativas (multivalorados N:N)</TD></TR>
      <TR><TD BGCOLOR="#6250d6"> </TD><TD ALIGN="LEFT">hierarquia da PRF</TD></TR>
      <TR><TD BGCOLOR="#52514e"> </TD><TD ALIGN="LEFT">catálogos</TD></TR>
      <TR><TD ALIGN="LEFT">PK / FK / GER</TD><TD ALIGN="LEFT">chave primária / estrangeira / coluna gerada</TD></TR>
      <TR><TD ALIGN="LEFT">tipo ?</TD><TD ALIGN="LEFT">aceita NULL</TD></TR>
      <TR><TD ALIGN="LEFT">linha tracejada</TD><TD ALIGN="LEFT">FK opcional (0..1)</TD></TR>
    </TABLE>>];''')
    linhas.append("}")
    return "\n".join(linhas)


# =============================================================================
# 3. Renderização
# =============================================================================
def renderizar(nome: str, motor: str) -> None:
    dot = DOCS / f"{nome}.dot"
    png = DOCS / f"{nome}.png"
    if shutil.which("dot"):
        subprocess.run([motor, "-Tpng", "-Gdpi=200", str(dot), "-o", str(png)], check=True)
        return
    # Sem Graphviz instalado: usa um contêiner alpine descartável.
    volume = f"{DOCS.as_posix()}:/w"
    cmd = ["docker", "run", "--rm", "-v", volume, "alpine:3.20", "sh", "-c",
           "apk add --no-cache graphviz font-dejavu >/dev/null 2>&1 && "
           f"{motor} -Tpng -Gdpi=200 /w/{nome}.dot -o /w/{nome}.png"]
    subprocess.run(cmd, check=True)


def main() -> None:
    (DOCS / "der_logico.dot").write_text(gerar_logico(), encoding="utf-8")
    renderizar("der_conceitual", "neato")
    renderizar("der_logico", "dot")
    for n in ("der_conceitual", "der_logico"):
        print("Gerado:", DOCS / f"{n}.png")


if __name__ == "__main__":
    main()
