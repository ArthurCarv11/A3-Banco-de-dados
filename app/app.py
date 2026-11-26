"""
UNIFACS — Projeto Integrador de Banco de Dados — A3
Time Índice — Grupo 4 | Cenário: USUPORT

app.py — ponto de entrada do aplicativo Streamlit.
Execute a partir da raiz do projeto:

    streamlit run app/app.py

Monta a navegação entre as quatro telas (Consulta, Inserção, Exclusão e
Painel) e a barra lateral com a identificação da equipe e o status da
conexão com o MySQL da VM.
"""

import streamlit as st

import db

st.set_page_config(page_title="USUPORT — Time Índice", page_icon=":material/emergency:",
                   layout="wide")

# Telas do app. Cada arquivo em paginas/ é executado quando selecionado.
navegacao = st.navigation([
    st.Page("paginas/consulta.py", title="Consulta", icon=":material/search:", default=True),
    st.Page("paginas/insercao.py", title="Inserção", icon=":material/add_circle:"),
    st.Page("paginas/exclusao.py", title="Exclusão", icon=":material/delete:"),
    st.Page("paginas/painel.py",   title="Painel gerencial", icon=":material/monitoring:"),
])

with st.sidebar:
    st.markdown("### Time Índice — USUPORT")
    st.caption("UNIFACS · Campus CTN · Salvador  \n"
               "UC Projeto Integrador de Banco de Dados — A3  \n"
               "Professores: Sergio Spinola e Alexandre Anunciação  \n"
               "Equipe: Time Índice — Grupo 4")
    ok, mensagem = db.testar_conexao()
    (st.success if ok else st.error)(mensagem, icon=":material/database:")
    st.caption("Sinistros em rodovias federais — base PRF 2024, normalizada até a 3FN.")

navegacao.run()
