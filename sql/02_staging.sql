-- =============================================================================
--  UNIFACS — Projeto Integrador de Banco de Dados — A3
--  Time Índice — Grupo 4 | Cenário: USUPORT
--  Arquivo: 02_staging.sql — área de preparação (staging) + carga bruta do CSV
-- -----------------------------------------------------------------------------
--  A planilha da PRF (0FN) é carregada SEM transformação numa tabela de
--  staging, com todas as colunas como texto. As transformações (limpeza,
--  separação do traçado, conversão de tipos) ficam no 03_carga.sql, em SQL
--  explícito, para que cada regra seja visível e auditável.
--
--  Formato do arquivo (conferido no perfilamento):
--    * codificação Latin-1 (ISO-8859-1)  → CHARACTER SET latin1
--    * separador ";"                     → FIELDS TERMINATED BY ';'
--    * textos entre aspas duplas         → OPTIONALLY ENCLOSED BY '"'
--    * fim de linha Windows (CRLF)       → LINES TERMINATED BY '\r\n'
--    * 1 linha de cabeçalho              → IGNORE 1 LINES
--    * 603.215 linhas de dados, 37 colunas
--    * ausência de valor vem como o texto NA ou N/A (tratado no 03_carga.sql)
--
--  COMO EXECUTAR (o caminho do arquivo é RELATIVO à pasta de onde o cliente
--  mysql foi chamado — rode a partir da raiz do projeto):
--     mysql --local-infile=1 -u root -p < sql/02_staging.sql
--  O servidor também precisa de local_infile = ON (ver abaixo e docs/infra_vm.md).
--  Se o LOAD DATA falhar (ex.: DBeaver sem permissão de arquivo local), use a
--  alternativa em Python:  python scripts/carregar_staging.py
-- =============================================================================

USE usuport;

-- Habilita a leitura de arquivos locais no servidor (exige usuário com
-- privilégio SYSTEM_VARIABLES_ADMIN, ex.: root). Na VM também pode ser
-- deixado fixo no mysqld.cnf com "local_infile = 1".
SET GLOBAL local_infile = 1;

DROP TABLE IF EXISTS stg_acidente_csv;

-- Uma coluna por coluna do CSV, todas texto, mesmos nomes do arquivo.
-- "linha" numera a ordem de leitura (rastreabilidade de cada registro).
CREATE TABLE stg_acidente_csv (
    linha                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id                     VARCHAR(12),
    pesid                  VARCHAR(12),
    data_inversa           VARCHAR(10),
    dia_semana             VARCHAR(15),
    horario                VARCHAR(8),
    uf                     VARCHAR(2),
    br                     VARCHAR(5),
    km                     VARCHAR(10),
    municipio              VARCHAR(60),
    causa_principal        VARCHAR(3),
    causa_acidente         VARCHAR(120),
    ordem_tipo_acidente    VARCHAR(3),
    tipo_acidente          VARCHAR(50),
    classificacao_acidente VARCHAR(20),
    fase_dia               VARCHAR(20),
    sentido_via            VARCHAR(13),
    condicao_metereologica VARCHAR(30),
    tipo_pista             VARCHAR(8),
    tracado_via            VARCHAR(255),
    uso_solo               VARCHAR(3),
    id_veiculo             VARCHAR(12),
    tipo_veiculo           VARCHAR(30),
    marca                  VARCHAR(60),
    ano_fabricacao_veiculo VARCHAR(4),
    tipo_envolvido         VARCHAR(10),
    estado_fisico          VARCHAR(15),
    idade                  VARCHAR(4),
    sexo                   VARCHAR(13),
    ilesos                 VARCHAR(2),
    feridos_leves          VARCHAR(2),
    feridos_graves         VARCHAR(2),
    mortos                 VARCHAR(2),
    latitude               VARCHAR(20),
    longitude              VARCHAR(20),
    regional               VARCHAR(10),
    delegacia              VARCHAR(12),
    uop                    VARCHAR(20),
    PRIMARY KEY (linha),
    INDEX idx_stg_id (id)          -- acelera os agrupamentos por acidente na carga
) ENGINE = InnoDB
  COMMENT = 'Staging: cópia bruta do CSV da PRF (apagada ao fim da validação)';

LOAD DATA LOCAL INFILE 'dados/acidentes2024_todas_causas_tipos_Usuport.csv'
    INTO TABLE stg_acidente_csv
    CHARACTER SET latin1
    FIELDS TERMINATED BY ';' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\r\n'
    IGNORE 1 LINES
    (id, pesid, data_inversa, dia_semana, horario, uf, br, km, municipio,
     causa_principal, causa_acidente, ordem_tipo_acidente, tipo_acidente,
     classificacao_acidente, fase_dia, sentido_via, condicao_metereologica,
     tipo_pista, tracado_via, uso_solo, id_veiculo, tipo_veiculo, marca,
     ano_fabricacao_veiculo, tipo_envolvido, estado_fisico, idade, sexo,
     ilesos, feridos_leves, feridos_graves, mortos, latitude, longitude,
     regional, delegacia, uop);

-- Conferência: devem aparecer 603.215 linhas e 73.156 acidentes distintos.
SELECT COUNT(*)           AS linhas_carregadas,
       COUNT(DISTINCT id) AS acidentes_distintos
  FROM stg_acidente_csv;
