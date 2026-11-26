"""
paginas/consulta.py — READ: filtro e exibição de acidentes, pessoas,
veículos e causas. Ao selecionar um acidente, mostra a ficha completa
(remontada a partir das tabelas normalizadas).
"""

from datetime import date

import mysql.connector
import pandas as pd
import streamlit as st

import db
from componentes import erro_mysql, mostrar_sql, opcoes


@st.cache_data(ttl=600, show_spinner=False)
def _catalogo(nome):
    """Catálogos mudam pouco: guardamos em cache por 10 min."""
    return db.catalogo(nome)


@st.cache_data(ttl=600, show_spinner=False)
def _cidades(uf):
    return db.cidades_da_uf(uf)


st.title("Consulta")
st.caption("Time Índice — USUPORT · filtros sobre o banco normalizado; "
           "o SQL de cada busca aparece no fim da tela.")

log: list = []
ini_base, fim_base = date(2024, 1, 1), date(2024, 12, 31)


def resultado_da_aba(chave: str, submetido: bool, funcao):
    """Executa a busca da aba só quando o formulário é enviado (ou na 1ª vez)
    e guarda o resultado + o SQL usado na sessão. Assim, clicar numa linha ou
    trocar de aba não repete as consultas das outras abas."""
    if submetido or chave not in st.session_state:
        log_aba: list = []
        try:
            st.session_state[chave] = (funcao(log_aba), log_aba)
        except mysql.connector.Error as e:
            erro_mysql(e)
            st.session_state[chave] = (pd.DataFrame(), log_aba)
    df, log_aba = st.session_state[chave]
    log.extend(log_aba)
    return df

aba_acid, aba_pes, aba_vei, aba_cau = st.tabs(["Acidentes", "Pessoas", "Veículos", "Causas"])

# -----------------------------------------------------------------------------
# Acidentes
# -----------------------------------------------------------------------------
with aba_acid:
    with st.form("filtro_acidentes"):
        c1, c2, c3 = st.columns([2, 2, 1])
        periodo = c1.date_input("Período", (ini_base, fim_base), format="DD/MM/YYYY")
        ufs = c2.multiselect("UF", db.UFS, placeholder="Todas")
        id_direto = c3.number_input("Id do acidente", min_value=0, step=1, value=0,
                                    help="0 = não filtrar por id")
        c4, c5, c6 = st.columns(3)
        cidades = _cidades(ufs[0]) if len(ufs) == 1 else None
        id_cidade = c4.selectbox(
            "Município (escolha 1 UF)", [None] + (cidades["id"].tolist() if cidades is not None else []),
            format_func=lambda i: "Todos" if i is None else
            cidades.set_index("id").loc[i, "nome"], disabled=cidades is None,
            placeholder="Todos")
        br = c5.number_input("BR", min_value=0, max_value=499, step=1, value=0, help="0 = todas")
        classificacoes = c6.multiselect("Classificação", db.CLASSIFICACOES, placeholder="Todas")
        c7, c8, c9 = st.columns([2, 1, 2])
        causas = opcoes(_catalogo("causa"))
        id_causa = c7.selectbox("Causa", [None] + list(causas),
                                format_func=lambda i: "Todas" if i is None else causas[i])
        so_principal = c8.checkbox("só como principal", value=False)
        tipos = opcoes(_catalogo("tipo_acidente"))
        id_tipo = c9.selectbox("Tipo de acidente (em qualquer ordem)", [None] + list(tipos),
                               format_func=lambda i: "Todos" if i is None else tipos[i])
        limite = st.slider("Máximo de linhas", 50, 1000, 300, step=50)
        enviou_acid = st.form_submit_button("Buscar", type="primary", icon=":material/search:")

    data_ini, data_fim = (periodo if isinstance(periodo, tuple) and len(periodo) == 2
                          else (ini_base, fim_base))
    filtros = {"data_ini": data_ini, "data_fim": data_fim, "ufs": ufs, "id_cidade": id_cidade,
               "br": br or None, "classificacoes": classificacoes, "id_causa": id_causa,
               "so_principal": so_principal, "id_tipo": id_tipo, "id_acidente": id_direto or None}
    resultado = resultado_da_aba("res_acidentes", enviou_acid,
                                 lambda lg: db.buscar_acidentes(filtros, limite, lg))

    if not resultado.empty:
        st.caption(f"{len(resultado)} acidente(s) exibido(s) — clique numa linha para abrir a ficha.")
        evento = st.dataframe(resultado, hide_index=True, width="stretch",
                              height=min(320, 40 + 35 * len(resultado)),
                              on_select="rerun", selection_mode="single-row",
                              column_config={"km": st.column_config.NumberColumn(format="%.1f")})
        linhas = evento.selection.rows if evento else []
        id_ficha = int(resultado.iloc[linhas[0]]["id"]) if linhas else None
    else:
        st.info("Nenhum acidente encontrado com esses filtros.")
        id_ficha = None

    # ---- ficha do acidente selecionado -------------------------------------
    if id_ficha:
        f = db.ficha_acidente(id_ficha, log)
        g = f["geral"].iloc[0]
        st.subheader(f"Acidente {g['id']} — {g['municipio']}/{g['uf']}")
        m1, m2, m3, m4, m5 = st.columns(5)
        m1.metric(f"Data ({g['dia_semana']})", f"{g['data']:%d/%m/%Y}")
        m2.metric("Pessoas", int(g["pessoas"]))
        m3.metric("Veículos", int(g["veiculos"]))
        m4.metric("Feridos", int(g["feridos"]))
        m5.metric("Óbitos", int(g["mortos"]))
        local = (f"BR-{int(g['br']):03d}, km {g['km']:.1f}" if pd.notna(g["br"])
                 else "sem BR informada")
        st.markdown(
            f"**Local:** {local} · sentido {g['sentido']} · pista {g['tipo_pista']} · "
            f"{g['uso_solo'].lower()}  \n"
            f"**Hora:** {g['horario']} · {g['fase_dia']} · tempo: {g['condicao_meteorologica']}  \n"
            f"**Classificação PRF:** {g['classificacao'] or '(não informada)'}  \n"
            f"**Unidade PRF:** {g['uop'] or '—'} / {g['delegacia'] or '—'} / "
            f"{g['superintendencia'] or '—'}")
        e1, e2, e3 = st.columns([3, 2, 1])
        e1.markdown("**Causas** (atributo multivalorado → causa_acidente)")
        e1.dataframe(f["causas"], hide_index=True, width="stretch")
        e2.markdown("**Sequência de tipos** (acidente_tipo)")
        e2.dataframe(f["tipos"], hide_index=True, width="stretch")
        e3.markdown("**Traçado**")
        e3.dataframe(f["tracados"], hide_index=True, width="stretch")
        v1, v2 = st.columns([2, 3])
        v1.markdown("**Veículos**")
        v1.dataframe(f["veiculos"], hide_index=True, width="stretch")
        v2.markdown("**Pessoas**")
        v2.dataframe(f["pessoas"], hide_index=True, width="stretch")
        st.map(f["geral"].rename(columns={"latitude": "lat", "longitude": "lon"})[["lat", "lon"]]
               .astype(float), zoom=11, height=260)

# -----------------------------------------------------------------------------
# Pessoas
# -----------------------------------------------------------------------------
with aba_pes:
    with st.form("filtro_pessoas"):
        c1, c2 = st.columns(2)
        periodo_p = c1.date_input("Período do acidente", (ini_base, fim_base), format="DD/MM/YYYY",
                                  key="per_p")
        ufs_p = c2.multiselect("UF", db.UFS, placeholder="Todas", key="uf_p")
        c3, c4, c5 = st.columns(3)
        envolvidos = c3.multiselect("Tipo de envolvido", db.TIPOS_ENVOLVIDO, placeholder="Todos")
        estados = c4.multiselect("Estado físico", db.ESTADOS_FISICOS, placeholder="Todos")
        sexos = c5.multiselect("Sexo", db.SEXOS, placeholder="Todos")
        idade = st.slider("Faixa de idade", 0, 110, (0, 110))
        enviou_pes = st.form_submit_button("Buscar pessoas", type="primary", icon=":material/search:")
    pi, pf = periodo_p if isinstance(periodo_p, tuple) and len(periodo_p) == 2 else (ini_base, fim_base)
    filtro_idade = idade != (0, 110)
    filtros_p = {"data_ini": pi, "data_fim": pf, "uf": ufs_p, "tipo_envolvido": envolvidos,
                 "estado_fisico": estados, "sexo": sexos,
                 "idade_min": idade[0] if filtro_idade else None,
                 "idade_max": idade[1] if filtro_idade else None}
    pessoas = resultado_da_aba("res_pessoas", enviou_pes,
                               lambda lg: db.buscar_pessoas(filtros_p, 500, lg))
    st.caption(f"{len(pessoas)} pessoa(s) (máx. 500). Pedestres e testemunhas não têm veículo.")
    st.dataframe(pessoas, hide_index=True, width="stretch", height=380)

# -----------------------------------------------------------------------------
# Veículos
# -----------------------------------------------------------------------------
with aba_vei:
    tipos_v = opcoes(_catalogo("tipo_veiculo"))
    with st.form("filtro_veiculos"):
        c1, c2 = st.columns(2)
        periodo_v = c1.date_input("Período do acidente", (ini_base, fim_base), format="DD/MM/YYYY",
                                  key="per_v")
        ids_tipo = c2.multiselect("Tipo de veículo", list(tipos_v), format_func=tipos_v.get,
                                  placeholder="Todos")
        c3, c4 = st.columns(2)
        marca = c3.text_input("Marca/modelo contém", placeholder="ex.: HONDA")
        anos = c4.slider("Ano de fabricação", 1900, 2025, (1900, 2025))
        enviou_vei = st.form_submit_button("Buscar veículos", type="primary", icon=":material/search:")
    vi, vf = periodo_v if isinstance(periodo_v, tuple) and len(periodo_v) == 2 else (ini_base, fim_base)
    filtro_ano = anos != (1900, 2025)
    filtros_v = {"data_ini": vi, "data_fim": vf, "ids_tipo": ids_tipo, "marca": marca.strip(),
                 "ano_min": anos[0] if filtro_ano else None,
                 "ano_max": anos[1] if filtro_ano else None}
    veiculos = resultado_da_aba("res_veiculos", enviou_vei,
                                lambda lg: db.buscar_veiculos(filtros_v, 500, lg))
    st.caption(f"{len(veiculos)} veículo(s) (máx. 500). Ocupantes = 0 → veículo sem pessoa registrada.")
    st.dataframe(veiculos, hide_index=True, width="stretch", height=380)

# -----------------------------------------------------------------------------
# Causas
# -----------------------------------------------------------------------------
with aba_cau:
    with st.form("filtro_causas"):
        periodo_c = st.date_input("Período", (ini_base, fim_base), format="DD/MM/YYYY", key="per_c")
        enviou_cau = st.form_submit_button("Atualizar", type="primary", icon=":material/search:")
    ci, cf = periodo_c if isinstance(periodo_c, tuple) and len(periodo_c) == 2 else (ini_base, fim_base)
    causas_df = resultado_da_aba("res_causas", enviou_cau, lambda lg: db.resumo_causas(ci, cf, lg))
    st.caption("Catálogo das 70 causas e quantas vezes cada uma foi apontada no período "
               "(como principal ou secundária).")
    st.dataframe(causas_df, hide_index=True, width="stretch", height=420,
                 column_config={"como_principal": st.column_config.ProgressColumn(
                     "como_principal", format="%d", min_value=0,
                     max_value=int(causas_df["como_principal"].max() or 1)
                     if not causas_df.empty else 1)})

mostrar_sql(log)
