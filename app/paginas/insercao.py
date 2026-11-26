"""
paginas/insercao.py — CREATE: cadastro de um acidente completo.

Um acidente só faz sentido com suas partes: causas (com a principal),
tipos em ordem, traçados, veículos e pessoas. Por isso o formulário coleta
tudo e o db.inserir_acidente grava em UMA transação (tudo ou nada).
A classificação não é digitada: é calculada do estado físico das pessoas
(regra RN08), o que mantém o banco coerente.
"""

from datetime import date, time

import mysql.connector
import pandas as pd
import streamlit as st

import db
from componentes import erro_mysql, mostrar_sql, opcoes


@st.cache_data(ttl=600, show_spinner=False)
def _catalogo(nome):
    return db.catalogo(nome)


@st.cache_data(ttl=600, show_spinner=False)
def _cidades(uf):
    return db.cidades_da_uf(uf)


st.title("Inserção de acidente")
st.caption("Time Índice — USUPORT · cadastro completo gravado numa única transação. "
           "Novos acidentes recebem id a partir de 9.000.001 (faixa do sistema).")

# Versão do formulário: ao gravar com sucesso, incrementa e os widgets voltam ao padrão.
if "versao_form" not in st.session_state:
    st.session_state.versao_form = 0
k = st.session_state.versao_form

# Resultado da última gravação (sobrevive ao "reset" do formulário).
if "ultima_insercao" in st.session_state:
    novo_id, log_ultimo = st.session_state.ultima_insercao
    st.success(f"Acidente **{novo_id}** gravado com sucesso (COMMIT). "
                "Confira na tela Consulta, filtrando pelo id.", icon=":material/check_circle:")
    mostrar_sql(log_ultimo, "SQL executado na última gravação", aberto=True)

log: list = []

# -----------------------------------------------------------------------------
# 1. Dados do acidente
# -----------------------------------------------------------------------------
st.subheader("1. Dados do acidente")
c1, c2, c3, c4 = st.columns(4)
data_ac = c1.date_input("Data", date(2024, 12, 31), format="DD/MM/YYYY", key=f"data{k}")
hora_ac = c2.time_input("Horário", time(18, 0), step=300, key=f"hora{k}")
uf = c3.selectbox("UF", db.UFS, index=db.UFS.index("BA"), key=f"uf{k}")
cidades = _cidades(uf)
mapa_cid = dict(zip(cidades["id"], cidades["nome"]))
padrao_cid = list(mapa_cid.values()).index("SALVADOR") if "SALVADOR" in mapa_cid.values() else 0
id_cidade = c4.selectbox("Município", list(mapa_cid), index=padrao_cid,
                         format_func=mapa_cid.get, key=f"cid{k}")

c5, c6, c7, c8 = st.columns(4)
br = c5.number_input("BR (0 = sem BR)", 0, 499, 324, step=1, key=f"br{k}")
km = c6.number_input("km", 0.0, 2000.0, 610.0, step=0.1, format="%.1f", key=f"km{k}",
                     disabled=br == 0)
sentido = c7.selectbox("Sentido", db.SENTIDOS, key=f"sent{k}")
tipo_pista = c8.selectbox("Tipo de pista", db.TIPOS_PISTA, index=1, key=f"pista{k}")

sugestao = db.coordenadas_sugeridas(id_cidade, log) or (-12.97, -38.50)
c9, c10, c11, c12 = st.columns(4)
uso_solo = c9.selectbox("Uso do solo", db.USOS_SOLO, key=f"solo{k}")
latitude = c10.number_input("Latitude", -34.0, 6.0, sugestao[0], format="%.6f",
                            key=f"lat{k}_{id_cidade}")
longitude = c11.number_input("Longitude", -74.0, -28.0, sugestao[1], format="%.6f",
                             key=f"lon{k}_{id_cidade}")
c12.caption("Coordenadas sugeridas: ponto médio dos acidentes já registrados no município.")

condicoes = opcoes(_catalogo("condicao_meteorologica"))
fases = opcoes(_catalogo("fase_dia"))
c13, c14 = st.columns(2)
id_condicao = c13.selectbox("Condição meteorológica", list(condicoes), format_func=condicoes.get,
                            key=f"cond{k}")
id_fase = c14.selectbox("Fase do dia", list(fases), format_func=fases.get, key=f"fase{k}")

# Unidade da PRF — o banco guarda só a MAIS ESPECÍFICA escolhida (arco).
st.markdown("**Unidade da PRF responsável** (o banco grava apenas a mais específica)")
u1, u2, u3 = st.columns(3)
sups = opcoes(_catalogo("superintendencia"))
id_sup = u1.selectbox("Superintendência", [None] + list(sups), placeholder="— nenhuma —",
                      format_func=lambda i: "— nenhuma —" if i is None else sups[i], key=f"sup{k}")
dels = opcoes(db.delegacias_da_superintendencia(id_sup, log), "sigla") if id_sup else {}
id_del = u2.selectbox("Delegacia", [None] + list(dels), disabled=not dels, placeholder="— nenhuma —",
                      format_func=lambda i: "— nenhuma —" if i is None else dels[i], key=f"del{k}")
uops = opcoes(db.uops_da_delegacia(id_del, log), "sigla") if id_del else {}
id_uop = u3.selectbox("UOP", [None] + list(uops), disabled=not uops, placeholder="— nenhuma —",
                      format_func=lambda i: "— nenhuma —" if i is None else uops[i], key=f"uop{k}")

# -----------------------------------------------------------------------------
# 2. Causas, tipos e traçados (atributos multivalorados)
# -----------------------------------------------------------------------------
st.subheader("2. Causas, sequência de tipos e traçado")
causas = opcoes(_catalogo("causa"))
tipos = opcoes(_catalogo("tipo_acidente"))
tracados = opcoes(_catalogo("tracado"))
id_por_tipo = {v: kk for kk, v in tipos.items()}

a1, a2 = st.columns([3, 2])
causas_sel = a1.multiselect("Causas apontadas", list(causas), format_func=causas.get,
                            key=f"causas{k}", placeholder="Escolha uma ou mais causas")
principal = a2.selectbox("Causa principal (exatamente uma)", causas_sel or [None],
                         format_func=lambda i: "—" if i is None else causas[i], key=f"princ{k}")

b1, b2 = st.columns([3, 2])
b1.markdown("**Sequência de tipos** — a ordem das linhas é a ordem dos eventos; "
            "o mesmo tipo pode se repetir.")
tipos_df = b1.data_editor(
    pd.DataFrame({"tipo": ["Colisão traseira"]}), num_rows="dynamic", hide_index=False,
    width="stretch", key=f"tipos{k}",
    column_config={"tipo": st.column_config.SelectboxColumn("Tipo", options=list(tipos.values()),
                                                            required=True)})
tracados_sel = b2.multiselect("Traçado da via", list(tracados), format_func=tracados.get,
                              default=[kk for kk, v in tracados.items() if v == "Reta"],
                              key=f"trac{k}")

# -----------------------------------------------------------------------------
# 3. Veículos e pessoas
# -----------------------------------------------------------------------------
st.subheader("3. Veículos e pessoas")
tipos_veic = opcoes(_catalogo("tipo_veiculo"))
id_por_tipo_veic = {v: kk for kk, v in tipos_veic.items()}

st.markdown("**Veículos** — rotulados V1, V2, ... na ordem das linhas.")
veic_df = st.data_editor(
    pd.DataFrame({"tipo": ["Automóvel"], "marca": ["FIAT/ARGO DRIVE 1.0"], "ano": [2021]}),
    num_rows="dynamic", width="stretch", key=f"veic{k}",
    column_config={
        "tipo": st.column_config.SelectboxColumn("Tipo", options=list(tipos_veic.values()),
                                                 required=True),
        "marca": st.column_config.TextColumn("Marca/modelo", max_chars=40),
        "ano": st.column_config.NumberColumn("Ano", min_value=1900, max_value=2100, step=1),
    })
veic_df = veic_df.dropna(subset=["tipo"]).reset_index(drop=True)
rotulos = [f"V{i}" for i in range(1, len(veic_df) + 1)]

st.markdown("**Pessoas** — Condutor/Passageiro escolhem um veículo; "
            "Pedestre, Testemunha e Cavaleiro ficam sem veículo.")
pes_df = st.data_editor(
    pd.DataFrame({"tipo_envolvido": ["Condutor"], "veiculo": ["V1"], "estado_fisico": ["Ileso"],
                  "idade": [30], "sexo": ["Masculino"]}),
    num_rows="dynamic", width="stretch", key=f"pes{k}",
    column_config={
        "tipo_envolvido": st.column_config.SelectboxColumn("Envolvido", options=db.TIPOS_ENVOLVIDO,
                                                           required=True),
        "veiculo": st.column_config.SelectboxColumn("Veículo", options=rotulos),
        "estado_fisico": st.column_config.SelectboxColumn("Estado físico",
                                                          options=db.ESTADOS_FISICOS, required=True),
        "idade": st.column_config.NumberColumn("Idade", min_value=0, max_value=110, step=1),
        "sexo": st.column_config.SelectboxColumn("Sexo", options=db.SEXOS, required=True),
    })
pes_df = pes_df.dropna(subset=["tipo_envolvido", "estado_fisico", "sexo"]).reset_index(drop=True)

# -----------------------------------------------------------------------------
# 4. Conferência e gravação
# -----------------------------------------------------------------------------
veiculos = [{"rotulo": rotulos[i], "id_tipo_veiculo": id_por_tipo_veic[r.tipo],
             "marca": (r.marca or "").strip() or None,
             "ano_fabricacao": None if pd.isna(r.ano) else int(r.ano)}
            for i, r in enumerate(veic_df.itertuples())]
pessoas = [{"tipo_envolvido": r.tipo_envolvido,
            "veiculo": None if pd.isna(r.veiculo) else r.veiculo,
            "estado_fisico": r.estado_fisico,
            "idade": None if pd.isna(r.idade) else int(r.idade),
            "sexo": r.sexo} for r in pes_df.itertuples()]
lista_tipos = [id_por_tipo[t] for t in tipos_df["tipo"].dropna()]

dados = {"data": data_ac, "horario": hora_ac, "br": br or None, "km": km if br else None,
         "sentido": sentido, "tipo_pista": tipo_pista, "uso_solo": uso_solo,
         "latitude": latitude, "longitude": longitude, "id_cidade": id_cidade,
         "id_condicao": id_condicao, "id_fase_dia": id_fase,
         # arco: só a unidade mais específica vai para o banco
         "id_uop": id_uop,
         "id_delegacia": id_del if not id_uop else None,
         "id_superintendencia": id_sup if not (id_uop or id_del) else None}

st.subheader("4. Conferência")
st.info(f"Classificação calculada pelas pessoas (RN08): **{db.classificacao_calculada(pessoas)}** · "
        f"{len(causas_sel)} causa(s), {len(lista_tipos)} tipo(s), {len(tracados_sel)} traçado(s), "
        f"{len(veiculos)} veículo(s), {len(pessoas)} pessoa(s).", icon=":material/fact_check:")

erros = db.validar_novo_acidente(dados, causas_sel, principal, lista_tipos, tracados_sel,
                                 veiculos, pessoas)
for e in erros:
    st.warning(e, icon=":material/warning:")

if st.button("Gravar acidente", type="primary", disabled=bool(erros), icon=":material/save:"):
    log_transacao: list = []                       # só os comandos da transação
    try:
        novo_id = db.inserir_acidente(dados, causas_sel, principal, lista_tipos, tracados_sel,
                                      veiculos, pessoas, log_transacao)
        st.session_state.ultima_insercao = (novo_id, log_transacao)
        st.session_state.versao_form += 1          # limpa o formulário
        st.rerun()
    except mysql.connector.Error as erro:
        log.extend(log_transacao)
        erro_mysql(erro)
        st.caption("A transação foi desfeita (ROLLBACK): nada foi gravado.")

mostrar_sql(log)
