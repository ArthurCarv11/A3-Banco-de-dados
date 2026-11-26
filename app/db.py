"""
UNIFACS — Projeto Integrador de Banco de Dados — A3
Time Índice — Grupo 4 | Cenário: USUPORT

db.py — CAMADA DE ACESSO AO BANCO (todo o SQL da aplicação está aqui).

Princípios:
  * SQL explícito, escrito à mão, sem ORM.
  * SEMPRE parametrizado: os valores vão separados do texto do SQL
    (marcadores %s), e quem monta o comando final é o driver
    mysql-connector-python. Isso impede SQL injection.
  * Cada função recebe uma lista `log`; toda instrução executada é
    anotada ali como (sql, parâmetros), e as telas mostram esse log no
    expander "SQL executado".
  * Escritas (inserção e exclusão) acontecem dentro de UMA transação:
    ou tudo é gravado (COMMIT), ou nada (ROLLBACK).
  * A conexão é configurada por variáveis de ambiente (arquivo .env),
    nunca com senha no código.
"""

from __future__ import annotations

import os
import re
from contextlib import contextmanager
from datetime import date, timedelta
from decimal import Decimal
from pathlib import Path

import mysql.connector
import pandas as pd
from mysql.connector import pooling

RAIZ = Path(__file__).resolve().parent.parent          # pasta do projeto
ARQUIVO_DQL = RAIZ / "sql" / "06_dql_consultas.sql"     # fonte única da DQL
ID_INICIAL_SISTEMA = 9_000_001                          # faixa reservada (ver 03_carga.sql)


# =============================================================================
# 1. Configuração e conexão
# =============================================================================
def _carregar_env(caminho: Path = RAIZ / ".env") -> None:
    """Lê o arquivo .env (CHAVE=valor por linha) sem sobrescrever variáveis
    que já existam no ambiente. Implementação mínima para não depender de
    bibliotecas extras."""
    if not caminho.exists():
        return
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        os.environ.setdefault(chave.strip(), valor.strip().strip('"').strip("'"))


def configuracao() -> dict:
    """Parâmetros de conexão vindos do ambiente (.env)."""
    _carregar_env()
    return {
        "host": os.getenv("DB_HOST", "127.0.0.1"),
        "port": int(os.getenv("DB_PORT", "3306")),
        "user": os.getenv("DB_USER", "usuport_app"),
        "password": os.getenv("DB_PASSWORD", ""),
        "database": os.getenv("DB_NAME", "usuport"),
        "charset": "utf8mb4",
        "collation": "utf8mb4_0900_ai_ci",
    }


_pool: pooling.MySQLConnectionPool | None = None


def _obter_pool() -> pooling.MySQLConnectionPool:
    """Cria (uma única vez) um pool de conexões reaproveitáveis."""
    global _pool
    if _pool is None:
        _pool = pooling.MySQLConnectionPool(pool_name="usuport", pool_size=5,
                                            pool_reset_session=True, **configuracao())
    return _pool


@contextmanager
def conexao():
    """Empresta uma conexão do pool e a devolve ao final (with conexao() as cn)."""
    cn = _obter_pool().get_connection()
    try:
        cur = cn.cursor()
        cur.execute("SET lc_time_names = 'pt_BR'")   # nomes de dia/mês em português
        cur.close()
        yield cn
    finally:
        cn.close()                                   # no pool, close() = devolver


def _registrar(log: list | None, sql: str, params=None) -> None:
    """Anota a instrução executada para exibição no expander 'SQL executado'."""
    if log is not None:
        log.append((_limpar(sql), params))


def _limpar(sql: str) -> str:
    """Remove a indentação comum do texto SQL (só para exibição)."""
    linhas = sql.strip("\n").splitlines()
    recuo = min((len(l) - len(l.lstrip()) for l in linhas if l.strip()), default=0)
    return "\n".join(l[recuo:] for l in linhas)


def _para_dataframe(linhas: list, colunas: list) -> pd.DataFrame:
    """Converte o resultado do cursor em DataFrame, ajustando dois tipos do
    driver para exibição: DECIMAL (SUM/AVG) → número e TIME → 'HH:MM'."""
    df = pd.DataFrame(linhas, columns=colunas)
    for col in df.columns:
        amostra = df[col].dropna()
        if amostra.empty:
            continue
        primeiro = amostra.iloc[0]
        if isinstance(primeiro, Decimal):
            df[col] = pd.to_numeric(df[col])
        elif isinstance(primeiro, timedelta):
            df[col] = df[col].map(lambda t: None if t is None else
                                  f"{int(t.total_seconds()) // 3600:02d}:{int(t.total_seconds()) % 3600 // 60:02d}")
    return df


def consultar(sql: str, params: tuple | dict | None = None, log: list | None = None) -> pd.DataFrame:
    """Executa um SELECT parametrizado e devolve um DataFrame."""
    _registrar(log, sql, params)
    with conexao() as cn:
        cur = cn.cursor()
        cur.execute(sql, params or ())
        colunas = [c[0] for c in cur.description]
        linhas = cur.fetchall()
        cur.close()
    return _para_dataframe(linhas, colunas)


def testar_conexao() -> tuple[bool, str]:
    """Usado na barra lateral: devolve (ok, mensagem)."""
    try:
        df = consultar("SELECT VERSION() AS versao, @@hostname AS servidor, DATABASE() AS banco")
        r = df.iloc[0]
        return True, f"MySQL {r.versao} em {r.servidor} — banco {r.banco}"
    except mysql.connector.Error as erro:
        return False, f"Sem conexão: {erro.msg}"


# =============================================================================
# 2. Catálogos e listas para os filtros/formulários
# =============================================================================
# Nome de tabela não pode ser parâmetro (%s). Por isso há um SQL FIXO por
# catálogo, escolhido por chave — nunca concatenamos texto vindo da tela.
SQL_CATALOGOS = {
    "causa":                  "SELECT id, descricao FROM causa ORDER BY descricao",
    "tipo_acidente":          "SELECT id, descricao FROM tipo_acidente ORDER BY descricao",
    "tracado":                "SELECT id, descricao FROM tracado ORDER BY descricao",
    "tipo_veiculo":           "SELECT id, descricao FROM tipo_veiculo ORDER BY descricao",
    "condicao_meteorologica": "SELECT id, descricao FROM condicao_meteorologica ORDER BY descricao",
    "fase_dia":               "SELECT id, descricao FROM fase_dia ORDER BY id",
    "superintendencia":       "SELECT id, sigla AS descricao FROM superintendencia ORDER BY sigla",
}

# Domínios das colunas com CHECK (os mesmos valores do 01_ddl.sql).
UFS = ["AC", "AL", "AM", "AP", "BA", "CE", "DF", "ES", "GO", "MA", "MG", "MS", "MT", "PA",
       "PB", "PE", "PI", "PR", "RJ", "RN", "RO", "RR", "RS", "SC", "SE", "SP", "TO"]
SENTIDOS = ["Crescente", "Decrescente", "Não Informado"]
TIPOS_PISTA = ["Simples", "Dupla", "Múltipla"]
USOS_SOLO = ["Urbano", "Rural"]
CLASSIFICACOES = ["Sem Vítimas", "Com Vítimas Feridas", "Com Vítimas Fatais"]
TIPOS_ENVOLVIDO = ["Condutor", "Passageiro", "Pedestre", "Testemunha", "Cavaleiro"]
ENVOLVIDOS_COM_VEICULO = {"Condutor", "Passageiro"}
ESTADOS_FISICOS = ["Ileso", "Lesões Leves", "Lesões Graves", "Óbito", "Não Informado"]
SEXOS = ["Masculino", "Feminino", "Não Informado", "Ignorado"]


def catalogo(nome: str, log: list | None = None) -> pd.DataFrame:
    """Devolve (id, descricao) de um catálogo da lista SQL_CATALOGOS."""
    return consultar(SQL_CATALOGOS[nome], log=log)


def cidades_da_uf(uf: str, log: list | None = None) -> pd.DataFrame:
    sql = "SELECT id, nome FROM cidade WHERE uf = %s ORDER BY nome"
    return consultar(sql, (uf,), log)


def delegacias_da_superintendencia(id_sup: int, log: list | None = None) -> pd.DataFrame:
    sql = "SELECT id, sigla FROM delegacia WHERE id_superintendencia = %s ORDER BY sigla"
    return consultar(sql, (id_sup,), log)


def uops_da_delegacia(id_del: int, log: list | None = None) -> pd.DataFrame:
    sql = "SELECT id, sigla FROM uop WHERE id_delegacia = %s ORDER BY sigla"
    return consultar(sql, (id_del,), log)


def coordenadas_sugeridas(id_cidade: int, log: list | None = None) -> tuple[float, float] | None:
    """Ponto médio dos acidentes já registrados no município (sugestão para o
    formulário de inserção). None se a cidade ainda não tem acidentes."""
    sql = "SELECT AVG(latitude) AS lat, AVG(longitude) AS lon FROM acidente WHERE id_cidade = %s"
    r = consultar(sql, (id_cidade,), log).iloc[0]
    return None if pd.isna(r["lat"]) else (round(float(r["lat"]), 6), round(float(r["lon"]), 6))


def faixa_de_datas(log: list | None = None) -> tuple[date, date]:
    df = consultar("SELECT MIN(data) AS ini, MAX(data) AS fim FROM acidente", log=log)
    return df.iloc[0]["ini"], df.iloc[0]["fim"]


# =============================================================================
# 3. READ — consulta de acidentes, pessoas, veículos e causas
# =============================================================================
def buscar_acidentes(f: dict, limite: int = 300, log: list | None = None) -> pd.DataFrame:
    """Filtra acidentes em DUAS etapas (desempenho):
       1) acha os ids que atendem aos filtros, usando índices (data, FKs);
       2) busca a ficha resumida desses ids na view vw_acidente_detalhe.
    O WHERE é montado só com trechos FIXOS; os valores vão em `params`."""
    where = ["a.data BETWEEN %s AND %s"]
    params: list = [f["data_ini"], f["data_fim"]]
    if f.get("id_acidente"):
        where.append("a.id = %s")
        params.append(int(f["id_acidente"]))
    if f.get("ufs"):
        where.append("c.uf IN (" + ", ".join(["%s"] * len(f["ufs"])) + ")")
        params += list(f["ufs"])
    if f.get("id_cidade"):
        where.append("a.id_cidade = %s")
        params.append(int(f["id_cidade"]))
    if f.get("br"):
        where.append("a.br = %s")
        params.append(int(f["br"]))
    if f.get("classificacoes"):
        where.append("a.classificacao IN (" + ", ".join(["%s"] * len(f["classificacoes"])) + ")")
        params += list(f["classificacoes"])
    if f.get("id_causa"):
        # EXISTS: "existe uma linha em causa_acidente ligando este acidente à causa"
        so_principal = " AND ca.principal = TRUE" if f.get("so_principal") else ""
        where.append("EXISTS (SELECT 1 FROM causa_acidente ca WHERE ca.id_acidente = a.id"
                     " AND ca.id_causa = %s" + so_principal + ")")
        params.append(int(f["id_causa"]))
    if f.get("id_tipo"):
        where.append("EXISTS (SELECT 1 FROM acidente_tipo at1 WHERE at1.id_acidente = a.id"
                     " AND at1.id_tipo = %s)")
        params.append(int(f["id_tipo"]))

    sql_ids = (
        "SELECT a.id\n"
        "  FROM acidente a\n"
        "  JOIN cidade c ON c.id = a.id_cidade\n"
        " WHERE " + "\n   AND ".join(where) + "\n"
        " ORDER BY a.data DESC, a.horario DESC, a.id DESC\n"
        " LIMIT %s"
    )
    ids = consultar(sql_ids, tuple(params + [limite]), log)["id"].tolist()
    if not ids:
        return pd.DataFrame()

    sql_ficha = (
        "SELECT id, data, dia_semana, horario, uf, municipio, br, km, classificacao,\n"
        "       causa_principal, tipos, veiculos, pessoas, feridos, mortos\n"
        "  FROM vw_acidente_detalhe\n"
        " WHERE id IN (" + ", ".join(["%s"] * len(ids)) + ")\n"
        " ORDER BY data DESC, horario DESC, id DESC"
    )
    return consultar(sql_ficha, tuple(ids), log)


def contar_acidentes_filtrados(f: dict, log: list | None = None) -> int:
    """Total de acidentes no período e UFs (sem limite), para o cabeçalho."""
    where = ["a.data BETWEEN %s AND %s"]
    params: list = [f["data_ini"], f["data_fim"]]
    if f.get("ufs"):
        where.append("c.uf IN (" + ", ".join(["%s"] * len(f["ufs"])) + ")")
        params += list(f["ufs"])
    sql = ("SELECT COUNT(*) AS total FROM acidente a JOIN cidade c ON c.id = a.id_cidade WHERE "
           + " AND ".join(where))
    return int(consultar(sql, tuple(params), log).iloc[0]["total"])


def ficha_acidente(id_acidente: int, log: list | None = None) -> dict:
    """Todas as partes de um acidente: dados gerais (view), causas, tipos,
    traçados, veículos e pessoas — cada parte vem de uma tabela do modelo."""
    p = (id_acidente,)
    geral = consultar("SELECT * FROM vw_acidente_detalhe WHERE id = %s", p, log)
    causas = consultar(
        """
        SELECT c.descricao AS causa,
               IF(ca.principal, 'Sim', 'Não') AS principal
          FROM causa_acidente ca
          JOIN causa c ON c.id = ca.id_causa
         WHERE ca.id_acidente = %s
         ORDER BY ca.principal DESC, c.descricao
        """, p, log)
    tipos = consultar(
        """
        SELECT at1.ordem, t.descricao AS tipo
          FROM acidente_tipo at1
          JOIN tipo_acidente t ON t.id = at1.id_tipo
         WHERE at1.id_acidente = %s
         ORDER BY at1.ordem
        """, p, log)
    tracados = consultar(
        """
        SELECT tr.descricao AS tracado
          FROM acidente_tracado x
          JOIN tracado tr ON tr.id = x.id_tracado
         WHERE x.id_acidente = %s
         ORDER BY tr.descricao
        """, p, log)
    veiculos = consultar(
        """
        SELECT v.id AS id_veiculo, tv.descricao AS tipo, v.marca, v.ano_fabricacao,
               COUNT(p.pesid) AS ocupantes_registrados
          FROM veiculo v
          JOIN tipo_veiculo tv ON tv.id = v.id_tipo_veiculo
          LEFT JOIN pessoa p   ON p.id_veiculo = v.id
         WHERE v.id_acidente = %s
         GROUP BY v.id, tv.descricao, v.marca, v.ano_fabricacao
         ORDER BY v.id
        """, p, log)
    pessoas = consultar(
        """
        SELECT p.pesid, p.tipo_envolvido, p.estado_fisico, p.idade, p.sexo,
               p.id_veiculo, tv.descricao AS tipo_veiculo
          FROM pessoa p
          LEFT JOIN veiculo v       ON v.id  = p.id_veiculo
          LEFT JOIN tipo_veiculo tv ON tv.id = v.id_tipo_veiculo
         WHERE p.id_acidente = %s
         ORDER BY p.id_veiculo IS NULL, p.id_veiculo, p.tipo_envolvido, p.pesid
        """, p, log)
    return {"geral": geral, "causas": causas, "tipos": tipos, "tracados": tracados,
            "veiculos": veiculos, "pessoas": pessoas}


def buscar_pessoas(f: dict, limite: int = 500, log: list | None = None) -> pd.DataFrame:
    """Pessoas envolvidas, com filtros por período, UF, papel, estado físico,
    sexo e faixa de idade (view vw_pessoa_detalhe)."""
    where = ["data BETWEEN %s AND %s"]
    params: list = [f["data_ini"], f["data_fim"]]
    for coluna in ("uf", "tipo_envolvido", "estado_fisico", "sexo"):
        valores = f.get(coluna)
        if valores:
            where.append(f"{coluna} IN (" + ", ".join(["%s"] * len(valores)) + ")")  # coluna: lista fixa acima
            params += list(valores)
    if f.get("idade_min") is not None:
        where.append("idade >= %s")
        params.append(int(f["idade_min"]))
    if f.get("idade_max") is not None:
        where.append("idade <= %s")
        params.append(int(f["idade_max"]))
    sql = ("SELECT pesid, id_acidente, data, uf, municipio, tipo_envolvido, estado_fisico,\n"
           "       idade, sexo, id_veiculo, tipo_veiculo\n"
           "  FROM vw_pessoa_detalhe\n"
           " WHERE " + "\n   AND ".join(where) + "\n"
           " ORDER BY data DESC, pesid DESC\n"
           " LIMIT %s")
    return consultar(sql, tuple(params + [limite]), log)


def buscar_veiculos(f: dict, limite: int = 500, log: list | None = None) -> pd.DataFrame:
    """Veículos por tipo, marca (contém), faixa de ano e período do acidente.
    LEFT JOIN em pessoa para contar ocupantes (0 = veículo sem pessoa)."""
    where = ["a.data BETWEEN %s AND %s"]
    params: list = [f["data_ini"], f["data_fim"]]
    if f.get("ids_tipo"):
        where.append("v.id_tipo_veiculo IN (" + ", ".join(["%s"] * len(f["ids_tipo"])) + ")")
        params += [int(x) for x in f["ids_tipo"]]
    if f.get("marca"):
        where.append("v.marca LIKE %s")
        params.append(f"%{f['marca']}%")
    if f.get("ano_min"):
        where.append("v.ano_fabricacao >= %s")
        params.append(int(f["ano_min"]))
    if f.get("ano_max"):
        where.append("v.ano_fabricacao <= %s")
        params.append(int(f["ano_max"]))
    sql = ("SELECT v.id AS id_veiculo, v.id_acidente, a.data, tv.descricao AS tipo,\n"
           "       v.marca, v.ano_fabricacao, COUNT(p.pesid) AS ocupantes,\n"
           "       SUM(p.estado_fisico = 'Óbito') AS obitos\n"
           "  FROM veiculo v\n"
           "  JOIN acidente a      ON a.id  = v.id_acidente\n"
           "  JOIN tipo_veiculo tv ON tv.id = v.id_tipo_veiculo\n"
           "  LEFT JOIN pessoa p   ON p.id_veiculo = v.id\n"
           " WHERE " + "\n   AND ".join(where) + "\n"
           " GROUP BY v.id, v.id_acidente, a.data, tv.descricao, v.marca, v.ano_fabricacao\n"
           " ORDER BY a.data DESC, v.id DESC\n"
           " LIMIT %s")
    return consultar(sql, tuple(params + [limite]), log)


def resumo_causas(data_ini: date, data_fim: date, log: list | None = None) -> pd.DataFrame:
    """Catálogo de causas com quantas vezes foi principal/secundária no período."""
    # LEFT JOIN com tabela derivada: causas sem ocorrência no período
    # continuam na lista (com zero), em vez de sumirem.
    sql = """
        SELECT c.id, c.descricao AS causa,
               COALESCE(SUM(x.principal = TRUE), 0)  AS como_principal,
               COALESCE(SUM(x.principal = FALSE), 0) AS como_secundaria,
               COUNT(x.id_acidente)                  AS total
          FROM causa c
          LEFT JOIN (SELECT ca.id_causa, ca.id_acidente, ca.principal
                       FROM causa_acidente ca
                       JOIN acidente a ON a.id = ca.id_acidente
                      WHERE a.data BETWEEN %s AND %s) x ON x.id_causa = c.id
         GROUP BY c.id, c.descricao
         ORDER BY como_principal DESC, total DESC
    """
    return consultar(sql, (data_ini, data_fim), log)


# =============================================================================
# 4. CREATE — cadastro de um acidente completo numa transação
# =============================================================================
def classificacao_calculada(pessoas: list[dict]) -> str:
    """Regra RN08: a classificação segue o estado físico mais grave."""
    estados = {p["estado_fisico"] for p in pessoas}
    if "Óbito" in estados:
        return "Com Vítimas Fatais"
    if estados & {"Lesões Leves", "Lesões Graves"}:
        return "Com Vítimas Feridas"
    return "Sem Vítimas"


def validar_novo_acidente(dados: dict, causas: list[int], principal: int | None,
                          tipos: list[int], tracados: list[int],
                          veiculos: list[dict], pessoas: list[dict]) -> list[str]:
    """Regras de negócio checadas ANTES de abrir a transação (o banco também
    as garante por CHECK/FK/UNIQUE; aqui é para dar mensagens amigáveis)."""
    erros = []
    if not causas:
        erros.append("Informe ao menos uma causa.")
    if principal is None or principal not in causas:
        erros.append("Marque exatamente uma causa principal entre as causas escolhidas.")
    if not tipos:
        erros.append("Informe ao menos um tipo de acidente (a ordem da lista é a ordem dos eventos).")
    if not tracados:
        erros.append("Informe ao menos um traçado da via.")
    if not pessoas:
        erros.append("Cadastre ao menos uma pessoa envolvida.")
    if dados.get("km") is not None and not dados.get("br"):
        erros.append("Só existe km quando há BR informada.")
    rotulos = {v["rotulo"] for v in veiculos}
    for i, p in enumerate(pessoas, start=1):
        tem_veiculo = bool(p.get("veiculo"))
        if p["tipo_envolvido"] in ENVOLVIDOS_COM_VEICULO and not tem_veiculo:
            erros.append(f"Pessoa {i}: {p['tipo_envolvido']} precisa estar em um veículo.")
        if p["tipo_envolvido"] not in ENVOLVIDOS_COM_VEICULO and tem_veiculo:
            erros.append(f"Pessoa {i}: {p['tipo_envolvido']} não ocupa veículo.")
        if tem_veiculo and p["veiculo"] not in rotulos:
            erros.append(f"Pessoa {i}: veículo '{p['veiculo']}' não existe neste acidente.")
        if p.get("idade") is not None and not (0 <= int(p["idade"]) <= 110):
            erros.append(f"Pessoa {i}: idade deve estar entre 0 e 110.")
    return erros


SQL_INSERT_ACIDENTE = """
    INSERT INTO acidente (data, horario, br, km, sentido, tipo_pista, uso_solo, classificacao,
                          latitude, longitude, id_cidade, id_condicao, id_fase_dia,
                          id_uop, id_delegacia, id_superintendencia)
    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
"""
SQL_INSERT_CAUSA = "INSERT INTO causa_acidente (id_acidente, id_causa, principal) VALUES (%s, %s, %s)"
SQL_INSERT_TIPO = "INSERT INTO acidente_tipo (id_acidente, ordem, id_tipo) VALUES (%s, %s, %s)"
SQL_INSERT_TRACADO = "INSERT INTO acidente_tracado (id_acidente, id_tracado) VALUES (%s, %s)"
SQL_INSERT_VEICULO = """
    INSERT INTO veiculo (id_acidente, id_tipo_veiculo, marca, ano_fabricacao)
    VALUES (%s, %s, %s, %s)
"""
SQL_INSERT_PESSOA = """
    INSERT INTO pessoa (id_acidente, id_veiculo, tipo_envolvido, estado_fisico, idade, sexo)
    VALUES (%s, %s, %s, %s, %s, %s)
"""


def inserir_acidente(dados: dict, causas: list[int], principal: int, tipos: list[int],
                     tracados: list[int], veiculos: list[dict], pessoas: list[dict],
                     log: list | None = None) -> int:
    """Grava o acidente e TODOS os dependentes numa única transação.
    Ordem = ordem das FKs: acidente → causas/tipos/traçados → veículos → pessoas.
    Se qualquer INSERT falhar (CHECK, FK, UNIQUE...), faz ROLLBACK e repassa o erro.
    Devolve o id gerado para o novo acidente (faixa >= 9.000.001)."""
    with conexao() as cn:
        cur = cn.cursor()
        try:
            cn.start_transaction()
            _registrar(log, "START TRANSACTION")

            # 1) acidente — id gerado pelo AUTO_INCREMENT
            p_acidente = (dados["data"], dados["horario"], dados.get("br"), dados.get("km"),
                          dados["sentido"], dados["tipo_pista"], dados["uso_solo"],
                          classificacao_calculada(pessoas), dados["latitude"], dados["longitude"],
                          dados["id_cidade"], dados["id_condicao"], dados["id_fase_dia"],
                          dados.get("id_uop"), dados.get("id_delegacia"),
                          dados.get("id_superintendencia"))
            cur.execute(SQL_INSERT_ACIDENTE, p_acidente)
            _registrar(log, SQL_INSERT_ACIDENTE, p_acidente)
            id_acidente = cur.lastrowid

            # 2) causas (uma é a principal)
            linhas = [(id_acidente, c, c == principal) for c in causas]
            cur.executemany(SQL_INSERT_CAUSA, linhas)
            _registrar(log, SQL_INSERT_CAUSA, linhas)

            # 3) tipos — a posição na lista vira a "ordem" (1, 2, 3...)
            linhas = [(id_acidente, ordem, t) for ordem, t in enumerate(tipos, start=1)]
            cur.executemany(SQL_INSERT_TIPO, linhas)
            _registrar(log, SQL_INSERT_TIPO, linhas)

            # 4) traçados
            linhas = [(id_acidente, t) for t in sorted(set(tracados))]
            cur.executemany(SQL_INSERT_TRACADO, linhas)
            _registrar(log, SQL_INSERT_TRACADO, linhas)

            # 5) veículos — um INSERT por veículo para guardar o id gerado
            id_por_rotulo = {}
            for v in veiculos:
                pv = (id_acidente, v["id_tipo_veiculo"], v.get("marca") or None,
                      v.get("ano_fabricacao"))
                cur.execute(SQL_INSERT_VEICULO, pv)
                _registrar(log, SQL_INSERT_VEICULO, pv)
                id_por_rotulo[v["rotulo"]] = cur.lastrowid

            # 6) pessoas — o rótulo do veículo (V1, V2...) vira o id real
            for p in pessoas:
                pp = (id_acidente, id_por_rotulo.get(p.get("veiculo")), p["tipo_envolvido"],
                      p["estado_fisico"], p.get("idade"), p["sexo"])
                cur.execute(SQL_INSERT_PESSOA, pp)
                _registrar(log, SQL_INSERT_PESSOA, pp)

            cn.commit()
            _registrar(log, "COMMIT")
            return id_acidente
        except mysql.connector.Error:
            cn.rollback()
            _registrar(log, "ROLLBACK")
            raise
        finally:
            cur.close()


# =============================================================================
# 5. DELETE — exclusão física de um acidente e de seus dependentes
# =============================================================================
SQL_RESUMO_EXCLUSAO = """
    SELECT (SELECT COUNT(*) FROM acidente         WHERE id          = %s) AS acidente,
           (SELECT COUNT(*) FROM pessoa           WHERE id_acidente = %s) AS pessoas,
           (SELECT COUNT(*) FROM veiculo          WHERE id_acidente = %s) AS veiculos,
           (SELECT COUNT(*) FROM causa_acidente   WHERE id_acidente = %s) AS causas,
           (SELECT COUNT(*) FROM acidente_tipo    WHERE id_acidente = %s) AS tipos,
           (SELECT COUNT(*) FROM acidente_tracado WHERE id_acidente = %s) AS tracados
"""

# Filhos ANTES do pai: as FKs são RESTRICT, então apagar o acidente primeiro
# daria erro 1451. pessoa vem antes de veiculo porque pessoa referencia veiculo.
SQL_EXCLUSAO = [
    ("pessoa",           "DELETE FROM pessoa           WHERE id_acidente = %s"),
    ("veiculo",          "DELETE FROM veiculo          WHERE id_acidente = %s"),
    ("causa_acidente",   "DELETE FROM causa_acidente   WHERE id_acidente = %s"),
    ("acidente_tipo",    "DELETE FROM acidente_tipo    WHERE id_acidente = %s"),
    ("acidente_tracado", "DELETE FROM acidente_tracado WHERE id_acidente = %s"),
    ("acidente",         "DELETE FROM acidente         WHERE id          = %s"),
]


def resumo_exclusao(id_acidente: int, log: list | None = None) -> dict:
    """Quantas linhas de cada tabela serão apagadas (mostrado antes de confirmar)."""
    df = consultar(SQL_RESUMO_EXCLUSAO, (id_acidente,) * 6, log)
    return {k: int(v) for k, v in df.iloc[0].items()}


def excluir_acidente(id_acidente: int, log: list | None = None) -> dict:
    """Apaga o acidente e os dependentes numa transação. Devolve quantas
    linhas cada DELETE removeu. Qualquer erro → ROLLBACK (nada é apagado)."""
    removidas = {}
    with conexao() as cn:
        cur = cn.cursor()
        try:
            cn.start_transaction()
            _registrar(log, "START TRANSACTION")
            for tabela, sql in SQL_EXCLUSAO:
                cur.execute(sql, (id_acidente,))
                _registrar(log, sql, (id_acidente,))
                removidas[tabela] = cur.rowcount
            cn.commit()
            _registrar(log, "COMMIT")
        except mysql.connector.Error:
            cn.rollback()
            _registrar(log, "ROLLBACK")
            raise
        finally:
            cur.close()
    return removidas


def acidentes_do_sistema(log: list | None = None) -> pd.DataFrame:
    """Acidentes cadastrados pelo próprio sistema (faixa >= 9.000.001)."""
    sql = """
        SELECT id, data, horario, municipio, uf, classificacao, causa_principal, pessoas
          FROM vw_acidente_detalhe
         WHERE id >= %s
         ORDER BY id DESC
    """
    return consultar(sql, (ID_INICIAL_SISTEMA,), log)


# =============================================================================
# 6. PAINEL — consultas da DQL lidas do arquivo sql/06_dql_consultas.sql
# =============================================================================
_MARCADOR = re.compile(r"^-- @Q(\d+) \| (.+)$", re.MULTILINE)


def carregar_consultas_dql(caminho: Path = ARQUIVO_DQL) -> list[dict]:
    """Separa o arquivo 06 pelos marcadores '-- @Qnn | título'. Para cada
    consulta devolve: codigo, titulo, descricao (comentários) e sql."""
    texto = caminho.read_text(encoding="utf-8")
    marcas = list(_MARCADOR.finditer(texto))
    consultas = []
    for i, m in enumerate(marcas):
        fim = marcas[i + 1].start() if i + 1 < len(marcas) else len(texto)
        bloco = texto[m.end():fim].strip("\n")
        comentarios, sql = [], []
        for linha in bloco.splitlines():
            if not sql and linha.startswith("--"):
                comentarios.append(linha[2:].strip())
            else:
                sql.append(linha)
        corpo = "\n".join(sql).strip()
        corpo = corpo[: corpo.rfind(";")] if ";" in corpo else corpo   # tira o ";" final
        consultas.append({"codigo": f"Q{m.group(1)}", "titulo": m.group(2).strip(),
                          "descricao": "\n".join(comentarios), "sql": corpo})
    return consultas


def executar_dql(sql: str, data_ini: date, data_fim: date, id_acidente: int = 571778,
                 log: list | None = None) -> pd.DataFrame:
    """Define as variáveis de sessão usadas no arquivo 06 (@data_ini,
    @data_fim, @id_acidente) — de forma parametrizada — e executa a consulta
    na MESMA conexão (variáveis de sessão só valem dentro dela)."""
    sql_set = "SET @data_ini = %s, @data_fim = %s, @id_acidente = %s"
    params = (data_ini, data_fim, id_acidente)
    with conexao() as cn:
        cur = cn.cursor()
        cur.execute(sql_set, params)
        _registrar(log, sql_set, params)
        cur.execute(sql)
        _registrar(log, sql)
        colunas = [c[0] for c in cur.description]
        linhas = cur.fetchall()
        cur.close()
    return _para_dataframe(linhas, colunas)


def indicadores(data_ini: date, data_fim: date, log: list | None = None) -> dict:
    """Números de capa do painel no período."""
    sql = """
        SELECT COUNT(DISTINCT a.id)                         AS acidentes,
               COUNT(p.pesid)                               AS pessoas,
               SUM(p.estado_fisico = 'Ileso')               AS ilesos,
               SUM(p.estado_fisico = 'Óbito')               AS obitos,
               SUM(p.estado_fisico = 'Lesões Graves')       AS feridos_graves,
               SUM(p.estado_fisico = 'Lesões Leves')        AS feridos_leves
          FROM acidente a
          LEFT JOIN pessoa p ON p.id_acidente = a.id
         WHERE a.data BETWEEN %s AND %s
    """
    df = consultar(sql, (data_ini, data_fim), log)
    return {k: int(v or 0) for k, v in df.iloc[0].items()}
