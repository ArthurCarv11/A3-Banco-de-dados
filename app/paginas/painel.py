"""
paginas/painel.py — Painel gerencial: executa as consultas da DQL
(sql/06_dql_consultas.sql) e mostra tabela + gráfico.

O SQL NÃO está repetido aqui: o painel lê o arquivo 06 e separa as consultas
pelos marcadores "-- @Qnn | título". O que roda no DBeaver e o que roda no app
é exatamente o mesmo texto.
"""

from datetime import date

import altair as alt
import mysql.connector
import pandas as pd
import streamlit as st

import db
from componentes import erro_mysql, mostrar_sql

COR = "#2a78d6"   # uma série por gráfico → uma cor (azul da paleta de referência)

# Gráfico sugerido para cada consulta: (tipo, coluna categoria/x, coluna valor/y)
GRAFICOS = {
    "Q01": ("linha_mes", "mes", "obitos"),
    "Q02": ("barra", "causa_principal", "acidentes"),
    "Q03": ("barra", "tipo_veiculo", "obitos"),
    "Q04": ("calor", ("fase_dia", "condicao"), "acidentes"),
    "Q06": ("barra", "tracado", "obitos"),
    "Q07": ("barra", "superintendencia", "acidentes"),
    "Q08": ("barra", "uop", "acidentes"),
    "Q10": ("barra", "uso_solo", "obitos_por_100_acidentes"),
    "Q11": ("barra", "tipo_veiculo", "sem_pessoa"),
    "Q12": ("barra_ordem", "dia_semana", "acidentes"),
    "Q13": ("barra", "primeiro_evento", "obitos_por_100_acidentes"),
    "Q14": ("barra_ordem", "faixa_etaria", "total_obitos"),
    "Q15": ("linha", "hora", "acidentes"),
    "Q17": ("barra", "municipio", "acidentes"),
}


def grafico(codigo: str, df: pd.DataFrame):
    """Monta o gráfico Altair da consulta (barras horizontais finas com ponta
    arredondada, linha de 2px, mapa de calor em tons de uma só cor)."""
    if codigo not in GRAFICOS or df.empty:
        return None
    tipo, x, y = GRAFICOS[codigo]
    if tipo in ("barra", "barra_ordem"):
        ordem = "-x" if tipo == "barra" else None          # maior no topo / ordem da consulta
        altura = max(160, 26 * len(df))
        return (alt.Chart(df).mark_bar(color=COR, cornerRadiusEnd=4, size=16)
                .encode(x=alt.X(f"{y}:Q", title=y.replace("_", " ")),
                        y=alt.Y(f"{x}:N", sort=ordem, title=None,
                                axis=alt.Axis(labelLimit=380)),   # nomes longos de causa
                        tooltip=list(df.columns))
                .properties(height=altura))
    if tipo == "linha":
        return (alt.Chart(df).mark_line(color=COR, strokeWidth=2, point=alt.OverlayMarkDef(size=60, color=COR))
                .encode(x=alt.X(f"{x}:O", title=x), y=alt.Y(f"{y}:Q", title=y),
                        tooltip=list(df.columns))
                .properties(height=280))
    if tipo == "linha_mes":
        mensal = df.groupby("mes", as_index=False)[["acidentes", "obitos"]].sum()
        return (alt.Chart(mensal).mark_line(color=COR, strokeWidth=2,
                                            point=alt.OverlayMarkDef(size=60, color=COR))
                .encode(x=alt.X("mes:O", title="mês (todas as UFs filtradas)"),
                        y=alt.Y("obitos:Q", title="óbitos"),
                        tooltip=["mes", "acidentes", "obitos"])
                .properties(height=280))
    if tipo == "calor":
        linha, coluna = x
        # paddingInner separa as células com um respiro da cor do fundo (claro ou escuro)
        return (alt.Chart(df).mark_rect(cornerRadius=2)
                .encode(x=alt.X(f"{coluna}:N", title=None, scale=alt.Scale(paddingInner=0.06)),
                        y=alt.Y(f"{linha}:N", title=None, scale=alt.Scale(paddingInner=0.06)),
                        color=alt.Color(f"{y}:Q", scale=alt.Scale(scheme="blues"), title=y),
                        tooltip=list(df.columns))
                .properties(height=260))
    return None


@st.cache_data(show_spinner=False)
def _consultas():
    return db.carregar_consultas_dql()


st.title("Painel gerencial")
st.caption("Time Índice — USUPORT · consultas estratégicas de sql/06_dql_consultas.sql "
           "executadas ao vivo no MySQL.")

log: list = []
c1, c2 = st.columns([2, 1])
periodo = c1.date_input("Período (@data_ini / @data_fim)", (date(2024, 1, 1), date(2024, 12, 31)),
                        format="DD/MM/YYYY")
data_ini, data_fim = (periodo if isinstance(periodo, tuple) and len(periodo) == 2
                      else (date(2024, 1, 1), date(2024, 12, 31)))

# Indicadores de capa
try:
    kpi = db.indicadores(data_ini, data_fim, log)
    fmt = lambda n: f"{n:,}".replace(",", ".")
    k1, k2, k3, k4, k5, k6 = st.columns(6)
    k1.metric("Acidentes", fmt(kpi["acidentes"]))
    k2.metric("Pessoas envolvidas", fmt(kpi["pessoas"]))
    k3.metric("Ilesos", fmt(kpi["ilesos"]))
    k4.metric("Feridos leves", fmt(kpi["feridos_leves"]))
    k5.metric("Feridos graves", fmt(kpi["feridos_graves"]))
    k6.metric("Óbitos", fmt(kpi["obitos"]))
    # O que falta para fechar o total são as pessoas com estado "Não Informado".
    nao_inf = kpi["pessoas"] - kpi["ilesos"] - kpi["feridos_leves"] - kpi["feridos_graves"] - kpi["obitos"]
    st.caption(f"Estado físico não informado: {fmt(nao_inf)} pessoa(s) "
               "(sobretudo testemunhas e condutores não identificados).")
except mysql.connector.Error as e:
    erro_mysql(e)

consultas = _consultas()
rotulos = {q["codigo"]: f"{q['codigo']} — {q['titulo']}" for q in consultas}
codigo = c2.selectbox("Consulta", list(rotulos), index=1, format_func=rotulos.get)
id_acidente = 571778
if codigo == "Q16":
    id_acidente = st.number_input("@id_acidente", min_value=1, value=571778, step=1)

q = next(x for x in consultas if x["codigo"] == codigo)
st.subheader(rotulos[codigo])
st.caption(q["descricao"].replace("\n", "  \n"))

try:
    df = db.executar_dql(q["sql"], data_ini, data_fim, int(id_acidente), log)
    if codigo == "Q04":   # tabela cruzada fica mais legível pivotada
        g = grafico(codigo, df)
        if g is not None:
            st.altair_chart(g, width="stretch")
        st.dataframe(df.pivot_table(index="fase_dia", columns="condicao", values="acidentes",
                                    fill_value=0), width="stretch")
    else:
        g = grafico(codigo, df)
        if g is not None:
            st.altair_chart(g, width="stretch")
        st.dataframe(df, hide_index=True, width="stretch", height=min(560, 38 + 35 * len(df)))
except mysql.connector.Error as e:
    erro_mysql(e)

mostrar_sql(log, aberto=True)
