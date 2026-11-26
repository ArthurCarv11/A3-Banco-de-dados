# Time Índice — Grupo 4 — Cenário USUPORT

**UNIFACS — Campus CTN, Salvador** · UC Projeto Integrador de Banco de Dados — Avaliação A3
Professores: Sergio Spinola e Alexandre Anunciação

| Integrante | RA |
|---|---|
| Filipe Albuquerque Oliveira | 12725146899 |
| Guilherme Cabral Teixeira | 12725188306 |
| Arthur Cordeiro de Carvalho Cruz | 12725113247 |
| Miguel Lima Quadros Gomes | 1272514349 |
| Alisson Sousa Santos | 12725158318 |
| Cláudio Roberto Cruz Santiago Santos | 12725151039 |

**Sistema de gestão e análise de sinistros em rodovias federais.** A planilha da PRF de 2024 (603.215 linhas redundantes) vira um banco MySQL 8 normalizado até a 3FN, com **16 tabelas** e **5 views**. O banco roda numa VM do VirtualBox, é inspecionado pelo DBeaver e é manipulado por um app CRUD em Python + Streamlit com SQL puro e parametrizado.

## Estrutura

```
├── README.md                    ← este arquivo
├── requirements.txt             ← dependências do app (streamlit, mysql-connector-python, pandas, altair)
├── .env.example                 ← modelo de configuração da conexão (copie para .env)
├── sql/
│   ├── 00_completo.sql          ← pacote ÚNICO (01..07 concatenados) — gerado por scripts/montar_sql_completo.py
│   ├── 01_ddl.sql               ← CREATE DATABASE, DROP/CREATE das 16 tabelas, PK/FK/UNIQUE/CHECK, índices, ALTER TABLE
│   ├── 02_staging.sql           ← staging + LOAD DATA LOCAL INFILE (latin1)
│   ├── 03_carga.sql             ← INSERT…SELECT da staging para as 16 tabelas + regras de limpeza R0–R11
│   ├── 04_validacao.sql         ← esperado × obtido (contagens, limpeza, regras de negócio) — 0 divergências
│   ├── 05_dml_exemplos.sql      ← INSERT fictício completo, UPDATEs, DELETE controlado em transação
│   ├── 06_dql_consultas.sql     ← 18 consultas gerenciais (JOINs, GROUP BY, COUNT, AVG, filtro temporal)
│   └── 07_views.sql             ← vw_acidente_detalhe, vw_acidente_totais, vw_pessoa_detalhe…
├── app/                         ← aplicação Streamlit (CRUD + painel)
│   ├── app.py                   ← entrada e navegação
│   ├── db.py                    ← TODO o SQL da aplicação (camada de acesso ao banco)
│   ├── componentes.py           ← expander "SQL executado", mensagens de erro
│   └── paginas/                 ← consulta.py · insercao.py · exclusao.py · painel.py
├── scripts/
│   ├── carregar_staging.py      ← alternativa ao LOAD DATA (carga da staging em Python)
│   ├── montar_sql_completo.py   ← gera sql/00_completo.sql
│   ├── gerar_dicionario.py      ← gera docs/dicionario_dados.md do INFORMATION_SCHEMA
│   ├── gerar_diagramas.py       ← gera docs/der_conceitual.png e docs/der_logico.png (Graphviz)
│   ├── capturar_telas.py        ← capturas do app para o relatório (Playwright + Edge)
│   ├── gerar_relatorio.py       ← docs/relatorio.md → docs/relatorio.pdf
│   └── empacotar_entrega.py     ← gera o .zip de entrega
├── docs/
│   ├── relatorio.pdf            ← RELATÓRIO TÉCNICO (entrega)
│   ├── versao2.md               ← projeto da versão 2: as 5 partes, riscos, testes e medições
│   ├── relatorio.md             ← fonte do relatório
│   ├── der_conceitual.png/.dot  ← DER conceitual (Chen) em alta resolução
│   ├── der_logico.png/.dot      ← modelo lógico (tabelas, PK/FK)
│   ├── requisitos_regras.md     ← requisitos funcionais/não funcionais e regras de negócio
│   ├── memorial_normalizacao.md ← 0FN → 1FN → 2FN → 3FN com exemplos reais
│   ├── dicionario_dados.md      ← tabelas, campos, tipos, restrições e finalidades
│   ├── infra_vm.md              ← VirtualBox + Ubuntu + MySQL 8 + DBeaver
│   ├── roteiro_apresentacao.md  ← roteiro de 15–20 min com as falas de cada integrante
│   ├── guia_arguicao.md         ← perguntas prováveis da banca e respostas
│   └── img/                     ← capturas de tela do app
├── certificados/README.md       ← status dos certificados Oracle Academy
└── dados/README.md              ← onde colocar o CSV (não vai no zip)
```

## Como reproduzir do zero

### 1. Banco de dados (na VM Ubuntu com MySQL 8)

Configuração da VM, rede, usuários e DBeaver: **`docs/infra_vm.md`**.

Coloque o CSV em `dados/acidentes2024_todas_causas_tipos_Usuport.csv` e, **na raiz do projeto**:

```bash
sudo mysql --local-infile=1 --default-character-set=utf8mb4 < sql/00_completo.sql
```

Cerca de 40 s depois o banco `usuport` está criado, carregado e validado (todas as linhas da validação `OK`). Para executar por etapas, rode `01` a `07` na ordem. Se o `LOAD DATA` não for permitido, use `python scripts/carregar_staging.py` no lugar do `02`.

### 2. Aplicação (no computador)

```bash
pip install -r requirements.txt
copy .env.example .env        # no Linux: cp .env.example .env
```

Edite o `.env` com o IP/porta da VM e a senha do `usuport_app`. Depois:

```bash
streamlit run app/app.py
```

O app abre em `http://localhost:8501`. A barra lateral mostra a versão do MySQL e o hostname do servidor conectado.

### 3. Regenerar a documentação (opcional)

Os scripts abaixo precisam do banco carregado e do `.env` configurado. O de diagramas usa o Graphviz local ou o Docker; o do relatório usa o Microsoft Edge para gerar o PDF.

```bash
python scripts/gerar_dicionario.py
python scripts/gerar_diagramas.py
python scripts/montar_sql_completo.py
python scripts/gerar_relatorio.py
python scripts/empacotar_entrega.py
```

## Resultados da carga (validados)

| Tabela | Linhas | Tabela | Linhas |
|---|---|---|---|
| acidente | 73.156 | causa_acidente | 111.307 |
| pessoa | 179.114 | acidente_tipo | 124.173 |
| veiculo | 139.617 | acidente_tracado | 93.850 |
| cidade | 1.873 | causa / tipo_acidente / tracado / tipo_veiculo | 70 / 17 / 12 / 25 |
| superintendencia / delegacia / uop | 28 / 152 / 394 | condicao_meteorologica / fase_dia | 10 / 4 |

A validação tem 57 verificações (contagens, regras de limpeza e regras de negócio) e terminou com **0 divergências**. Tudo foi testado num MySQL 8.0.46 em Docker antes de ir para a VM.
