"""
componentes.py — peças de interface reutilizadas pelas telas.

O destaque é `mostrar_sql`: todas as telas terminam com o expander
"SQL executado", que lista cada instrução enviada ao MySQL e os valores
passados como parâmetros (a prova de que o app fala SQL direto com o SGBD).
"""

from __future__ import annotations

import mysql.connector
import streamlit as st

# Erros do MySQL mais comuns nas telas, com explicação em português.
MENSAGENS_ERRO = {
    3819: "Uma regra CHECK foi violada (valor fora do domínio permitido).",
    1452: "Chave estrangeira inválida: o registro referenciado não existe ou é de outro acidente.",
    1451: "Não é possível apagar: ainda há registros dependentes (FK RESTRICT).",
    1062: "Valor duplicado em uma chave única (PK/UNIQUE).",
    1048: "Campo obrigatório (NOT NULL) ficou vazio.",
}


def formatar_parametros(params) -> str:
    """Representa os parâmetros de forma legível (listas longas são resumidas)."""
    if params is None:
        return ""
    if isinstance(params, list) and len(params) > 6:
        return f"{params[:6]} ... (+{len(params) - 6} linhas, via executemany)"
    return repr(params)


def mostrar_sql(log: list, titulo: str = "SQL executado", aberto: bool = False) -> None:
    """Expander com as instruções SQL executadas nesta tela, na ordem."""
    with st.expander(f"{titulo} ({len(log)} instrução(ões))", expanded=aberto,
                     icon=":material/code:"):
        if not log:
            st.caption("Nenhuma instrução executada ainda.")
        for i, (sql, params) in enumerate(log, start=1):
            st.markdown(f"**{i}.**")
            st.code(sql, language="sql")
            if params:
                st.caption("Parâmetros (%s, na ordem): " + formatar_parametros(params))


def erro_mysql(erro: mysql.connector.Error) -> None:
    """Mostra um erro do MySQL com o código, a explicação e a mensagem original."""
    explicacao = MENSAGENS_ERRO.get(erro.errno, "Erro retornado pelo MySQL.")
    st.error(f"**Erro {erro.errno}** — {explicacao}\n\n`{erro.msg}`", icon=":material/error:")


def opcoes(df, coluna_texto: str = "descricao") -> dict:
    """Converte um DataFrame (id, descricao) em {id: descricao} para selectbox."""
    return dict(zip(df["id"].tolist(), df[coluna_texto].tolist()))
