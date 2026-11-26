"""
paginas/exclusao.py — DELETE: exclusão FÍSICA de um acidente e de todos os
seus dependentes (pessoas, veículos, causas, tipos e traçados) numa única
transação, com pré-visualização e dupla confirmação.

Trava de segurança: por padrão só podem ser excluídos acidentes criados pelo
próprio sistema (id >= 9.000.001). Apagar um registro original da PRF exige
marcar uma confirmação extra.
"""

import mysql.connector
import streamlit as st

import db
from componentes import erro_mysql, mostrar_sql

st.title("Exclusão de acidente")
st.caption("Time Índice — USUPORT · exclusão física em transação: filhos antes do pai "
           "(as FKs são RESTRICT).")

log: list = []

# Resultado da última exclusão (mostrado após o rerun).
if "ultima_exclusao" in st.session_state:
    id_exc, removidas, log_exc = st.session_state.pop("ultima_exclusao")
    st.success(f"Acidente **{id_exc}** excluído (COMMIT). Linhas removidas por tabela: "
               + ", ".join(f"{t} = {n}" for t, n in removidas.items()), icon=":material/check_circle:")
    mostrar_sql(log_exc, "SQL executado na exclusão", aberto=True)

st.markdown("**Acidentes cadastrados pelo sistema** (massa de teste e inserções pelo app)")
sistema = db.acidentes_do_sistema(log)
if sistema.empty:
    st.caption("Nenhum acidente do sistema no momento.")
else:
    st.dataframe(sistema, hide_index=True, width="stretch")

padrao = int(sistema["id"].iloc[0]) if not sistema.empty else 0
id_alvo = st.number_input("Id do acidente a excluir", min_value=0, step=1, value=padrao)

if id_alvo:
    resumo = db.resumo_exclusao(int(id_alvo), log)
    if resumo["acidente"] == 0:
        st.warning(f"O acidente {id_alvo} não existe.", icon=":material/search_off:")
    else:
        ficha = db.consultar("SELECT id, data, municipio, uf, classificacao, causa_principal "
                             "FROM vw_acidente_detalhe WHERE id = %s", (int(id_alvo),), log)
        st.dataframe(ficha, hide_index=True, width="stretch")
        st.markdown("**Será apagado** (pré-visualização, nada foi alterado ainda):")
        st.dataframe([resumo], hide_index=True)

        original_prf = id_alvo < db.ID_INICIAL_SISTEMA
        liberado = True
        if original_prf:
            st.error("Este é um registro ORIGINAL da PRF (importado do CSV).", icon=":material/lock:")
            liberado = st.checkbox("Entendo que estou apagando um registro original da PRF.")

        confirmacao = st.text_input("Para confirmar, digite o id do acidente", key=f"conf{id_alvo}")
        pode = liberado and confirmacao.strip() == str(id_alvo)
        if st.button("Excluir definitivamente", type="primary", disabled=not pode,
                     icon=":material/delete_forever:"):
            log_transacao: list = []               # só a transação + a releitura
            try:
                removidas = db.excluir_acidente(int(id_alvo), log_transacao)
                # Prova de persistência: relê o banco depois do COMMIT.
                depois = db.resumo_exclusao(int(id_alvo), log_transacao)
                st.session_state.ultima_exclusao = (int(id_alvo), removidas, log_transacao)
                assert sum(depois.values()) == 0
                st.rerun()
            except mysql.connector.Error as erro:
                log.extend(log_transacao)
                erro_mysql(erro)
                st.caption("A transação foi desfeita (ROLLBACK): nada foi apagado.")

mostrar_sql(log)
