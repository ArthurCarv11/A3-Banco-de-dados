"""
UNIFACS — Projeto Integrador de Banco de Dados — A3
Time Índice — Grupo 4 | Cenário: USUPORT

gerar_relatorio.py — gera docs/relatorio.pdf a partir de docs/relatorio.md.

Etapas:
  1. expande as diretivas do relatorio.md:
       <!-- incluir: arquivo.md -->                 insere outro documento (títulos rebaixados)
       <!-- incluir-trecho: arq :: ## A :: ## B --> insere o trecho entre dois títulos
       <!-- codigo: app/db.py :: funcao -->          insere o código-fonte real de uma função
     assim o relatório usa SEMPRE a versão atual dos documentos e do código;
  2. converte Markdown → HTML (biblioteca "markdown") com folha de estilo A4;
  3. imprime o HTML em PDF com o Microsoft Edge em modo headless.

Uso, da raiz do projeto:
    python scripts/gerar_relatorio.py
"""

import ast
import re
import shutil
import subprocess
from pathlib import Path

import markdown

RAIZ = Path(__file__).resolve().parent.parent
DOCS = RAIZ / "docs"

EDGE_CANDIDATOS = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    "microsoft-edge", "google-chrome", "chromium",
]

CSS = r"""
@page { size: A4; margin: 18mm 17mm 18mm 17mm;
        @bottom-left  { content: "Time Índice — Grupo 4 · Cenário USUPORT"; font: 7.5pt 'Segoe UI', sans-serif; color: #777; }
        @bottom-right { content: counter(page); font: 8pt 'Segoe UI', sans-serif; color: #777; } }
@page capa { margin: 0; @bottom-left { content: none; } @bottom-right { content: none; } }
@page paisagem { size: A4 landscape; margin: 10mm 12mm 14mm 12mm; }
html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body { font-family: 'Segoe UI', 'DejaVu Sans', Arial, sans-serif; font-size: 10pt; line-height: 1.45; color: #1d1d1f; }
h1 { break-before: page; font-size: 19pt; color: #17417f; border-bottom: 2.5px solid #2a78d6; padding-bottom: 4px; margin: 0 0 10pt; }
h2 { font-size: 13.5pt; color: #17417f; margin: 16pt 0 6pt; break-after: avoid; }
h3 { font-size: 11.5pt; color: #222; margin: 13pt 0 5pt; break-after: avoid; }
h4 { font-size: 10.5pt; margin: 10pt 0 4pt; break-after: avoid; }
p, li { orphans: 3; widows: 3; }
table { border-collapse: collapse; width: 100%; font-size: 8.6pt; margin: 6pt 0 10pt; }
th, td { border: 1px solid #c8ccd2; padding: 2.5pt 4.5pt; vertical-align: top; text-align: left; }
th { background: #e9f0fb; }
tr { break-inside: avoid; }
code { font-family: Consolas, 'DejaVu Sans Mono', monospace; font-size: 8.4pt; background: #f2f3f5; padding: 0 2px; border-radius: 2px; }
pre { background: #f6f8fa; border: 1px solid #dde1e6; border-radius: 4px; padding: 6pt 8pt; font-size: 7.8pt; line-height: 1.32;
      white-space: pre-wrap; word-break: break-word; }
pre code { background: none; padding: 0; font-size: inherit; }
blockquote { margin: 6pt 0; padding: 4pt 10pt; border-left: 3px solid #2a78d6; background: #f4f8fe; color: #333; }
a { color: #1f5fbf; text-decoration: none; }
.tabela-compacta table { font-size: 8pt; }
.figura { text-align: center; margin: 10pt 0; break-inside: avoid; }
.figura img { max-width: 100%; max-height: 225mm; border: 1px solid #e0e0e0; }
.paisagem { page: paisagem; }
.paisagem img { max-height: 170mm; border: none; }
.legenda { font-size: 8.3pt; color: #555; margin-top: 3pt; text-align: center; }
/* capa */
.capa { page: capa; height: 296mm; box-sizing: border-box; padding: 28mm 26mm 20mm; display: flex; flex-direction: column;
        background: linear-gradient(180deg, #17417f 0, #17417f 62mm, #ffffff 62mm); }
.capa .titulo { color: #17417f; font-size: 40pt; font-weight: 700; margin: 30mm 0 0; letter-spacing: 2px; }
.capa .instituicao { color: #fff; font-size: 13pt; font-weight: 600; margin: 0; }
.capa .uc { color: #dbe8f8; font-size: 10.5pt; margin: 4pt 0 0; }
.capa .subtitulo { font-size: 13pt; color: #333; margin: 4pt 0 14mm; }
.capa .equipe { font-size: 11.5pt; margin: 0 0 6pt; }
.capa table { width: 75%; font-size: 10pt; }
.capa .professores { margin-top: 10pt; font-size: 10.5pt; }
.capa .local { margin-top: auto; font-size: 10.5pt; color: #444; }
/* sumário */
.sumario { break-after: page; }
.sumario .titulo-sumario { font-size: 17pt; font-weight: 700; color: #17417f; border-bottom: 2.5px solid #2a78d6; padding-bottom: 4px; }
.sumario .toc ul { list-style: none; padding-left: 0; }
.sumario .toc > ul > li { margin: 5pt 0; font-weight: 600; }
.sumario .toc ul ul { padding-left: 16pt; font-weight: 400; }
.sumario .toc ul ul li { margin: 1.5pt 0; }
"""


def rebaixar_titulos(texto: str) -> str:
    """'# X' → '## X' etc., fora de blocos de código."""
    saida, em_codigo = [], False
    for linha in texto.splitlines():
        if linha.strip().startswith("```"):
            em_codigo = not em_codigo
        if not em_codigo and re.match(r"^#{1,5} ", linha):
            linha = "#" + linha
        saida.append(linha)
    return "\n".join(saida)


def incluir_documento(caminho: Path) -> str:
    """Insere um .md sem o título principal e sem a citação de cabeçalho."""
    linhas = caminho.read_text(encoding="utf-8").splitlines()
    if linhas and linhas[0].startswith("# "):
        linhas = linhas[1:]
    while linhas and (not linhas[0].strip() or linhas[0].startswith(">")):
        linhas = linhas[1:]
    return rebaixar_titulos("\n".join(linhas))


def incluir_trecho(caminho: Path, inicio: str, fim: str) -> str:
    texto = caminho.read_text(encoding="utf-8")
    a = texto.index(inicio) + len(inicio)
    b = texto.index(fim, a)
    return texto[a:b].strip()


def codigo_funcao(caminho: Path, nome: str) -> str:
    """Extrai o código-fonte exato de uma função (via árvore sintática)."""
    fonte = caminho.read_text(encoding="utf-8")
    for no in ast.walk(ast.parse(fonte)):
        if isinstance(no, ast.FunctionDef) and no.name == nome:
            linhas = fonte.splitlines()[no.lineno - 1: no.end_lineno]
            return f"```python\n# {caminho.relative_to(RAIZ).as_posix()}\n" + "\n".join(linhas) + "\n```"
    raise ValueError(f"função {nome} não encontrada em {caminho}")


def expandir(md: str) -> str:
    md = re.sub(r"<!-- incluir: (.+?) -->",
                lambda m: incluir_documento((DOCS / m.group(1).strip()).resolve()), md)
    md = re.sub(r"<!-- incluir-trecho: (.+?) :: (.+?) :: (.+?) -->",
                lambda m: incluir_trecho((DOCS / m.group(1).strip()).resolve(),
                                         m.group(2).strip(), m.group(3).strip()), md)
    md = re.sub(r"<!-- codigo: (.+?) :: (.+?) -->",
                lambda m: codigo_funcao(RAIZ / m.group(1).strip(), m.group(2).strip()), md)
    return md


def localizar_navegador() -> str:
    for c in EDGE_CANDIDATOS:
        if Path(c).exists() or shutil.which(c):
            return c
    raise FileNotFoundError("Microsoft Edge/Chrome não encontrado para gerar o PDF.")


def main() -> None:
    md = expandir((DOCS / "relatorio.md").read_text(encoding="utf-8"))
    corpo = markdown.markdown(md, extensions=["extra", "toc", "sane_lists"],
                              extension_configs={"toc": {"toc_depth": "1-2"}})
    html = ("<!doctype html><html lang='pt-BR'><head><meta charset='utf-8'>"
            "<title>USUPORT — Relatório técnico — Time Índice</title>"
            f"<style>{CSS}</style></head><body>{corpo}</body></html>")
    arq_html = DOCS / "relatorio.html"
    arq_html.write_text(html, encoding="utf-8")

    pdf = DOCS / "relatorio.pdf"
    subprocess.run([localizar_navegador(), "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                    f"--print-to-pdf={pdf}", arq_html.as_uri()],
                   check=True, capture_output=True)
    arq_html.unlink()                     # o HTML é só intermediário
    print(f"Gerado: {pdf} ({pdf.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
