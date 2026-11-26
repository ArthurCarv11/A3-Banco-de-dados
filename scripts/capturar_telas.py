"""
UNIFACS — Projeto Integrador de Banco de Dados — A3
Time Índice — Grupo 4 | Cenário: USUPORT

capturar_telas.py — tira as capturas de tela do app usadas no relatório
(docs/img/app_*.png). Utilitário de documentação: precisa do app rodando
(streamlit run app/app.py) e do pacote playwright; usa o Microsoft Edge já
instalado (channel="msedge"), sem baixar navegador.

Uso, da raiz do projeto:
    python scripts/capturar_telas.py [url_base]
"""

import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

RAIZ = Path(__file__).resolve().parent.parent
DESTINO = RAIZ / "docs" / "img"
BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8501"


def esperar_app(pagina, ms_extra: int = 1500) -> None:
    """Espera o Streamlit terminar de rodar o script (some o indicador 'Running')."""
    pagina.wait_for_selector('[data-testid="stSidebar"]', timeout=30000)
    pagina.wait_for_timeout(1000)
    pagina.wait_for_function(
        "() => !document.querySelector('[data-testid=\"stStatusWidget\"]')"
        " || !document.querySelector('[data-testid=\"stStatusWidget\"]').innerText.includes('Running')",
        timeout=60000)
    pagina.wait_for_timeout(ms_extra)


def main() -> None:
    DESTINO.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="msedge", headless=True)
        ctx = nav.new_context(viewport={"width": 1440, "height": 1000}, color_scheme="light",
                              device_scale_factor=1.5)
        pg = ctx.new_page()

        # 1) Consulta: busca o acidente 661121 e abre a ficha
        pg.goto(f"{BASE}/")
        esperar_app(pg, 2500)
        campo = pg.get_by_role("spinbutton", name="Id do acidente")
        campo.click()
        campo.fill("661121")
        pg.get_by_role("button", name="Buscar", exact=False).first.click()
        pg.get_by_text("1 acidente(s) exibido(s)").wait_for(timeout=30000)   # filtro aplicado
        esperar_app(pg)
        grade = pg.locator('[data-testid="stDataFrame"]').first
        caixa = grade.bounding_box()
        pg.mouse.click(caixa["x"] + 20, caixa["y"] + 55)      # 1ª linha (coluna de seleção)
        titulo = pg.get_by_text("Acidente 661121")
        titulo.wait_for(timeout=30000)
        esperar_app(pg, 2000)
        titulo.scroll_into_view_if_needed()                    # mostra a ficha, não o formulário
        pg.wait_for_timeout(1000)
        pg.screenshot(path=str(DESTINO / "app_consulta.png"))

        # 2) Inserção
        pg.set_viewport_size({"width": 1440, "height": 1250})
        pg.goto(f"{BASE}/insercao")
        esperar_app(pg)
        pg.wait_for_selector('[data-testid="stTimeInput"]', timeout=20000)   # campo de horário
        pg.wait_for_timeout(1500)
        pg.screenshot(path=str(DESTINO / "app_insercao.png"))

        # 3) Exclusão (pré-visualização do acidente de teste)
        pg.set_viewport_size({"width": 1440, "height": 820})
        pg.goto(f"{BASE}/exclusao")
        esperar_app(pg)
        pg.screenshot(path=str(DESTINO / "app_exclusao.png"))

        # 4) Painel
        pg.set_viewport_size({"width": 1440, "height": 1120})
        pg.goto(f"{BASE}/painel")
        esperar_app(pg, 3000)
        pg.wait_for_selector("canvas.marks, svg.marks", timeout=30000)   # gráfico Vega desenhado
        pg.wait_for_timeout(1500)
        pg.screenshot(path=str(DESTINO / "app_painel.png"))

        nav.close()
    for f in sorted(DESTINO.glob("app_*.png")):
        print("Gerado:", f)


if __name__ == "__main__":
    main()
