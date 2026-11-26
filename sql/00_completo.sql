-- =============================================================================
--  UNIFACS — Campus CTN, Salvador
--  UC Projeto Integrador de Banco de Dados — Avaliação A3
--  Professores: Sergio Spinola e Alexandre Anunciação
--  Equipe: Time Índice — Grupo 4 | Cenário: USUPORT
--
--  Arquivo: 00_completo.sql — PACOTE SQL ÚNICO (DDL + carga + validação +
--  DML + DQL + views + rotinas). Gerado por scripts/montar_sql_completo.py a
--  partir dos scripts modulares 01..08 (não edite este arquivo diretamente).
--
--  Execução (da RAIZ do projeto, com o CSV em dados/), SEMPRE como root:
--  criar trigger com o log binário ligado (padrão do MySQL 8) exige SUPER.
--     mysql --local-infile=1 --default-character-set=utf8mb4 -u root -p < sql/00_completo.sql
--  Na VM Ubuntu:  sudo mysql --local-infile=1 --default-character-set=utf8mb4 < sql/00_completo.sql
-- =============================================================================


-- #############################################################################
-- ##  01_ddl.sql
-- #############################################################################

-- =============================================================================
--  UNIFACS — UC Projeto Integrador de Banco de Dados — Avaliação A3
--  Equipe: Time Índice — Grupo 4  |  Cenário: USUPORT
--  Arquivo: 01_ddl.sql — DDL (Data Definition Language)
-- -----------------------------------------------------------------------------
--  O que este script faz, em ordem:
--    1. CREATE DATABASE usuport (utf8mb4, colação sem acento/sem caixa);
--    2. DROP TABLE IF EXISTS das tabelas, na ordem INVERSA das FKs
--       (primeiro quem referencia, depois quem é referenciado);
--    3. CREATE TABLE das 14 tabelas, na ordem DIRETA das FKs
--       (primeiro os catálogos e a hierarquia da PRF, depois acidente,
--        depois as tabelas que dependem de acidente);
--    4. ALTER TABLE comentados, com restrições que só podem ser criadas
--       depois que as tabelas envolvidas existem.
--
--  Convenções de nomes:
--    pk_ = chave primária | fk_ = chave estrangeira | uq_ = UNIQUE
--    ck_ = CHECK          | idx_ = índice de busca
--  Toda coluna e tabela tem COMMENT: ele aparece no DBeaver/Workbench e é a
--  fonte do dicionário de dados (scripts/gerar_dicionario.py).
--
--  Política de exclusão: todas as FKs são ON DELETE RESTRICT (padrão).
--  Apagar um acidente exige apagar antes os dependentes, de forma explícita
--  e dentro de uma transação (ver 05_dml_exemplos.sql e app/db.py).
-- =============================================================================

CREATE DATABASE IF NOT EXISTS usuport
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_0900_ai_ci;   -- ai_ci: "sao paulo" encontra "SÃO PAULO"

USE usuport;

-- -----------------------------------------------------------------------------
-- 2. Remoção das tabelas (ordem inversa das dependências)
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS pessoa;
DROP TABLE IF EXISTS veiculo;
DROP TABLE IF EXISTS acidente_tracado;
DROP TABLE IF EXISTS acidente_tipo;
DROP TABLE IF EXISTS causa_acidente;
DROP TABLE IF EXISTS acidente;
DROP TABLE IF EXISTS tipo_veiculo;
DROP TABLE IF EXISTS tracado;
DROP TABLE IF EXISTS tipo_acidente;
DROP TABLE IF EXISTS causa;
-- Catálogos da versão 1 que viraram coluna com CHECK na versão 2 (parte 1).
-- O DROP continua aqui para limpar um banco criado pela versão 1.
DROP TABLE IF EXISTS fase_dia;
DROP TABLE IF EXISTS condicao_meteorologica;
DROP TABLE IF EXISTS cidade;
DROP TABLE IF EXISTS uop;
DROP TABLE IF EXISTS delegacia;
DROP TABLE IF EXISTS superintendencia;

-- =============================================================================
-- 3. Criação das tabelas
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 3.1 Hierarquia administrativa da PRF: superintendência → delegacia → UOP
--     Existe como tabela porque "traz informação junto": no CSV, a UOP
--     determina a delegacia, que determina a superintendência (100% dos casos).
--     Guardar as três siglas no acidente seria dependência transitiva (fere 3FN).
-- -----------------------------------------------------------------------------
CREATE TABLE superintendencia (
    id    SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT
          COMMENT 'Chave substituta (surrogate) da superintendência',
    sigla VARCHAR(10)       NOT NULL
          COMMENT 'Sigla da superintendência regional da PRF (ex.: SPRF-BA) ou UniPRF',
    CONSTRAINT pk_superintendencia PRIMARY KEY (id),
    CONSTRAINT uq_superintendencia_sigla UNIQUE (sigla)
) ENGINE = InnoDB
  COMMENT = 'Superintendências regionais da PRF (topo da hierarquia administrativa)';

CREATE TABLE delegacia (
    id                  SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT
                        COMMENT 'Chave substituta da delegacia',
    sigla               VARCHAR(12)       NOT NULL
                        COMMENT 'Sigla da delegacia (ex.: DEL01-BA)',
    id_superintendencia SMALLINT UNSIGNED NOT NULL
                        COMMENT 'FK: superintendência à qual a delegacia está subordinada',
    CONSTRAINT pk_delegacia PRIMARY KEY (id),
    CONSTRAINT uq_delegacia_sigla UNIQUE (sigla),
    CONSTRAINT fk_delegacia_superintendencia
        FOREIGN KEY (id_superintendencia) REFERENCES superintendencia (id)
) ENGINE = InnoDB
  COMMENT = 'Delegacias da PRF; cada uma pertence a exatamente uma superintendência';

CREATE TABLE uop (
    id           SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT
                 COMMENT 'Chave substituta da UOP',
    sigla        VARCHAR(20)       NOT NULL
                 COMMENT 'Sigla da Unidade Operacional (ex.: UOP01-DEL01-BA)',
    id_delegacia SMALLINT UNSIGNED NOT NULL
                 COMMENT 'FK: delegacia à qual a UOP está subordinada',
    CONSTRAINT pk_uop PRIMARY KEY (id),
    CONSTRAINT uq_uop_sigla UNIQUE (sigla),
    CONSTRAINT fk_uop_delegacia
        FOREIGN KEY (id_delegacia) REFERENCES delegacia (id)
) ENGINE = InnoDB
  COMMENT = 'Unidades Operacionais (postos) da PRF; cada uma pertence a uma delegacia';

-- -----------------------------------------------------------------------------
-- 3.2 Cidade — "traz informação junto": o município determina a UF.
--     Chave natural composta (nome, uf): 36 nomes de município se repetem em
--     UFs diferentes no CSV (ex.: BOM JESUS existe em PB, PI, RN e RS).
-- -----------------------------------------------------------------------------
CREATE TABLE cidade (
    id   SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT
         COMMENT 'Chave substituta da cidade',
    nome VARCHAR(60)       NOT NULL
         COMMENT 'Nome do município como registrado pela PRF (maiúsculas, sem acento)',
    uf   CHAR(2)           NOT NULL
         COMMENT 'Sigla da unidade da federação do município',
    CONSTRAINT pk_cidade PRIMARY KEY (id),
    CONSTRAINT uq_cidade_nome_uf UNIQUE (nome, uf),
    CONSTRAINT ck_cidade_uf CHECK (uf IN ('AC','AL','AP','AM','BA','CE','DF','ES','GO',
                                          'MA','MT','MS','MG','PA','PB','PR','PE','PI',
                                          'RJ','RN','RS','RO','RR','SC','SP','SE','TO')),
    INDEX idx_cidade_uf (uf)                -- filtro por UF no app e nas consultas
) ENGINE = InnoDB
  COMMENT = 'Municípios onde ocorreram acidentes; chave natural (nome, uf)';

-- -----------------------------------------------------------------------------
-- 3.3 Catálogos (listas de valores grandes ou que podem mudar).
--     Critério do grupo: vira tabela a lista que é grande, tem textos longos ou
--     que a PRF pode revisar (causas, tipos de acidente, traçados, tipos de
--     veículo). Listas pequenas, curtas e fixas viram coluna com CHECK (sexo,
--     sentido, fase do dia, condição meteorológica etc.): o CHECK valida na
--     própria linha e dispensa um JOIN.
-- -----------------------------------------------------------------------------
CREATE TABLE causa (
    id        SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT
              COMMENT 'Chave substituta da causa',
    descricao VARCHAR(120)     NOT NULL
              COMMENT 'Descrição da causa apontada pela PRF (ex.: Velocidade Incompatível)',
    CONSTRAINT pk_causa PRIMARY KEY (id),
    CONSTRAINT uq_causa_descricao UNIQUE (descricao)
) ENGINE = InnoDB
  COMMENT = 'Catálogo de causas de acidente (70 valores no CSV de 2024)';

CREATE TABLE tipo_acidente (
    id        TINYINT UNSIGNED NOT NULL AUTO_INCREMENT
              COMMENT 'Chave substituta do tipo de acidente',
    descricao VARCHAR(50)      NOT NULL
              COMMENT 'Tipo do evento (ex.: Colisão traseira, Tombamento)',
    CONSTRAINT pk_tipo_acidente PRIMARY KEY (id),
    CONSTRAINT uq_tipo_acidente_descricao UNIQUE (descricao)
) ENGINE = InnoDB
  COMMENT = 'Catálogo de tipos de acidente (17 valores no CSV de 2024)';

CREATE TABLE tracado (
    id        TINYINT UNSIGNED NOT NULL AUTO_INCREMENT
              COMMENT 'Chave substituta do traçado',
    descricao VARCHAR(30)      NOT NULL
              COMMENT 'Característica do traçado da via (ex.: Reta, Curva, Declive)',
    CONSTRAINT pk_tracado PRIMARY KEY (id),
    CONSTRAINT uq_tracado_descricao UNIQUE (descricao)
) ENGINE = InnoDB
  COMMENT = 'Catálogo de traçados de via (12 valores, extraídos da célula multivalorada)';

CREATE TABLE tipo_veiculo (
    id        TINYINT UNSIGNED NOT NULL AUTO_INCREMENT
              COMMENT 'Chave substituta do tipo de veículo',
    descricao VARCHAR(30)      NOT NULL
              COMMENT 'Tipo do veículo (ex.: Automóvel, Motocicleta, Ônibus)',
    CONSTRAINT pk_tipo_veiculo PRIMARY KEY (id),
    CONSTRAINT uq_tipo_veiculo_descricao UNIQUE (descricao)
) ENGINE = InnoDB
  COMMENT = 'Catálogo de tipos de veículo (25 valores no CSV de 2024)';

-- -----------------------------------------------------------------------------
-- 3.4 ACIDENTE — entidade central.
--     * id = identificador do acidente atribuído pela PRF (chave natural).
--       AUTO_INCREMENT só para acidentes novos cadastrados pelo sistema.
--     * dia_semana NÃO é armazenado: é calculado da data (DAYNAME/DAYOFWEEK).
--     * Atributo composto "local" (br, km, sentido, cidade) foi decomposto em
--       colunas simples + FK para cidade. "Coordenadas" (latitude, longitude)
--       também viraram duas colunas.
--     * Unidade da PRF responsável: ARCO EXCLUSIVO. O acidente aponta para a
--       unidade MAIS ESPECÍFICA conhecida: a UOP; se não houver UOP, a delegacia;
--       se não houver delegacia, a superintendência. Nunca duas ao mesmo tempo
--       (ck_acidente_unidade_unica), por isso não há dependência transitiva.
--       No CSV: 73.044 com UOP, 76 só com delegacia, 33 só com superintendência
--       e 3 sem nenhuma unidade.
-- -----------------------------------------------------------------------------
CREATE TABLE acidente (
    id                  INT UNSIGNED      NOT NULL AUTO_INCREMENT
                        COMMENT 'Identificador do acidente atribuído pela PRF (coluna id do CSV)',
    data                DATE              NOT NULL
                        COMMENT 'Data do acidente (data_inversa no CSV); dia da semana é calculado a partir dela',
    horario             TIME              NOT NULL
                        COMMENT 'Hora do acidente',
    br                  SMALLINT UNSIGNED NULL
                        COMMENT 'Número da rodovia federal (BR); NULL em 186 acidentes sem BR informada',
    km                  DECIMAL(6,1)      NULL
                        COMMENT 'Quilômetro da BR (vírgula decimal convertida para ponto)',
    sentido             VARCHAR(13)       NOT NULL
                        COMMENT 'Sentido da via: Crescente, Decrescente ou Não Informado',
    tipo_pista          VARCHAR(8)        NOT NULL
                        COMMENT 'Tipo de pista: Simples, Dupla ou Múltipla',
    uso_solo            VARCHAR(6)        NOT NULL
                        COMMENT 'Urbano (uso_solo = Sim no CSV) ou Rural (uso_solo = Não)',
    classificacao       VARCHAR(20)       NULL
                        COMMENT 'Classificação da PRF: Sem Vítimas, Com Vítimas Feridas ou Com Vítimas Fatais',
    latitude            DECIMAL(12,10)    NOT NULL
                        COMMENT 'Latitude em graus decimais (parte do atributo composto coordenadas)',
    longitude           DECIMAL(13,10)    NOT NULL
                        COMMENT 'Longitude em graus decimais (parte do atributo composto coordenadas)',
    condicao_meteorologica VARCHAR(16)    NOT NULL
                        COMMENT 'Condição do tempo no momento do acidente (10 valores fixos; ex.: Céu Claro, Chuva, Ignorado)',
    fase_dia            VARCHAR(11)       NOT NULL
                        COMMENT 'Fase do dia: Amanhecer, Pleno Dia, Anoitecer ou Plena Noite',
    id_cidade           SMALLINT UNSIGNED NOT NULL
                        COMMENT 'FK: município onde ocorreu o acidente (e, por ele, a UF)',
    id_uop              SMALLINT UNSIGNED NULL
                        COMMENT 'FK (arco): UOP responsável; preenchida quando a UOP é conhecida',
    id_delegacia        SMALLINT UNSIGNED NULL
                        COMMENT 'FK (arco): delegacia responsável, só quando NÃO há UOP',
    id_superintendencia SMALLINT UNSIGNED NULL
                        COMMENT 'FK (arco): superintendência responsável, só quando NÃO há UOP nem delegacia',
    CONSTRAINT pk_acidente PRIMARY KEY (id),
    CONSTRAINT fk_acidente_cidade      FOREIGN KEY (id_cidade)   REFERENCES cidade (id),
    CONSTRAINT fk_acidente_uop         FOREIGN KEY (id_uop)       REFERENCES uop (id),
    CONSTRAINT fk_acidente_delegacia   FOREIGN KEY (id_delegacia) REFERENCES delegacia (id),
    CONSTRAINT fk_acidente_superintendencia
        FOREIGN KEY (id_superintendencia) REFERENCES superintendencia (id),
    -- Domínios levantados do CSV (perfilamento de 2024):
    CONSTRAINT ck_acidente_sentido    CHECK (sentido IN ('Crescente','Decrescente','Não Informado')),
    CONSTRAINT ck_acidente_tipo_pista CHECK (tipo_pista IN ('Simples','Dupla','Múltipla')),
    CONSTRAINT ck_acidente_uso_solo   CHECK (uso_solo IN ('Urbano','Rural')),
    CONSTRAINT ck_acidente_classificacao CHECK (classificacao IS NULL OR classificacao IN
                                    ('Sem Vítimas','Com Vítimas Feridas','Com Vítimas Fatais')),
    -- Versão 2 (parte 1): listas pequenas e fixas que eram catálogo viram CHECK.
    CONSTRAINT ck_acidente_fase_dia CHECK (fase_dia IN
                                    ('Amanhecer','Pleno Dia','Anoitecer','Plena Noite')),
    CONSTRAINT ck_acidente_condicao CHECK (condicao_meteorologica IN
                                    ('Céu Claro','Chuva','Garoa/Chuvisco','Granizo','Ignorado',
                                     'Neve','Nevoeiro/Neblina','Nublado','Sol','Vento')),
    -- Faixas válidas:
    CONSTRAINT ck_acidente_data      CHECK (data >= '2007-01-01'),     -- série de dados abertos da PRF começa em 2007
    CONSTRAINT ck_acidente_horario   CHECK (horario BETWEEN '00:00:00' AND '23:59:59'),
    CONSTRAINT ck_acidente_br        CHECK (br IS NULL OR br BETWEEN 1 AND 499),   -- BRs vão de 010 a 499
    CONSTRAINT ck_acidente_km        CHECK (km IS NULL OR km >= 0),
    CONSTRAINT ck_acidente_km_br     CHECK (km IS NULL OR br IS NOT NULL),          -- não existe km sem BR
    CONSTRAINT ck_acidente_latitude  CHECK (latitude  BETWEEN -34 AND 6),            -- caixa geográfica do Brasil
    CONSTRAINT ck_acidente_longitude CHECK (longitude BETWEEN -74 AND -28),
    -- Arco exclusivo: no máximo UMA das três unidades preenchida.
    CONSTRAINT ck_acidente_unidade_unica CHECK (
          (id_uop IS NOT NULL) + (id_delegacia IS NOT NULL) + (id_superintendencia IS NOT NULL) <= 1),
    -- Índices de busca (as FKs já ganham índice automático no InnoDB):
    INDEX idx_acidente_data (data),                 -- filtros temporais (BETWEEN datas)
    INDEX idx_acidente_br_km (br, km),              -- trechos críticos por BR/km
    INDEX idx_acidente_classificacao (classificacao)
) ENGINE = InnoDB
  COMMENT = 'Acidente (sinistro) em rodovia federal registrado pela PRF';

-- -----------------------------------------------------------------------------
-- 3.5 CAUSA_ACIDENTE — resolve o atributo MULTIVALORADO "causas" (N:N).
--     Um acidente tem 1..16 causas; exatamente UMA é a principal.
--     PK composta (id_acidente, id_causa): a mesma causa não se repete.
-- -----------------------------------------------------------------------------
CREATE TABLE causa_acidente (
    id_acidente INT UNSIGNED      NOT NULL
                COMMENT 'FK: acidente',
    id_causa    SMALLINT UNSIGNED NOT NULL
                COMMENT 'FK: causa apontada para o acidente',
    principal   BOOLEAN           NOT NULL DEFAULT FALSE
                COMMENT 'TRUE se for a causa principal do acidente (exatamente uma por acidente)',
    CONSTRAINT pk_causa_acidente PRIMARY KEY (id_acidente, id_causa),
    CONSTRAINT fk_causa_acidente_acidente FOREIGN KEY (id_acidente) REFERENCES acidente (id),
    CONSTRAINT fk_causa_acidente_causa    FOREIGN KEY (id_causa)    REFERENCES causa (id),
    CONSTRAINT ck_causa_acidente_principal CHECK (principal IN (0, 1))
) ENGINE = InnoDB
  COMMENT = 'Associação N:N entre acidente e causa, com a marcação da causa principal';

-- -----------------------------------------------------------------------------
-- 3.6 ACIDENTE_TIPO — resolve o atributo MULTIVALORADO e ORDENADO "tipos".
--     PK (id_acidente, ordem) e NÃO (id_acidente, id_tipo): em 1.509 acidentes
--     o MESMO tipo aparece em ordens diferentes (ex.: 571802).
-- -----------------------------------------------------------------------------
CREATE TABLE acidente_tipo (
    id_acidente INT UNSIGNED     NOT NULL
                COMMENT 'FK: acidente',
    ordem       TINYINT UNSIGNED NOT NULL
                COMMENT 'Posição do evento na sequência do acidente (1 = primeiro evento)',
    id_tipo     TINYINT UNSIGNED NOT NULL
                COMMENT 'FK: tipo de acidente ocorrido nessa posição da sequência',
    CONSTRAINT pk_acidente_tipo PRIMARY KEY (id_acidente, ordem),
    CONSTRAINT fk_acidente_tipo_acidente FOREIGN KEY (id_acidente) REFERENCES acidente (id),
    CONSTRAINT fk_acidente_tipo_tipo     FOREIGN KEY (id_tipo)     REFERENCES tipo_acidente (id),
    CONSTRAINT ck_acidente_tipo_ordem CHECK (ordem BETWEEN 1 AND 50)
) ENGINE = InnoDB
  COMMENT = 'Sequência ordenada de tipos de evento de cada acidente';

-- -----------------------------------------------------------------------------
-- 3.7 ACIDENTE_TRACADO — resolve o atributo MULTIVALORADO "traçado da via",
--     que no CSV vinha numa única célula separada por ";" (ex.: "Reta;Declive").
--     A ordem não importa, por isso a PK é (id_acidente, id_tracado).
-- -----------------------------------------------------------------------------
CREATE TABLE acidente_tracado (
    id_acidente INT UNSIGNED     NOT NULL
                COMMENT 'FK: acidente',
    id_tracado  TINYINT UNSIGNED NOT NULL
                COMMENT 'FK: característica de traçado presente no local',
    CONSTRAINT pk_acidente_tracado PRIMARY KEY (id_acidente, id_tracado),
    CONSTRAINT fk_acidente_tracado_acidente FOREIGN KEY (id_acidente) REFERENCES acidente (id),
    CONSTRAINT fk_acidente_tracado_tracado  FOREIGN KEY (id_tracado)  REFERENCES tracado (id)
) ENGINE = InnoDB
  COMMENT = 'Associação N:N entre acidente e traçado da via';

-- -----------------------------------------------------------------------------
-- 3.8 VEICULO — cada id_veiculo da PRF pertence a UM único acidente
--     (não é cadastro de frota: não há placa). Por isso a FK fica no veículo.
--     ano_fabricacao é SMALLINT e não YEAR porque YEAR começa em 1901 e o CSV
--     tem veículos com ano 1900.
-- -----------------------------------------------------------------------------
CREATE TABLE veiculo (
    id              INT UNSIGNED      NOT NULL AUTO_INCREMENT
                    COMMENT 'Identificador do veículo no acidente atribuído pela PRF (id_veiculo)',
    id_acidente     INT UNSIGNED      NOT NULL
                    COMMENT 'FK: acidente em que o veículo se envolveu',
    id_tipo_veiculo TINYINT UNSIGNED  NOT NULL
                    COMMENT 'FK: tipo do veículo',
    marca           VARCHAR(40)       NULL
                    COMMENT 'Marca/modelo informado (ex.: HONDA/CG 160 FAN); NULL quando não informado',
    ano_fabricacao  SMALLINT UNSIGNED NULL
                    COMMENT 'Ano de fabricação; NULL quando ausente (0 no CSV)',
    CONSTRAINT pk_veiculo PRIMARY KEY (id),
    -- UNIQUE (id, id_acidente): redundante como unicidade (id já é PK), mas é
    -- o alvo da FK composta de pessoa (ver ALTER TABLE no fim do script).
    CONSTRAINT uq_veiculo_id_acidente UNIQUE (id, id_acidente),
    CONSTRAINT fk_veiculo_acidente     FOREIGN KEY (id_acidente)     REFERENCES acidente (id),
    CONSTRAINT fk_veiculo_tipo_veiculo FOREIGN KEY (id_tipo_veiculo) REFERENCES tipo_veiculo (id),
    CONSTRAINT ck_veiculo_ano CHECK (ano_fabricacao IS NULL OR ano_fabricacao BETWEEN 1900 AND 2100)
) ENGINE = InnoDB
  COMMENT = 'Veículo envolvido em um acidente (um registro por veículo por acidente)';

-- -----------------------------------------------------------------------------
-- 3.9 PESSOA — cada pesid pertence a um único acidente.
--     * Condutor/Passageiro estão SEMPRE num veículo; Pedestre, Testemunha e
--       Cavaleiro NUNCA (regra verificada no CSV) → ck_pessoa_envolvido_veiculo.
--     * id_acidente é obrigatório porque pedestres e testemunhas não têm
--       veículo. Para quem tem veículo, ele repete o acidente do veículo: essa
--       redundância é CONTROLADA pela FK composta (id_veiculo, id_acidente)
--       → veiculo (id, id_acidente), criada no ALTER TABLE abaixo, que impede
--       que a pessoa aponte para um veículo de outro acidente.
--     * ilesos/feridos_leves/feridos_graves/mortos NÃO são armazenados: são
--       derivados de estado_fisico e somados com GROUP BY.
-- -----------------------------------------------------------------------------
CREATE TABLE pessoa (
    pesid          INT UNSIGNED     NOT NULL AUTO_INCREMENT
                   COMMENT 'Identificador da pessoa no acidente atribuído pela PRF (pesid)',
    id_acidente    INT UNSIGNED     NOT NULL
                   COMMENT 'FK: acidente em que a pessoa se envolveu',
    id_veiculo     INT UNSIGNED     NULL
                   COMMENT 'FK: veículo ocupado pela pessoa; NULL para pedestre, testemunha e cavaleiro',
    tipo_envolvido VARCHAR(10)      NOT NULL
                   COMMENT 'Papel no acidente: Condutor, Passageiro, Pedestre, Testemunha ou Cavaleiro',
    estado_fisico  VARCHAR(15)      NOT NULL
                   COMMENT 'Ileso, Lesões Leves, Lesões Graves, Óbito ou Não Informado',
    idade          TINYINT UNSIGNED NULL
                   COMMENT 'Idade em anos; NULL quando ausente ou inválida (> 110 no CSV)',
    sexo           VARCHAR(13)      NOT NULL
                   COMMENT 'Masculino, Feminino, Não Informado ou Ignorado',
    CONSTRAINT pk_pessoa PRIMARY KEY (pesid),
    CONSTRAINT fk_pessoa_acidente FOREIGN KEY (id_acidente) REFERENCES acidente (id),
    CONSTRAINT ck_pessoa_tipo_envolvido CHECK (tipo_envolvido IN
                    ('Condutor','Passageiro','Pedestre','Testemunha','Cavaleiro')),
    CONSTRAINT ck_pessoa_estado_fisico CHECK (estado_fisico IN
                    ('Ileso','Lesões Leves','Lesões Graves','Óbito','Não Informado')),
    CONSTRAINT ck_pessoa_sexo  CHECK (sexo IN ('Masculino','Feminino','Não Informado','Ignorado')),
    CONSTRAINT ck_pessoa_idade CHECK (idade IS NULL OR idade BETWEEN 0 AND 110),
    -- Quem ocupa veículo (Condutor/Passageiro) tem id_veiculo; os demais não têm.
    CONSTRAINT ck_pessoa_envolvido_veiculo CHECK (
          (tipo_envolvido IN ('Condutor','Passageiro')) = (id_veiculo IS NOT NULL)),
    INDEX idx_pessoa_estado_fisico (estado_fisico)   -- contagem de óbitos/feridos
) ENGINE = InnoDB
  COMMENT = 'Pessoa envolvida em um acidente (condutor, passageiro, pedestre, testemunha ou cavaleiro)';

-- =============================================================================
-- 4. ALTER TABLE — restrições adicionadas depois da criação
-- =============================================================================

-- ALTER 1 — FK composta pessoa → veiculo.
--   Por que ALTER e não dentro do CREATE? Para deixar explícito que ela depende
--   da UNIQUE (id, id_acidente) de veiculo. Ela garante a regra "a pessoa só
--   pode estar num veículo do MESMO acidente". Quando id_veiculo é NULL
--   (pedestre/testemunha), o MySQL não verifica a FK (MATCH SIMPLE).
ALTER TABLE pessoa
    ADD CONSTRAINT fk_pessoa_veiculo_mesmo_acidente
        FOREIGN KEY (id_veiculo, id_acidente) REFERENCES veiculo (id, id_acidente);

-- ALTER 2 — "No máximo uma causa principal por acidente".
--   CHECK não enxerga outras linhas, então usamos uma coluna GERADA (virtual,
--   não ocupa espaço) que vale id_acidente quando principal = TRUE e NULL caso
--   contrário, e colocamos UNIQUE nela. O MySQL aceita vários NULL num índice
--   UNIQUE, mas não dois id_acidente iguais → no máximo uma principal.
--   O "pelo menos uma" é garantido pela transação de inserção (app) e
--   conferido em 04_validacao.sql.
ALTER TABLE causa_acidente
    ADD COLUMN marcador_principal INT UNSIGNED
        GENERATED ALWAYS AS (IF(principal, id_acidente, NULL)) VIRTUAL
        COMMENT 'Coluna gerada: id_acidente se a causa for principal, senão NULL (apoia a UNIQUE)',
    ADD CONSTRAINT uq_causa_acidente_uma_principal UNIQUE (marcador_principal);

-- ALTER 3 — Índice de busca por marca do veículo (tela de consulta do app,
--   filtro "marca contém..."). Mostra a criação de índice fora do CREATE TABLE.
ALTER TABLE veiculo
    ADD INDEX idx_veiculo_marca (marca);

-- Conferência rápida: deve listar as 14 tabelas.
SELECT table_name AS tabela, table_comment AS finalidade
  FROM information_schema.tables
 WHERE table_schema = 'usuport' AND table_type = 'BASE TABLE'
 ORDER BY table_name;


-- #############################################################################
-- ##  02_staging.sql
-- #############################################################################

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


-- #############################################################################
-- ##  03_carga.sql
-- #############################################################################

-- =============================================================================
--  UNIFACS — Projeto Integrador de Banco de Dados — A3
--  Time Índice — Grupo 4 | Cenário: USUPORT
--  Arquivo: 03_carga.sql — povoamento (DML) das 14 tabelas a partir da staging
-- -----------------------------------------------------------------------------
--  Cada tabela é preenchida com INSERT ... SELECT [DISTINCT] sobre a staging,
--  na ORDEM DAS FKs (quem é referenciado entra antes de quem referencia):
--     1. superintendencia → delegacia → uop
--     2. cidade e catálogos (condição, fase do dia, causa, tipo, traçado, tipo de veículo)
--     3. acidente
--     4. causa_acidente, acidente_tipo, acidente_tracado
--     5. veiculo → pessoa
--
--  REGRAS DE LIMPEZA aplicadas (a contagem de registros afetados por cada
--  uma está em 04_validacao.sql, seção B):
--     R0  id em notação científica ("6e+05", 3 linhas) → "600000"
--     R1  "NA" / "N/A" (texto)          → NULL
--     R2  km "272,5" (vírgula)          → 272.5 DECIMAL
--     R3  latitude/longitude (texto)    → DECIMAL
--     R4  uso_solo Sim/Não              → 'Urbano'/'Rural'
--     R5  traçado "Reta;Declive"        → uma linha por valor em acidente_tracado
--                                         (sem duplicar valores da mesma célula)
--     R6  idade > 110                   → NULL
--     R7  ano_fabricacao = 0            → NULL
--     R8  marca "Não Informado/Não Informado" → NULL
--     R9  linha sem pesid (veículo sem pessoa) → gera veículo, não gera pessoa
--     R10 UOP/delegacia ausentes        → acidente aponta para a unidade mais
--                                         específica conhecida (arco)
--     R11 dia_semana e ilesos/feridos/mortos → NÃO carregados (derivados)
--     R12 fase do dia "Pleno dia"       → "Pleno Dia" (grafia padronizada, como
--                                         "Plena Noite"; versão 2, parte 1)
-- =============================================================================

USE usuport;

-- -----------------------------------------------------------------------------
-- 0. Correção na própria staging (R0)
--    O acidente 600000 foi exportado em notação científica ("6e+05") em 3
--    linhas; no arquivo ele fica exatamente entre os ids 599999 e 600001.
--    O UPDATE converte qualquer id com "e" para o inteiro correspondente
--    (a coluna "linha" da staging continua apontando a linha original do CSV).
-- -----------------------------------------------------------------------------
UPDATE stg_acidente_csv
   SET id = CAST(CAST(id AS DOUBLE) AS UNSIGNED)
 WHERE id REGEXP '[eE]';
SELECT 'R0 ids corrigidos na staging' AS tabela, ROW_COUNT() AS linhas_inseridas;

-- -----------------------------------------------------------------------------
-- 1. Hierarquia da PRF
-- -----------------------------------------------------------------------------
INSERT INTO superintendencia (sigla)
SELECT DISTINCT s.regional
  FROM stg_acidente_csv s
 WHERE s.regional <> 'N/A'                              -- R1
 ORDER BY s.regional;
SELECT 'superintendencia' AS tabela, ROW_COUNT() AS linhas_inseridas;

INSERT INTO delegacia (sigla, id_superintendencia)
SELECT DISTINCT s.delegacia, sp.id
  FROM stg_acidente_csv s
  JOIN superintendencia sp ON sp.sigla = s.regional     -- traduz sigla → id
 WHERE s.delegacia <> 'N/A'
 ORDER BY s.delegacia;
SELECT 'delegacia' AS tabela, ROW_COUNT() AS linhas_inseridas;

INSERT INTO uop (sigla, id_delegacia)
SELECT DISTINCT s.uop, d.id
  FROM stg_acidente_csv s
  JOIN delegacia d ON d.sigla = s.delegacia
 WHERE s.uop <> 'N/A'
 ORDER BY s.uop;
SELECT 'uop' AS tabela, ROW_COUNT() AS linhas_inseridas;

-- -----------------------------------------------------------------------------
-- 2. Cidade e catálogos
-- -----------------------------------------------------------------------------
-- Cidade: chave natural (nome, uf) — DISTINCT sobre o par, não só o nome.
INSERT INTO cidade (nome, uf)
SELECT DISTINCT s.municipio, s.uf
  FROM stg_acidente_csv s
 ORDER BY s.uf, s.municipio;
SELECT 'cidade' AS tabela, ROW_COUNT() AS linhas_inseridas;

-- (Versão 2: condição meteorológica e fase do dia não têm mais catálogo;
--  o texto vai direto para a coluna de acidente, validado por CHECK.)

INSERT INTO causa (descricao)
SELECT DISTINCT s.causa_acidente
  FROM stg_acidente_csv s
 ORDER BY 1;
SELECT 'causa' AS tabela, ROW_COUNT() AS linhas_inseridas;

INSERT INTO tipo_acidente (descricao)
SELECT DISTINCT s.tipo_acidente
  FROM stg_acidente_csv s
 ORDER BY 1;
SELECT 'tipo_acidente' AS tabela, ROW_COUNT() AS linhas_inseridas;

-- Traçado (R5): a célula "Reta;Declive;Curva" vira um array JSON
-- ["Reta","Declive","Curva"] e o JSON_TABLE devolve uma linha por elemento.
INSERT INTO tracado (descricao)
SELECT DISTINCT TRIM(j.valor)
  FROM (SELECT DISTINCT tracado_via FROM stg_acidente_csv) s
 CROSS JOIN JSON_TABLE(
           CONCAT('["', REPLACE(s.tracado_via, ';', '","'), '"]'),
           '$[*]' COLUMNS (valor VARCHAR(30) COLLATE utf8mb4_0900_ai_ci PATH '$')
       ) AS j
 ORDER BY 1;
SELECT 'tracado' AS tabela, ROW_COUNT() AS linhas_inseridas;

INSERT INTO tipo_veiculo (descricao)
SELECT DISTINCT s.tipo_veiculo
  FROM stg_acidente_csv s
 WHERE s.tipo_veiculo <> 'NA'               -- linhas de pedestre/testemunha não têm veículo
 ORDER BY 1;
SELECT 'tipo_veiculo' AS tabela, ROW_COUNT() AS linhas_inseridas;

-- -----------------------------------------------------------------------------
-- 3. Acidente — uma linha por id. A subconsulta DISTINCT reduz as 603.215
--    linhas às 73.156 combinações de atributos do acidente (todos os atributos
--    do acidente são constantes dentro do mesmo id: conferido no perfilamento).
-- -----------------------------------------------------------------------------
INSERT INTO acidente (id, data, horario, br, km, sentido, tipo_pista, uso_solo,
                      classificacao, latitude, longitude, condicao_meteorologica,
                      fase_dia, id_cidade, id_uop, id_delegacia, id_superintendencia)
SELECT CAST(s.id AS UNSIGNED),
       CAST(s.data_inversa AS DATE),
       CAST(s.horario AS TIME),
       CAST(NULLIF(s.br, 'NA') AS UNSIGNED),                          -- R1
       CAST(REPLACE(NULLIF(s.km, 'NA'), ',', '.') AS DECIMAL(6,1)),   -- R1 + R2
       s.sentido_via,
       s.tipo_pista,
       CASE s.uso_solo WHEN 'Sim' THEN 'Urbano' WHEN 'Não' THEN 'Rural' END,  -- R4
       NULLIF(s.classificacao_acidente, 'NA'),                        -- R1
       CAST(s.latitude  AS DECIMAL(12,10)),                           -- R3
       CAST(s.longitude AS DECIMAL(13,10)),                           -- R3
       s.condicao_metereologica,                     -- (sic) nome da coluna no CSV
       -- R12: a colação é sem caixa, então 'Pleno dia' casa com o WHEN e sai padronizado
       CASE s.fase_dia WHEN 'Pleno Dia' THEN 'Pleno Dia' ELSE s.fase_dia END,
       c.id,
       -- R10: arco "unidade mais específica conhecida"
       u.id                                              AS id_uop,
       CASE WHEN u.id IS NULL THEN d.id END              AS id_delegacia,
       CASE WHEN u.id IS NULL AND d.id IS NULL THEN sp.id END AS id_superintendencia
  FROM (SELECT DISTINCT id, data_inversa, horario, br, km, sentido_via, tipo_pista,
                        uso_solo, classificacao_acidente, latitude, longitude,
                        municipio, uf, condicao_metereologica, fase_dia,
                        uop, delegacia, regional
          FROM stg_acidente_csv) AS s
  JOIN cidade                 c  ON c.nome = s.municipio AND c.uf = s.uf
  LEFT JOIN uop              u  ON u.sigla  = s.uop         -- 'N/A' não casa → NULL
  LEFT JOIN delegacia         d  ON d.sigla  = s.delegacia
  LEFT JOIN superintendencia  sp ON sp.sigla = s.regional
 ORDER BY 1;
SELECT 'acidente' AS tabela, ROW_COUNT() AS linhas_inseridas;

-- -----------------------------------------------------------------------------
-- 4. Tabelas associativas (resolvem os atributos multivalorados)
-- -----------------------------------------------------------------------------
-- Causas: a mesma causa aparece repetida em várias linhas (uma por pessoa ×
-- tipo); GROUP BY reduz a um par (acidente, causa). MAX(...) = 1 se a causa
-- foi marcada como principal em alguma linha.
INSERT INTO causa_acidente (id_acidente, id_causa, principal)
SELECT CAST(s.id AS UNSIGNED), c.id, MAX(s.causa_principal = 'Sim')
  FROM stg_acidente_csv s
  JOIN causa c ON c.descricao = s.causa_acidente
 GROUP BY s.id, c.id
 ORDER BY 1, 2;
SELECT 'causa_acidente' AS tabela, ROW_COUNT() AS linhas_inseridas;

-- Tipos: um par (acidente, ordem) → um tipo. O mesmo tipo pode aparecer em
-- ordens diferentes (por isso a PK usa a ordem).
INSERT INTO acidente_tipo (id_acidente, ordem, id_tipo)
SELECT DISTINCT CAST(s.id AS UNSIGNED), CAST(s.ordem_tipo_acidente AS UNSIGNED), t.id
  FROM stg_acidente_csv s
  JOIN tipo_acidente t ON t.descricao = s.tipo_acidente
 ORDER BY 1, 2;
SELECT 'acidente_tipo' AS tabela, ROW_COUNT() AS linhas_inseridas;

-- Traçado do acidente (R5). O DISTINCT remove valores repetidos dentro da mesma
-- célula (ex.: "Reta;Reta" → um registro).
INSERT INTO acidente_tracado (id_acidente, id_tracado)
SELECT DISTINCT CAST(s.id AS UNSIGNED), t.id
  FROM (SELECT DISTINCT id, tracado_via FROM stg_acidente_csv) s
 CROSS JOIN JSON_TABLE(
           CONCAT('["', REPLACE(s.tracado_via, ';', '","'), '"]'),
           '$[*]' COLUMNS (valor VARCHAR(30) COLLATE utf8mb4_0900_ai_ci PATH '$')
       ) AS j
  JOIN tracado t ON t.descricao = TRIM(j.valor)
 ORDER BY 1, 2;
SELECT 'acidente_tracado' AS tabela, ROW_COUNT() AS linhas_inseridas;

/* Alternativa equivalente SEM JSON (CTE recursiva), útil para explicar a lógica:
WITH RECURSIVE partes (id, item, resto) AS (
    SELECT id,
           SUBSTRING_INDEX(tracado_via, ';', 1),
           IF(LOCATE(';', tracado_via) > 0, SUBSTRING(tracado_via, LOCATE(';', tracado_via) + 1), NULL)
      FROM (SELECT DISTINCT id, tracado_via FROM stg_acidente_csv) x
    UNION ALL
    SELECT id,
           SUBSTRING_INDEX(resto, ';', 1),
           IF(LOCATE(';', resto) > 0, SUBSTRING(resto, LOCATE(';', resto) + 1), NULL)
      FROM partes
     WHERE resto IS NOT NULL
)
SELECT DISTINCT id, TRIM(item) FROM partes;
*/

-- -----------------------------------------------------------------------------
-- 5. Veículo e pessoa
-- -----------------------------------------------------------------------------
-- Veículo: inclui os 17.192 veículos que só aparecem em linhas sem pesid (R9).
INSERT INTO veiculo (id, id_acidente, id_tipo_veiculo, marca, ano_fabricacao)
SELECT DISTINCT
       CAST(s.id_veiculo AS UNSIGNED),
       CAST(s.id AS UNSIGNED),
       tv.id,
       NULLIF(s.marca, 'Não Informado/Não Informado'),                         -- R8
       NULLIF(CAST(NULLIF(s.ano_fabricacao_veiculo, 'NA') AS UNSIGNED), 0)     -- R7
  FROM stg_acidente_csv s
  JOIN tipo_veiculo tv ON tv.descricao = s.tipo_veiculo
 WHERE s.id_veiculo <> 'NA'
 ORDER BY 1;
SELECT 'veiculo' AS tabela, ROW_COUNT() AS linhas_inseridas;

-- Pessoa: só linhas com pesid (R9). Os contadores ilesos/feridos/mortos do
-- CSV NÃO são carregados (R11): saem de estado_fisico.
INSERT INTO pessoa (pesid, id_acidente, id_veiculo, tipo_envolvido, estado_fisico, idade, sexo)
SELECT DISTINCT
       CAST(s.pesid AS UNSIGNED),
       CAST(s.id AS UNSIGNED),
       CAST(NULLIF(s.id_veiculo, 'NA') AS UNSIGNED),
       s.tipo_envolvido,
       s.estado_fisico,
       CASE WHEN s.idade = 'NA'                    THEN NULL
            WHEN CAST(s.idade AS UNSIGNED) > 110   THEN NULL                    -- R6
            ELSE CAST(s.idade AS UNSIGNED) END,
       s.sexo
  FROM stg_acidente_csv s
 WHERE s.pesid <> 'NA'
 ORDER BY 1;
SELECT 'pessoa' AS tabela, ROW_COUNT() AS linhas_inseridas;

-- -----------------------------------------------------------------------------
-- 6. ALTER TABLE — reserva de faixa de identificadores
--    Os ids da PRF ficam abaixo de 2 milhões. A partir de 9.000.001 ficam os
--    registros criados pelo próprio sistema USUPORT (massa de teste e app),
--    o que permite distinguir/expurgar dados próprios com um simples filtro.
-- -----------------------------------------------------------------------------
ALTER TABLE acidente AUTO_INCREMENT = 9000001;
ALTER TABLE veiculo  AUTO_INCREMENT = 9000001;
ALTER TABLE pessoa   AUTO_INCREMENT = 9000001;

-- Atualiza as estatísticas dos índices para o otimizador.
ANALYZE TABLE acidente, pessoa, veiculo, causa_acidente, acidente_tipo, acidente_tracado;


-- #############################################################################
-- ##  04_validacao.sql
-- #############################################################################

-- =============================================================================
--  UNIFACS — Projeto Integrador de Banco de Dados — A3
--  Time Índice — Grupo 4 | Cenário: USUPORT
--  Arquivo: 04_validacao.sql — conferência da carga
-- -----------------------------------------------------------------------------
--  Cada verificação devolve: o que foi medido, o valor ESPERADO (vindo do
--  perfilamento do CSV), o valor OBTIDO no banco e a situação (OK/DIVERGENTE).
--    A. Contagens das 14 tabelas
--    B. Regras de limpeza: quantos registros cada regra afetou
--    C. Regras de negócio (violações devem ser 0)
--    D. Remoção da staging (o esquema final fica só com as 14 tabelas)
--  Rode logo após o 03_carga.sql (a seção B lê a staging).
-- =============================================================================

USE usuport;

-- -----------------------------------------------------------------------------
-- A. Contagens esperadas
-- -----------------------------------------------------------------------------
SELECT t.verificacao, t.esperado, t.obtido,
       IF(t.esperado = t.obtido, 'OK', 'DIVERGENTE') AS situacao
  FROM (
    SELECT 'A01 acidentes'                  AS verificacao, 73156  AS esperado, (SELECT COUNT(*) FROM acidente)               AS obtido
    UNION ALL SELECT 'A02 pessoas',                  179114, (SELECT COUNT(*) FROM pessoa)
    UNION ALL SELECT 'A03 veiculos',                 139617, (SELECT COUNT(*) FROM veiculo)
    UNION ALL SELECT 'A04 causas (catalogo)',            70, (SELECT COUNT(*) FROM causa)
    UNION ALL SELECT 'A05 tipos de acidente',            17, (SELECT COUNT(*) FROM tipo_acidente)
    UNION ALL SELECT 'A06 tracados',                     12, (SELECT COUNT(*) FROM tracado)
    UNION ALL SELECT 'A07 tipos de veiculo',             25, (SELECT COUNT(*) FROM tipo_veiculo)
    UNION ALL SELECT 'A08 superintendencias',            28, (SELECT COUNT(*) FROM superintendencia)
    UNION ALL SELECT 'A09 delegacias',                  152, (SELECT COUNT(*) FROM delegacia)
    UNION ALL SELECT 'A10 UOPs',                        394, (SELECT COUNT(*) FROM uop)
    UNION ALL SELECT 'A11 cidades (nome, uf)',         1873, (SELECT COUNT(*) FROM cidade)
    -- v2: condição e fase do dia viraram coluna com CHECK → conta valores distintos
    UNION ALL SELECT 'A12 condicoes meteorologicas (distintas)', 10,
           (SELECT COUNT(DISTINCT condicao_meteorologica) FROM acidente)
    UNION ALL SELECT 'A13 fases do dia (distintas)',              4,
           (SELECT COUNT(DISTINCT fase_dia) FROM acidente)
    UNION ALL SELECT 'A14 pares acidente-causa',     111307, (SELECT COUNT(*) FROM causa_acidente)
    UNION ALL SELECT 'A15 pares acidente-ordem-tipo',124173, (SELECT COUNT(*) FROM acidente_tipo)
    UNION ALL SELECT 'A16 pares acidente-tracado',    93850, (SELECT COUNT(*) FROM acidente_tracado)
  ) AS t;

-- -----------------------------------------------------------------------------
-- B. Regras de limpeza — registros afetados (ver cabeçalho do 03_carga.sql)
-- -----------------------------------------------------------------------------
SELECT t.verificacao, t.esperado, t.obtido,
       IF(t.esperado = t.obtido, 'OK', 'DIVERGENTE') AS situacao
  FROM (
    -- R0: as 3 linhas "6e+05" agora pertencem ao acidente 600000
    SELECT 'B-R0 linhas do acidente 600000 (ex-6e+05)' AS verificacao, 3 AS esperado,
           (SELECT COUNT(*) FROM stg_acidente_csv WHERE id = '600000') AS obtido
    -- R1: textos NA/N/A que viraram NULL (contados por acidente)
    UNION ALL SELECT 'B-R1 acidentes sem BR/km (NA -> NULL)', 186,
           (SELECT COUNT(*) FROM acidente WHERE br IS NULL AND km IS NULL)
    UNION ALL SELECT 'B-R1 acidentes sem classificacao (NA -> NULL)', 1,
           (SELECT COUNT(*) FROM acidente WHERE classificacao IS NULL)
    UNION ALL SELECT 'B-R1 pessoas sem idade no CSV (NA -> NULL)', 17140,
           (SELECT COUNT(DISTINCT pesid) FROM stg_acidente_csv WHERE pesid <> 'NA' AND idade = 'NA')
    -- R2: km com vírgula decimal convertidos
    UNION ALL SELECT 'B-R2 acidentes com km convertido de virgula', 27170,
           (SELECT COUNT(DISTINCT id) FROM stg_acidente_csv WHERE km LIKE '%,%')
    -- R4: uso do solo
    UNION ALL SELECT 'B-R4 acidentes urbanos (Sim -> Urbano)',
           (SELECT COUNT(DISTINCT id) FROM stg_acidente_csv WHERE uso_solo = 'Sim'),
           (SELECT COUNT(*) FROM acidente WHERE uso_solo = 'Urbano')
    -- R5: células de traçado com mais de um valor
    UNION ALL SELECT 'B-R5 acidentes com tracado multivalorado', 18458,
           (SELECT COUNT(DISTINCT id) FROM stg_acidente_csv WHERE tracado_via LIKE '%;%')
    UNION ALL SELECT 'B-R5 celulas com valor repetido (removido)', 0,
           (SELECT COUNT(*) FROM (SELECT DISTINCT id, tracado_via FROM stg_acidente_csv) x
             WHERE JSON_LENGTH(CONCAT('["', REPLACE(tracado_via, ';', '","'), '"]'))
                 <> (SELECT COUNT(*) FROM acidente_tracado at2 WHERE at2.id_acidente = x.id))
    -- R6: idades impossíveis
    UNION ALL SELECT 'B-R6 pessoas com idade > 110 (-> NULL)', 282,
           (SELECT COUNT(DISTINCT pesid) FROM stg_acidente_csv
             WHERE pesid <> 'NA' AND idade <> 'NA' AND CAST(idade AS UNSIGNED) > 110)
    UNION ALL SELECT 'B-R6 pessoas com idade NULL no banco (R1 + R6)', 17140 + 282,
           (SELECT COUNT(*) FROM pessoa WHERE idade IS NULL)
    -- R7: ano de fabricação 0
    UNION ALL SELECT 'B-R7 veiculos com ano = 0 (-> NULL)', 10122,
           (SELECT COUNT(*) FROM veiculo WHERE ano_fabricacao IS NULL)
    -- R8: marca não informada
    UNION ALL SELECT 'B-R8 veiculos com marca nao informada (-> NULL)', 8070,
           (SELECT COUNT(*) FROM veiculo WHERE marca IS NULL)
    -- R9: linhas sem pesid geram veículo mas não pessoa
    UNION ALL SELECT 'B-R9 linhas do CSV sem pesid', 57641,
           (SELECT COUNT(*) FROM stg_acidente_csv WHERE pesid = 'NA')
    UNION ALL SELECT 'B-R9 veiculos sem nenhuma pessoa', 17192,
           (SELECT COUNT(*) FROM veiculo v
             WHERE NOT EXISTS (SELECT 1 FROM pessoa p WHERE p.id_veiculo = v.id))
    -- R10: arco da unidade responsável
    UNION ALL SELECT 'B-R10 acidentes ligados a UOP', 73044,
           (SELECT COUNT(*) FROM acidente WHERE id_uop IS NOT NULL)
    UNION ALL SELECT 'B-R10 acidentes so com delegacia (sem UOP)', 76,
           (SELECT COUNT(*) FROM acidente WHERE id_delegacia IS NOT NULL)
    UNION ALL SELECT 'B-R10 acidentes so com superintendencia', 33,
           (SELECT COUNT(*) FROM acidente WHERE id_superintendencia IS NOT NULL)
    UNION ALL SELECT 'B-R10 acidentes sem unidade da PRF', 3,
           (SELECT COUNT(*) FROM acidente
             WHERE id_uop IS NULL AND id_delegacia IS NULL AND id_superintendencia IS NULL)
    -- R11: dia_semana do CSV confere com o calculado a partir da data
    UNION ALL SELECT 'B-R11 dia_semana do CSV diferente do calculado', 0,
           (SELECT COUNT(*) FROM (SELECT DISTINCT id, data_inversa, dia_semana FROM stg_acidente_csv) x
             WHERE x.dia_semana <> ELT(DAYOFWEEK(x.data_inversa), 'domingo', 'segunda-feira',
                     'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado'))
    -- R11: contadores do CSV (mortos etc.) conferem com estado_fisico
    UNION ALL SELECT 'B-R11 mortos no CSV x pessoas com Obito',
           (SELECT SUM(m) FROM (SELECT pesid, MAX(CAST(mortos AS UNSIGNED)) m
                                  FROM stg_acidente_csv WHERE pesid <> 'NA' GROUP BY pesid) x),
           (SELECT COUNT(*) FROM pessoa WHERE estado_fisico = 'Óbito')
    UNION ALL SELECT 'B-R11 feridos graves no CSV x pessoas com Lesoes Graves',
           (SELECT SUM(m) FROM (SELECT pesid, MAX(CAST(feridos_graves AS UNSIGNED)) m
                                  FROM stg_acidente_csv WHERE pesid <> 'NA' GROUP BY pesid) x),
           (SELECT COUNT(*) FROM pessoa WHERE estado_fisico = 'Lesões Graves')
    -- R12: nenhuma fase do dia com a grafia antiga (comparação COM caixa)
    UNION ALL SELECT 'B-R12 fase do dia com grafia antiga "Pleno dia"', 0,
           (SELECT COUNT(*) FROM acidente WHERE fase_dia COLLATE utf8mb4_0900_as_cs = 'Pleno dia')
    UNION ALL SELECT 'B-R12 acidentes de "Pleno Dia" (padronizados)',
           (SELECT COUNT(DISTINCT id) FROM stg_acidente_csv WHERE fase_dia = 'Pleno dia'),
           (SELECT COUNT(*) FROM acidente WHERE fase_dia COLLATE utf8mb4_0900_as_cs = 'Pleno Dia')
  ) AS t;

-- -----------------------------------------------------------------------------
-- C. Regras de negócio (o "esperado" é a quantidade de VIOLAÇÕES ou o valor
--    conhecido do perfilamento)
-- -----------------------------------------------------------------------------
SELECT t.verificacao, t.esperado, t.obtido,
       IF(t.esperado = t.obtido, 'OK', 'DIVERGENTE') AS situacao
  FROM (
    -- RN01: exatamente uma causa principal por acidente
    SELECT 'C-RN01 acidentes sem exatamente 1 causa principal' AS verificacao, 0 AS esperado,
           (SELECT COUNT(*) FROM acidente a
             WHERE (SELECT COALESCE(SUM(ca.principal), 0) FROM causa_acidente ca
                     WHERE ca.id_acidente = a.id) <> 1) AS obtido
    -- RN02: todo acidente tem pelo menos um tipo, um traçado e uma pessoa
    UNION ALL SELECT 'C-RN02 acidentes sem tipo', 0,
           (SELECT COUNT(*) FROM acidente a LEFT JOIN acidente_tipo t ON t.id_acidente = a.id WHERE t.id_acidente IS NULL)
    UNION ALL SELECT 'C-RN02 acidentes sem tracado', 0,
           (SELECT COUNT(*) FROM acidente a LEFT JOIN acidente_tracado t ON t.id_acidente = a.id WHERE t.id_acidente IS NULL)
    UNION ALL SELECT 'C-RN02 acidentes sem pessoa', 0,
           (SELECT COUNT(*) FROM acidente a WHERE NOT EXISTS (SELECT 1 FROM pessoa p WHERE p.id_acidente = a.id))
    -- RN03: o mesmo tipo pode se repetir em ordens diferentes
    UNION ALL SELECT 'C-RN03 acidentes com tipo repetido em ordens diferentes', 1509,
           (SELECT COUNT(DISTINCT id_acidente) FROM
               (SELECT id_acidente, id_tipo FROM acidente_tipo
                 GROUP BY id_acidente, id_tipo HAVING COUNT(*) > 1) x)
    -- RN04: pessoa só em veículo do mesmo acidente (garantido pela FK composta)
    UNION ALL SELECT 'C-RN04 pessoas em veiculo de outro acidente', 0,
           (SELECT COUNT(*) FROM pessoa p JOIN veiculo v ON v.id = p.id_veiculo
             WHERE v.id_acidente <> p.id_acidente)
    -- RN05: pessoas sem veículo são só Pedestre, Testemunha ou Cavaleiro
    UNION ALL SELECT 'C-RN05 pessoas sem veiculo fora de Pedestre/Testemunha/Cavaleiro', 0,
           (SELECT COUNT(*) FROM pessoa WHERE id_veiculo IS NULL
               AND tipo_envolvido NOT IN ('Pedestre', 'Testemunha', 'Cavaleiro'))
    -- RN06: hierarquia estrita — já garantida pelas FKs uop→delegacia→superintendência
    UNION ALL SELECT 'C-RN06 UOPs sem delegacia', 0,
           (SELECT COUNT(*) FROM uop u LEFT JOIN delegacia d ON d.id = u.id_delegacia WHERE d.id IS NULL)
    -- RN07: acidente atendido por superintendência de outra UF (fato do CSV):
    --       1.289 por SPRF de outra UF + 2 pela UniPRF (unidade nacional, sem UF)
    UNION ALL SELECT 'C-RN07 acidentes da UniPRF (sem UF)', 2,
           (SELECT COUNT(*) FROM acidente a
              LEFT JOIN uop u        ON u.id = a.id_uop
              LEFT JOIN delegacia d  ON d.id = COALESCE(u.id_delegacia, a.id_delegacia)
              JOIN superintendencia s ON s.id = COALESCE(d.id_superintendencia, a.id_superintendencia)
             WHERE s.sigla = 'UniPRF')
    UNION ALL SELECT 'C-RN07 acidentes atendidos por SPRF de outra UF', 1289,
           (SELECT COUNT(*) FROM acidente a
              JOIN cidade c ON c.id = a.id_cidade
              LEFT JOIN uop u        ON u.id = a.id_uop
              LEFT JOIN delegacia d  ON d.id = COALESCE(u.id_delegacia, a.id_delegacia)
              JOIN superintendencia s ON s.id = COALESCE(d.id_superintendencia, a.id_superintendencia)
             WHERE s.sigla LIKE 'SPRF-%' AND RIGHT(s.sigla, 2) <> c.uf)
    -- RN08: classificação registrada x classificação calculada pelo estado físico
    UNION ALL SELECT 'C-RN08 classificacao divergente do estado fisico', 0,
           (SELECT COUNT(*) FROM acidente a
              JOIN (SELECT id_acidente,
                           CASE WHEN SUM(estado_fisico = 'Óbito') > 0 THEN 'Com Vítimas Fatais'
                                WHEN SUM(estado_fisico IN ('Lesões Leves', 'Lesões Graves')) > 0
                                     THEN 'Com Vítimas Feridas'
                                ELSE 'Sem Vítimas' END AS calculada
                      FROM pessoa GROUP BY id_acidente) k ON k.id_acidente = a.id
             WHERE a.classificacao <> k.calculada)
    -- Casos citados no relatório
    UNION ALL SELECT 'C-RN09 causas do acidente 589272 (provavel erro de preenchimento)', 16,
           (SELECT COUNT(*) FROM causa_acidente WHERE id_acidente = 589272)
    UNION ALL SELECT 'C-RN10 linhas do acidente 661121 (onibus) no CSV', 1540,
           (SELECT COUNT(*) FROM stg_acidente_csv WHERE id = '661121')
    UNION ALL SELECT 'C-RN11 municipios homonimos em UFs diferentes', 36,
           (SELECT COUNT(*) FROM (SELECT nome FROM cidade GROUP BY nome HAVING COUNT(*) > 1) x)
  ) AS t;

-- Distribuição do arco (para o relatório)
SELECT CASE WHEN id_uop IS NOT NULL              THEN '1. UOP'
            WHEN id_delegacia IS NOT NULL        THEN '2. so delegacia'
            WHEN id_superintendencia IS NOT NULL THEN '3. so superintendencia'
            ELSE '4. nenhuma' END AS unidade_registrada,
       COUNT(*) AS acidentes
  FROM acidente
 GROUP BY unidade_registrada
 ORDER BY unidade_registrada;

-- -----------------------------------------------------------------------------
-- D. Remoção da staging — o esquema final fica com as 14 tabelas do modelo.
--    (comente a linha abaixo se quiser manter a staging para inspeção)
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_acidente_csv;


-- #############################################################################
-- ##  05_dml_exemplos.sql
-- #############################################################################

-- =============================================================================
--  UNIFACS — Projeto Integrador de Banco de Dados — A3
--  Time Índice — Grupo 4 | Cenário: USUPORT
--  Arquivo: 05_dml_exemplos.sql — DML de demonstração (INSERT, UPDATE, DELETE)
-- -----------------------------------------------------------------------------
--  1. INSERT: massa de teste FICTÍCIA e consistente — dois acidentes completos
--     (acidente + causas + tipos + traçados + veículos + pessoas), cada um numa
--     transação. Os ids saem da faixa reservada (>= 9.000.001, ver 03_carga.sql)
--     e as FKs são resolvidas por subconsulta pela descrição, sem "números mágicos".
--  2. UPDATE: correções pontuais, atualização em mais de uma tabela na mesma
--     transação e atualização de catálogo (efeito da normalização).
--  3. DELETE controlado (expurgo): remoção do 2º acidente fictício e de todos os
--     seus dependentes, filho → pai, numa transação, com conferência antes/depois.
--     Também mostra um ROLLBACK.
--  Ao final, o acidente fictício nº 1 continua no banco como massa de teste.
--
--  Os comandos que DEVEM falhar (demonstração das restrições) estão
--  comentados no bloco 4, com o erro esperado.
-- =============================================================================

USE usuport;

-- =============================================================================
-- 1. INSERT — massa de teste fictícia
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1.1 Acidente fictício nº 1: colisão traseira com moto num viaduto da BR-324,
--     em Salvador, num fim de tarde chuvoso. 2 veículos, 4 pessoas.
--     Classificação "Com Vítimas Feridas" é coerente com as pessoas (RN08).
-- -----------------------------------------------------------------------------
START TRANSACTION;

INSERT INTO acidente (data, horario, br, km, sentido, tipo_pista, uso_solo,
                      classificacao, latitude, longitude,
                      condicao_meteorologica, fase_dia, id_cidade, id_uop)
VALUES ('2024-12-20', '18:40:00', 324, 612.5, 'Crescente', 'Dupla', 'Urbano',
        'Com Vítimas Feridas', -12.9301000000, -38.4502000000,
        'Chuva', 'Anoitecer',                -- v2: texto validado por CHECK
        (SELECT id FROM cidade WHERE nome = 'SALVADOR' AND uf = 'BA'),
        (SELECT id FROM uop    WHERE sigla = 'UOP01-DEL01-BA'));

-- LAST_INSERT_ID() devolve o id gerado pelo AUTO_INCREMENT nesta conexão.
SET @id_ac1 = LAST_INSERT_ID();

-- Causas: três, sendo "Velocidade Incompatível" a principal (a expressão
-- descricao = '...' vale 1 só para ela).
INSERT INTO causa_acidente (id_acidente, id_causa, principal)
SELECT @id_ac1, c.id, (c.descricao = 'Velocidade Incompatível')
  FROM causa c
 WHERE c.descricao IN ('Velocidade Incompatível', 'Pista Escorregadia', 'Chuva');

-- Tipos em sequência: 1º colisão traseira, 2º saída de leito carroçável.
INSERT INTO acidente_tipo (id_acidente, ordem, id_tipo)
VALUES (@id_ac1, 1, (SELECT id FROM tipo_acidente WHERE descricao = 'Colisão traseira')),
       (@id_ac1, 2, (SELECT id FROM tipo_acidente WHERE descricao = 'Saída de leito carroçável'));

-- Traçado (multivalorado): reta sobre viaduto.
INSERT INTO acidente_tracado (id_acidente, id_tracado)
SELECT @id_ac1, t.id FROM tracado t WHERE t.descricao IN ('Reta', 'Viaduto');

-- Veículos: um por INSERT para guardar cada id gerado.
INSERT INTO veiculo (id_acidente, id_tipo_veiculo, marca, ano_fabricacao)
VALUES (@id_ac1, (SELECT id FROM tipo_veiculo WHERE descricao = 'Automóvel'), 'FIAT/ARGO DRIVE 1.0', 2021);
SET @v1 = LAST_INSERT_ID();

INSERT INTO veiculo (id_acidente, id_tipo_veiculo, marca, ano_fabricacao)
VALUES (@id_ac1, (SELECT id FROM tipo_veiculo WHERE descricao = 'Motocicleta'), 'HONDA/CG 160 FAN', 2023);
SET @v2 = LAST_INSERT_ID();

-- Pessoas: condutora do carro (ilesa), condutor e passageira da moto (feridos)
-- e uma testemunha (sem veículo — regra RN05).
INSERT INTO pessoa (id_acidente, id_veiculo, tipo_envolvido, estado_fisico, idade, sexo)
VALUES (@id_ac1, @v1,  'Condutor',   'Ileso',         34,   'Feminino'),
       (@id_ac1, @v2,  'Condutor',   'Lesões Graves', 22,   'Masculino'),
       (@id_ac1, @v2,  'Passageiro', 'Lesões Leves',  19,   'Feminino'),
       (@id_ac1, NULL, 'Testemunha', 'Não Informado', NULL, 'Não Informado');

COMMIT;

-- -----------------------------------------------------------------------------
-- 1.2 Acidente fictício nº 2 (será expurgado no bloco 3): tombamento de
--     caminhão em curva, em Feira de Santana, sem vítimas.
-- -----------------------------------------------------------------------------
START TRANSACTION;

INSERT INTO acidente (data, horario, br, km, sentido, tipo_pista, uso_solo,
                      classificacao, latitude, longitude,
                      condicao_meteorologica, fase_dia, id_cidade, id_uop)
VALUES ('2024-12-21', '04:15:00', 116, 425.0, 'Decrescente', 'Simples', 'Rural',
        'Sem Vítimas', -12.3100000000, -38.9500000000,
        'Céu Claro', 'Plena Noite',
        (SELECT id FROM cidade WHERE nome = 'FEIRA DE SANTANA' AND uf = 'BA'),
        (SELECT id FROM uop    WHERE sigla = 'UOP01-DEL01-BA'));
SET @id_ac2 = LAST_INSERT_ID();

INSERT INTO causa_acidente (id_acidente, id_causa, principal)
SELECT @id_ac2, c.id, TRUE FROM causa c WHERE c.descricao = 'Avarias e/ou desgaste excessivo no pneu';

INSERT INTO acidente_tipo (id_acidente, ordem, id_tipo)
VALUES (@id_ac2, 1, (SELECT id FROM tipo_acidente WHERE descricao = 'Tombamento'));

INSERT INTO acidente_tracado (id_acidente, id_tracado)
SELECT @id_ac2, t.id FROM tracado t WHERE t.descricao = 'Curva';

INSERT INTO veiculo (id_acidente, id_tipo_veiculo, marca, ano_fabricacao)
VALUES (@id_ac2, (SELECT id FROM tipo_veiculo WHERE descricao = 'Caminhão'), 'VOLVO/FH 540 6X4T', 2019);
SET @v3 = LAST_INSERT_ID();

INSERT INTO pessoa (id_acidente, id_veiculo, tipo_envolvido, estado_fisico, idade, sexo)
VALUES (@id_ac2, @v3, 'Condutor', 'Ileso', 51, 'Masculino');

COMMIT;

-- Conferência dos dois acidentes inseridos.
SELECT a.id, a.data, c.nome AS cidade, c.uf, a.br, a.km, a.classificacao,
       (SELECT COUNT(*) FROM causa_acidente   x WHERE x.id_acidente = a.id) AS causas,
       (SELECT COUNT(*) FROM acidente_tipo    x WHERE x.id_acidente = a.id) AS tipos,
       (SELECT COUNT(*) FROM acidente_tracado x WHERE x.id_acidente = a.id) AS tracados,
       (SELECT COUNT(*) FROM veiculo          x WHERE x.id_acidente = a.id) AS veiculos,
       (SELECT COUNT(*) FROM pessoa           x WHERE x.id_acidente = a.id) AS pessoas
  FROM acidente a
  JOIN cidade c ON c.id = a.id_cidade
 WHERE a.id IN (@id_ac1, @id_ac2);

-- =============================================================================
-- 2. UPDATE
-- =============================================================================

-- 2.1 Correção pontual: a idade da passageira foi digitada errada (19 → 20).
--     O WHERE (acidente + veículo + papel) identifica exatamente 1 pessoa.
UPDATE pessoa
   SET idade = 20
 WHERE id_acidente = @id_ac1
   AND id_veiculo  = @v2
   AND tipo_envolvido = 'Passageiro';
SELECT 'U1 idade corrigida' AS etapa, ROW_COUNT() AS linhas_afetadas;

-- 2.2 Atualização em duas tabelas, na MESMA transação: o condutor da moto
--     morreu no hospital. Mudar só a pessoa deixaria a classificação do
--     acidente incoerente (RN08), por isso as duas mudanças vão juntas.
START TRANSACTION;
UPDATE pessoa
   SET estado_fisico = 'Óbito'
 WHERE id_acidente = @id_ac1 AND id_veiculo = @v2 AND tipo_envolvido = 'Condutor';
UPDATE acidente
   SET classificacao = 'Com Vítimas Fatais'
 WHERE id = @id_ac1;
COMMIT;
SELECT 'U2 obito + reclassificacao' AS etapa, classificacao FROM acidente WHERE id = @id_ac1;

-- 2.3 Troca da causa principal: "Pista Escorregadia" passa a ser a principal.
--     São DOIS UPDATEs em ordem: primeiro desmarca, depois marca. Se fosse ao
--     contrário, por um instante haveria duas principais e a UNIQUE
--     uq_causa_acidente_uma_principal recusaria (erro 1062).
START TRANSACTION;
UPDATE causa_acidente
   SET principal = FALSE
 WHERE id_acidente = @id_ac1 AND principal = TRUE;
UPDATE causa_acidente
   SET principal = TRUE
 WHERE id_acidente = @id_ac1
   AND id_causa = (SELECT id FROM causa WHERE descricao = 'Pista Escorregadia');
COMMIT;
SELECT 'U3 nova causa principal' AS etapa, c.descricao
  FROM causa_acidente ca JOIN causa c ON c.id = ca.id_causa
 WHERE ca.id_acidente = @id_ac1 AND ca.principal = TRUE;

-- 2.4 Atualização de catálogo — o ganho da normalização: a PRF grafa
--     "Semireboque", mas a grafia oficial (Acordo Ortográfico) é "Semirreboque".
--     Corrigir no catálogo é UMA linha alterada, e os 15.245 veículos desse tipo
--     passam a exibir o novo texto. Na planilha original seriam 50.449 células.
--     (É também o argumento para causa, tipo de acidente e tipo de veículo
--      continuarem como TABELA: são listas longas que a PRF revisa.)
UPDATE tipo_veiculo
   SET descricao = 'Semirreboque'
 WHERE descricao = 'Semireboque';
SELECT 'U4 catalogo padronizado' AS etapa, ROW_COUNT() AS linhas_afetadas;
SELECT tv.descricao AS tipo_veiculo, COUNT(*) AS veiculos
  FROM veiculo v JOIN tipo_veiculo tv ON tv.id = v.id_tipo_veiculo
 WHERE tv.descricao LIKE 'Semir%'
 GROUP BY tv.descricao;

-- =============================================================================
-- 3. DELETE controlado (expurgo)
-- =============================================================================

-- 3.1 Demonstração de ROLLBACK: apaga as pessoas do acidente 1 e desfaz.
START TRANSACTION;
DELETE FROM pessoa WHERE id_acidente = @id_ac1;
SELECT 'dentro da transação' AS momento, COUNT(*) AS pessoas_acidente_1
  FROM pessoa WHERE id_acidente = @id_ac1;
ROLLBACK;
SELECT 'depois do ROLLBACK' AS momento, COUNT(*) AS pessoas_acidente_1
  FROM pessoa WHERE id_acidente = @id_ac1;

-- 3.2 Expurgo do acidente fictício nº 2 com todos os dependentes.
--     Ordem: filhos antes do pai (as FKs são RESTRICT). A condição
--     "id >= 9000001" é uma trava: este bloco nunca apaga dados da PRF.
SELECT 'antes do expurgo' AS momento,
       (SELECT COUNT(*) FROM acidente WHERE id = @id_ac2)            AS acidente,
       (SELECT COUNT(*) FROM pessoa   WHERE id_acidente = @id_ac2)   AS pessoas,
       (SELECT COUNT(*) FROM veiculo  WHERE id_acidente = @id_ac2)   AS veiculos,
       (SELECT COUNT(*) FROM causa_acidente WHERE id_acidente = @id_ac2) AS causas;

START TRANSACTION;
DELETE FROM pessoa           WHERE id_acidente = @id_ac2 AND id_acidente >= 9000001;
DELETE FROM veiculo          WHERE id_acidente = @id_ac2 AND id_acidente >= 9000001;
DELETE FROM causa_acidente   WHERE id_acidente = @id_ac2 AND id_acidente >= 9000001;
DELETE FROM acidente_tipo    WHERE id_acidente = @id_ac2 AND id_acidente >= 9000001;
DELETE FROM acidente_tracado WHERE id_acidente = @id_ac2 AND id_acidente >= 9000001;
DELETE FROM acidente         WHERE id = @id_ac2          AND id >= 9000001;
COMMIT;

SELECT 'depois do expurgo' AS momento,
       (SELECT COUNT(*) FROM acidente WHERE id = @id_ac2)            AS acidente,
       (SELECT COUNT(*) FROM pessoa   WHERE id_acidente = @id_ac2)   AS pessoas,
       (SELECT COUNT(*) FROM veiculo  WHERE id_acidente = @id_ac2)   AS veiculos,
       (SELECT COUNT(*) FROM causa_acidente WHERE id_acidente = @id_ac2) AS causas;

-- Estado final: 73.156 acidentes da PRF + 1 acidente fictício de teste.
SELECT SUM(id <  9000001) AS acidentes_prf,
       SUM(id >= 9000001) AS acidentes_de_teste
  FROM acidente;

-- =============================================================================
-- 4. Comandos que DEVEM FALHAR — demonstração das restrições
--    (descomente um por vez no DBeaver para mostrar à banca)
-- =============================================================================

-- 4.1 CHECK de idade (0..110) → ERROR 3819: Check constraint 'ck_pessoa_idade' is violated.
-- INSERT INTO pessoa (id_acidente, id_veiculo, tipo_envolvido, estado_fisico, idade, sexo)
-- VALUES (@id_ac1, NULL, 'Pedestre', 'Ileso', 150, 'Masculino');

-- 4.2 Condutor sem veículo → ERROR 3819: Check constraint 'ck_pessoa_envolvido_veiculo' is violated.
-- INSERT INTO pessoa (id_acidente, id_veiculo, tipo_envolvido, estado_fisico, idade, sexo)
-- VALUES (@id_ac1, NULL, 'Condutor', 'Ileso', 40, 'Masculino');

-- 4.3 Pessoa num veículo de OUTRO acidente (veículo 1018215 é do acidente 571772)
--     → ERROR 1452: ... foreign key constraint fails (fk_pessoa_veiculo_mesmo_acidente)
-- INSERT INTO pessoa (id_acidente, id_veiculo, tipo_envolvido, estado_fisico, idade, sexo)
-- VALUES (@id_ac1, 1018215, 'Passageiro', 'Ileso', 30, 'Feminino');

-- 4.4 Segunda causa principal no mesmo acidente
--     → ERROR 1062: Duplicate entry ... for key 'causa_acidente.uq_causa_acidente_uma_principal'
-- UPDATE causa_acidente SET principal = TRUE WHERE id_acidente = @id_ac1;

-- 4.5 Apagar acidente que ainda tem dependentes
--     → ERROR 1451: Cannot delete or update a parent row: a foreign key constraint fails
-- DELETE FROM acidente WHERE id = 571772;

-- 4.6 Unidade da PRF dupla (UOP e delegacia ao mesmo tempo)
--     → ERROR 3819: Check constraint 'ck_acidente_unidade_unica' is violated.
-- UPDATE acidente SET id_delegacia = 1 WHERE id = @id_ac1;

-- 4.7 Fase do dia fora da lista (v2: era FK, agora é CHECK)
--     → ERROR 3819: Check constraint 'ck_acidente_fase_dia' is violated.
-- UPDATE acidente SET fase_dia = 'Madrugada' WHERE id = @id_ac1;


-- #############################################################################
-- ##  06_dql_consultas.sql
-- #############################################################################

-- =============================================================================
--  UNIFACS — Projeto Integrador de Banco de Dados — A3
--  Time Índice — Grupo 4 | Cenário: USUPORT
--  Arquivo: 06_dql_consultas.sql — DQL: consultas estratégicas para a gestão
-- -----------------------------------------------------------------------------
--  Cada consulta começa com um marcador "-- @Qnn | título". O painel do app
--  Streamlit lê ESTE arquivo, separa as consultas pelos marcadores e executa
--  exatamente o mesmo SQL (fonte única).
--
--  Parâmetros (variáveis de sessão). No DBeaver, altere os SET abaixo; no
--  app, eles são definidos pela tela antes de cada consulta:
--     @data_ini, @data_fim → filtro temporal (intervalo de datas)
--     @id_acidente         → acidente usado na Q16 (ficha completa)
--
--  Como contamos vítimas sem duplicar: um JOIN de acidente com pessoa E com
--  causa multiplica as linhas (pessoa × causa). Por isso as vítimas são
--  somadas antes, por acidente, na CTE "totais" (WITH ... AS), e só depois
--  juntadas ao resto. ilesos/feridos/mortos saem de pessoa.estado_fisico.
-- =============================================================================

USE usuport;

SET @data_ini    = '2024-01-01';
SET @data_fim    = '2024-12-31';
SET @id_acidente = 571778;
SET lc_time_names = 'pt_BR';      -- DAYNAME/MONTHNAME em português

-- @Q01 | Acidentes e óbitos por UF e mês
-- Objetivo: série mensal por UF para acompanhar a evolução no período.
-- Técnicas: CTE, INNER JOIN (cidade), LEFT JOIN (totais), GROUP BY, COUNT, SUM, filtro temporal.
WITH totais AS (
    SELECT id_acidente,
           SUM(estado_fisico = 'Óbito') AS mortos
      FROM pessoa
     GROUP BY id_acidente
)
SELECT c.uf,
       DATE_FORMAT(a.data, '%Y-%m')  AS mes,
       COUNT(*)                      AS acidentes,
       COALESCE(SUM(t.mortos), 0)    AS obitos
  FROM acidente a
 INNER JOIN cidade c  ON c.id = a.id_cidade
  LEFT JOIN totais t  ON t.id_acidente = a.id
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY c.uf, mes
 ORDER BY c.uf, mes;

-- @Q02 | Volume de acidentes por causa principal no período
-- Objetivo: quais causas mais originam acidentes (e mortes) num intervalo de datas.
-- Técnicas: INNER JOIN em 3 tabelas, LEFT JOIN, GROUP BY, COUNT, SUM, função de janela (percentual).
WITH totais AS (
    SELECT id_acidente, SUM(estado_fisico = 'Óbito') AS mortos
      FROM pessoa GROUP BY id_acidente
)
SELECT ca_desc.descricao                                        AS causa_principal,
       COUNT(*)                                                 AS acidentes,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)         AS pct_acidentes,
       COALESCE(SUM(t.mortos), 0)                               AS obitos
  FROM acidente a
 INNER JOIN causa_acidente ca     ON ca.id_acidente = a.id AND ca.principal = TRUE
 INNER JOIN causa          ca_desc ON ca_desc.id = ca.id_causa
  LEFT JOIN totais         t      ON t.id_acidente = a.id
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY ca_desc.descricao
 ORDER BY acidentes DESC
 LIMIT 15;

-- @Q03 | Óbitos por tipo de veículo
-- Objetivo: ocupantes de que tipo de veículo mais morrem e qual a letalidade.
-- Técnicas: INNER JOIN em 4 tabelas, GROUP BY, COUNT, SUM, AVG, filtro temporal.
SELECT tv.descricao                                          AS tipo_veiculo,
       COUNT(*)                                              AS ocupantes,
       SUM(p.estado_fisico = 'Óbito')                        AS obitos,
       ROUND(100 * AVG(p.estado_fisico = 'Óbito'), 2)        AS pct_obito,
       ROUND(AVG(p.idade), 1)                                AS idade_media
  FROM pessoa p
 INNER JOIN veiculo      v  ON v.id  = p.id_veiculo
 INNER JOIN tipo_veiculo tv ON tv.id = v.id_tipo_veiculo
 INNER JOIN acidente     a  ON a.id  = p.id_acidente
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY tv.descricao
 ORDER BY obitos DESC;

-- @Q04 | Acidentes por fase do dia × condição meteorológica
-- Objetivo: cruzar luminosidade e tempo para orientar fiscalização e sinalização.
-- Técnicas: CTE, LEFT JOIN, GROUP BY com 2 colunas, COUNT, SUM, filtro temporal.
-- v2: fase do dia e condição são colunas com CHECK no próprio acidente,
--     por isso esta consulta não precisa mais de JOIN com catálogo.
WITH totais AS (
    SELECT id_acidente, SUM(estado_fisico = 'Óbito') AS mortos
      FROM pessoa GROUP BY id_acidente
)
SELECT a.fase_dia                                             AS fase_dia,
       a.condicao_meteorologica                               AS condicao,
       COUNT(*)                                               AS acidentes,
       COALESCE(SUM(t.mortos), 0)                             AS obitos,
       ROUND(100 * COALESCE(SUM(t.mortos), 0) / COUNT(*), 2)  AS obitos_por_100_acidentes
  FROM acidente a
  LEFT JOIN totais t ON t.id_acidente = a.id
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY a.fase_dia, a.condicao_meteorologica
 ORDER BY acidentes DESC;

-- @Q05 | Média de idade por estado físico e sexo
-- Objetivo: perfil etário das vítimas por gravidade (AVG ignora idades NULL).
-- Técnicas: GROUP BY, AVG, MIN, MAX, COUNT de coluna (conta só não nulos).
SELECT p.estado_fisico,
       p.sexo,
       COUNT(*)                AS pessoas,
       COUNT(p.idade)          AS com_idade_informada,
       ROUND(AVG(p.idade), 1)  AS idade_media,
       MIN(p.idade)            AS idade_min,
       MAX(p.idade)            AS idade_max
  FROM pessoa p
 GROUP BY p.estado_fisico, p.sexo
 ORDER BY FIELD(p.estado_fisico, 'Óbito', 'Lesões Graves', 'Lesões Leves', 'Ileso', 'Não Informado'),
          pessoas DESC;

-- @Q06 | Traçados da via com mais vítimas fatais
-- Objetivo: características da via associadas a mortes. Um acidente com
-- "Reta;Declive" conta nos dois traçados (o atributo é multivalorado).
-- Técnicas: CTE, INNER JOIN (tabela associativa N:N), LEFT JOIN, GROUP BY, SUM, filtro temporal.
WITH totais AS (
    SELECT id_acidente, SUM(estado_fisico = 'Óbito') AS mortos
      FROM pessoa GROUP BY id_acidente
)
SELECT tr.descricao                                           AS tracado,
       COUNT(*)                                               AS acidentes,
       COALESCE(SUM(t.mortos), 0)                             AS obitos,
       ROUND(100 * COALESCE(SUM(t.mortos), 0) / COUNT(*), 2)  AS obitos_por_100_acidentes
  FROM acidente_tracado at2
 INNER JOIN tracado  tr ON tr.id = at2.id_tracado
 INNER JOIN acidente a  ON a.id  = at2.id_acidente
  LEFT JOIN totais   t  ON t.id_acidente = a.id
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY tr.descricao
 ORDER BY obitos DESC;

-- @Q07 | Ranking das superintendências da PRF
-- Objetivo: carga de trabalho e gravidade por superintendência. Resolve o
-- ARCO: a superintendência vem da UOP, ou da delegacia, ou direto do acidente.
-- Técnicas: CTE, cadeia de LEFT JOIN com COALESCE, GROUP BY, COUNT, SUM.
WITH totais AS (
    SELECT id_acidente, SUM(estado_fisico = 'Óbito') AS mortos
      FROM pessoa GROUP BY id_acidente
)
SELECT COALESCE(s.sigla, '(sem unidade)')                     AS superintendencia,
       COUNT(*)                                               AS acidentes,
       COALESCE(SUM(t.mortos), 0)                             AS obitos,
       ROUND(100 * COALESCE(SUM(t.mortos), 0) / COUNT(*), 2)  AS obitos_por_100_acidentes
  FROM acidente a
  LEFT JOIN uop              u ON u.id = a.id_uop
  LEFT JOIN delegacia        d ON d.id = COALESCE(u.id_delegacia, a.id_delegacia)
  LEFT JOIN superintendencia s ON s.id = COALESCE(d.id_superintendencia, a.id_superintendencia)
  LEFT JOIN totais           t ON t.id_acidente = a.id
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY superintendencia
 ORDER BY acidentes DESC;

-- @Q08 | Ranking das 20 UOPs com mais acidentes
-- Objetivo: postos operacionais mais demandados, com delegacia e superintendência.
-- Técnicas: INNER JOIN em 4 tabelas (hierarquia), LEFT JOIN, GROUP BY, COUNT, SUM, RANK().
WITH totais AS (
    SELECT id_acidente, SUM(estado_fisico = 'Óbito') AS mortos
      FROM pessoa GROUP BY id_acidente
)
SELECT RANK() OVER (ORDER BY COUNT(*) DESC)  AS posicao,
       u.sigla                               AS uop,
       d.sigla                               AS delegacia,
       s.sigla                               AS superintendencia,
       COUNT(*)                              AS acidentes,
       COALESCE(SUM(t.mortos), 0)            AS obitos
  FROM acidente a
 INNER JOIN uop              u ON u.id = a.id_uop
 INNER JOIN delegacia        d ON d.id = u.id_delegacia
 INNER JOIN superintendencia s ON s.id = d.id_superintendencia
  LEFT JOIN totais           t ON t.id_acidente = a.id
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY u.sigla, d.sigla, s.sigla
 ORDER BY acidentes DESC
 LIMIT 20;

-- @Q09 | Trechos críticos: BR e segmento de 10 km
-- Objetivo: onde concentrar fiscalização — trechos de 10 km com mais mortes.
-- Técnicas: expressão no GROUP BY (FLOOR), INNER JOIN, LEFT JOIN, HAVING, COUNT, SUM.
WITH totais AS (
    SELECT id_acidente, SUM(estado_fisico = 'Óbito') AS mortos
      FROM pessoa GROUP BY id_acidente
)
-- km_inicio = início do trecho (ex.: km 272,5 cai no trecho que começa no km 270).
SELECT a.br,
       c.uf,
       FLOOR(a.km / 10) * 10          AS km_inicio,
       COUNT(*)                       AS acidentes,
       COALESCE(SUM(t.mortos), 0)     AS obitos
  FROM acidente a
 INNER JOIN cidade c ON c.id = a.id_cidade
  LEFT JOIN totais t ON t.id_acidente = a.id
 WHERE a.br IS NOT NULL
   AND a.data BETWEEN @data_ini AND @data_fim
 GROUP BY a.br, c.uf, km_inicio
HAVING COUNT(*) >= 20
 ORDER BY obitos DESC, acidentes DESC
 LIMIT 20;

-- @Q10 | Acidentes urbanos × rurais
-- Objetivo: comparar volume e gravidade entre área urbana e rural.
-- Técnicas: CTE, LEFT JOIN, GROUP BY, COUNT, SUM, AVG, percentual com janela.
WITH totais AS (
    SELECT id_acidente,
           COUNT(*)                               AS pessoas,
           SUM(estado_fisico = 'Óbito')           AS mortos,
           SUM(estado_fisico = 'Lesões Graves')   AS feridos_graves
      FROM pessoa GROUP BY id_acidente
)
SELECT a.uso_solo,
       COUNT(*)                                               AS acidentes,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)       AS pct_acidentes,
       ROUND(AVG(t.pessoas), 2)                               AS pessoas_por_acidente,
       SUM(t.feridos_graves)                                  AS feridos_graves,
       SUM(t.mortos)                                          AS obitos,
       ROUND(100 * SUM(t.mortos) / COUNT(*), 2)               AS obitos_por_100_acidentes
  FROM acidente a
  LEFT JOIN totais t ON t.id_acidente = a.id
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY a.uso_solo;

-- @Q11 | Veículos sem nenhuma pessoa registrada
-- Objetivo: medir a lacuna de registro (linhas do CSV sem pesid).
-- Técnicas: LEFT JOIN ... IS NULL (anti-junção), GROUP BY, COUNT, percentual.
-- O LEFT JOIN mantém TODOS os veículos; quando não existe ocupante, as colunas
-- do lado direito vêm NULL — é isso que "o.id_veiculo IS NULL" conta.
SELECT tv.descricao                                          AS tipo_veiculo,
       COUNT(*)                                              AS veiculos,
       SUM(o.id_veiculo IS NULL)                             AS sem_pessoa,
       ROUND(100 * SUM(o.id_veiculo IS NULL) / COUNT(*), 1)  AS pct_sem_pessoa
  FROM veiculo v
 INNER JOIN tipo_veiculo tv ON tv.id = v.id_tipo_veiculo
  LEFT JOIN (SELECT id_veiculo, COUNT(*) AS ocupantes        -- ocupantes por veículo
               FROM pessoa
              WHERE id_veiculo IS NOT NULL
              GROUP BY id_veiculo) o ON o.id_veiculo = v.id
 GROUP BY tv.descricao
 ORDER BY sem_pessoa DESC;

-- @Q12 | Acidentes e óbitos por dia da semana
-- Objetivo: dia da semana NÃO é armazenado (seria derivado da data): é
-- calculado com DAYNAME, em português graças a lc_time_names = 'pt_BR'.
-- Técnicas: função de data, LEFT JOIN, GROUP BY, COUNT, SUM, AVG, filtro temporal.
WITH totais AS (
    SELECT id_acidente, SUM(estado_fisico = 'Óbito') AS mortos
      FROM pessoa GROUP BY id_acidente
)
SELECT DAYOFWEEK(a.data)                         AS n,
       DAYNAME(a.data)                           AS dia_semana,
       COUNT(*)                                  AS acidentes,
       COALESCE(SUM(t.mortos), 0)                AS obitos,
       ROUND(AVG(COALESCE(t.mortos, 0)), 3)      AS media_obitos_por_acidente
  FROM acidente a
  LEFT JOIN totais t ON t.id_acidente = a.id
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY n, dia_semana
 ORDER BY n;

-- @Q13 | Letalidade pelo primeiro evento do acidente
-- Objetivo: qual tipo de evento inicial (ordem = 1) é mais letal.
-- Técnicas: INNER JOIN com condição extra (ordem = 1), LEFT JOIN, GROUP BY, COUNT, SUM.
WITH totais AS (
    SELECT id_acidente, SUM(estado_fisico = 'Óbito') AS mortos
      FROM pessoa GROUP BY id_acidente
)
SELECT ta.descricao                                           AS primeiro_evento,
       COUNT(*)                                               AS acidentes,
       COALESCE(SUM(t.mortos), 0)                             AS obitos,
       ROUND(100 * COALESCE(SUM(t.mortos), 0) / COUNT(*), 2)  AS obitos_por_100_acidentes
  FROM acidente a
 INNER JOIN acidente_tipo at1 ON at1.id_acidente = a.id AND at1.ordem = 1
 INNER JOIN tipo_acidente ta  ON ta.id = at1.id_tipo
  LEFT JOIN totais        t   ON t.id_acidente = a.id
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY ta.descricao
 ORDER BY obitos_por_100_acidentes DESC;

-- @Q14 | Vítimas fatais por faixa etária e tipo de envolvido
-- Objetivo: quem morre nas rodovias (condutor, passageiro, pedestre...) e com que idade.
-- Técnicas: CASE para faixas, INNER JOIN, GROUP BY, COUNT, filtro temporal.
SELECT CASE WHEN p.idade IS NULL THEN '(não informada)'
            WHEN p.idade < 18     THEN '00-17'
            WHEN p.idade < 30     THEN '18-29'
            WHEN p.idade < 45     THEN '30-44'
            WHEN p.idade < 60     THEN '45-59'
            ELSE '60+' END                       AS faixa_etaria,
       SUM(p.tipo_envolvido = 'Condutor')        AS condutores,
       SUM(p.tipo_envolvido = 'Passageiro')      AS passageiros,
       SUM(p.tipo_envolvido = 'Pedestre')        AS pedestres,
       SUM(p.tipo_envolvido = 'Cavaleiro')       AS cavaleiros,
       COUNT(*)                                  AS total_obitos
  FROM pessoa p
 INNER JOIN acidente a ON a.id = p.id_acidente
 WHERE p.estado_fisico = 'Óbito'
   AND a.data BETWEEN @data_ini AND @data_fim
 GROUP BY faixa_etaria
 ORDER BY faixa_etaria;

-- @Q15 | Acidentes por hora do dia e classificação
-- Objetivo: horários de pico e horários mais graves.
-- Técnicas: HOUR(), GROUP BY, COUNT, SUM condicional, filtro temporal.
SELECT HOUR(a.horario)                                     AS hora,
       COUNT(*)                                            AS acidentes,
       SUM(a.classificacao = 'Sem Vítimas')                AS sem_vitimas,
       SUM(a.classificacao = 'Com Vítimas Feridas')        AS com_feridos,
       SUM(a.classificacao = 'Com Vítimas Fatais')         AS com_mortos
  FROM acidente a
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY hora
 ORDER BY hora;

-- @Q16 | Ficha completa de um acidente (junções + subconsultas)
-- Objetivo: reconstituir o "registro da planilha" a partir do modelo normalizado.
-- Técnicas: INNER JOIN e LEFT JOIN em cadeia, GROUP_CONCAT, subconsultas correlacionadas.
SELECT a.id,
       a.data,
       DAYNAME(a.data)                                   AS dia_semana,
       a.horario,
       c.nome                                            AS municipio,
       c.uf,
       a.br, a.km, a.sentido, a.tipo_pista, a.uso_solo,
       a.fase_dia,
       a.condicao_meteorologica                          AS condicao,
       a.classificacao,
       COALESCE(u.sigla, '-')                            AS uop,
       COALESCE(d.sigla, '-')                            AS delegacia,
       COALESCE(s.sigla, '-')                            AS superintendencia,
       (SELECT cz.descricao FROM causa_acidente ca JOIN causa cz ON cz.id = ca.id_causa
         WHERE ca.id_acidente = a.id AND ca.principal)   AS causa_principal,
       (SELECT GROUP_CONCAT(ta.descricao ORDER BY at1.ordem SEPARATOR ' > ')
          FROM acidente_tipo at1 JOIN tipo_acidente ta ON ta.id = at1.id_tipo
         WHERE at1.id_acidente = a.id)                   AS sequencia_tipos,
       (SELECT GROUP_CONCAT(tr.descricao ORDER BY tr.descricao SEPARATOR ', ')
          FROM acidente_tracado x JOIN tracado tr ON tr.id = x.id_tracado
         WHERE x.id_acidente = a.id)                     AS tracados,
       (SELECT COUNT(*) FROM veiculo v WHERE v.id_acidente = a.id) AS veiculos,
       (SELECT COUNT(*) FROM pessoa  p WHERE p.id_acidente = a.id) AS pessoas
  FROM acidente a
 INNER JOIN cidade                 c  ON c.id  = a.id_cidade
  LEFT JOIN uop                    u  ON u.id  = a.id_uop
  LEFT JOIN delegacia              d  ON d.id  = COALESCE(u.id_delegacia, a.id_delegacia)
  LEFT JOIN superintendencia       s  ON s.id  = COALESCE(d.id_superintendencia, a.id_superintendencia)
 WHERE a.id = @id_acidente;

-- @Q17 | Os 15 municípios com mais acidentes
-- Objetivo: municípios prioritários (chave natural nome + UF evita misturar homônimos).
-- Técnicas: CTE, INNER JOIN, LEFT JOIN, GROUP BY por (nome, uf), COUNT, SUM, filtro temporal.
WITH totais AS (
    SELECT id_acidente, SUM(estado_fisico = 'Óbito') AS mortos
      FROM pessoa GROUP BY id_acidente
)
SELECT c.nome                         AS municipio,
       c.uf,
       COUNT(*)                       AS acidentes,
       COALESCE(SUM(t.mortos), 0)     AS obitos
  FROM acidente a
 INNER JOIN cidade c ON c.id = a.id_cidade
  LEFT JOIN totais t ON t.id_acidente = a.id
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY c.id, c.nome, c.uf
 ORDER BY acidentes DESC
 LIMIT 15;

-- @Q18 | Acidentes atendidos por superintendência de outra UF
-- Objetivo: evidenciar a regra de negócio "a regional nem sempre é da UF do
-- acidente" (ex.: entorno do DF em Goiás atendido pela SPRF-DF).
-- Técnicas: cadeia de JOIN com COALESCE (arco), condição sobre texto (RIGHT), GROUP BY, COUNT.
SELECT c.uf                    AS uf_do_acidente,
       s.sigla                 AS superintendencia,
       COUNT(*)                AS acidentes
  FROM acidente a
 INNER JOIN cidade           c ON c.id = a.id_cidade
  LEFT JOIN uop              u ON u.id = a.id_uop
  LEFT JOIN delegacia        d ON d.id = COALESCE(u.id_delegacia, a.id_delegacia)
 INNER JOIN superintendencia s ON s.id = COALESCE(d.id_superintendencia, a.id_superintendencia)
 WHERE s.sigla LIKE 'SPRF-%'
   AND RIGHT(s.sigla, 2) <> c.uf
 GROUP BY c.uf, s.sigla
 ORDER BY acidentes DESC;


-- #############################################################################
-- ##  07_views.sql
-- #############################################################################

-- =============================================================================
--  UNIFACS — Projeto Integrador de Banco de Dados — A3
--  Time Índice — Grupo 4 | Cenário: USUPORT
--  Arquivo: 07_views.sql — visões (VIEW) usadas pelo app e pelas consultas
-- -----------------------------------------------------------------------------
--  Uma VIEW é uma consulta guardada com nome: não armazena dados, só
--  "remonta" a informação a partir das tabelas normalizadas. Assim o app
--  enxerga o acidente "completo" (como na planilha) sem que o banco perca a 3FN.
--
--    vw_acidente_unidade     — resolve o ARCO: UOP/delegacia/superintendência
--    vw_acidente_totais      — vítimas por acidente, derivadas de estado_fisico
--    vw_acidente_detalhe     — ficha do acidente (dia da semana calculado,
--                              causas/tipos/traçados com GROUP_CONCAT)
--    vw_pessoa_detalhe       — pessoa + acidente + veículo
--    vw_classificacao_conferencia — classificação registrada × calculada
-- =============================================================================

USE usuport;

-- -----------------------------------------------------------------------------
-- vw_acidente_unidade: uma linha por acidente com as três siglas da PRF.
-- A delegacia vem da UOP (se houver) ou do próprio acidente; a
-- superintendência vem da delegacia (se houver) ou do próprio acidente.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_acidente_unidade AS
SELECT a.id                           AS id_acidente,
       u.sigla                        AS uop,
       d.sigla                        AS delegacia,
       s.sigla                        AS superintendencia,
       CASE WHEN a.id_uop IS NOT NULL              THEN 'UOP'
            WHEN a.id_delegacia IS NOT NULL        THEN 'Delegacia'
            WHEN a.id_superintendencia IS NOT NULL THEN 'Superintendência'
            ELSE 'Nenhuma' END        AS nivel_registrado
  FROM acidente a
  LEFT JOIN uop              u ON u.id = a.id_uop
  LEFT JOIN delegacia        d ON d.id = COALESCE(u.id_delegacia, a.id_delegacia)
  LEFT JOIN superintendencia s ON s.id = COALESCE(d.id_superintendencia, a.id_superintendencia);

-- -----------------------------------------------------------------------------
-- vw_acidente_totais: os contadores que a planilha trazia em colunas
-- (ilesos, feridos_leves, feridos_graves, mortos) — aqui CALCULADOS.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_acidente_totais AS
SELECT p.id_acidente,
       COUNT(*)                                AS pessoas,
       SUM(p.estado_fisico = 'Ileso')          AS ilesos,
       SUM(p.estado_fisico = 'Lesões Leves')   AS feridos_leves,
       SUM(p.estado_fisico = 'Lesões Graves')  AS feridos_graves,
       SUM(p.estado_fisico = 'Óbito')          AS mortos,
       SUM(p.estado_fisico = 'Não Informado')  AS estado_nao_informado
  FROM pessoa p
 GROUP BY p.id_acidente;

-- -----------------------------------------------------------------------------
-- vw_acidente_detalhe: ficha do acidente.
--  * dia_semana: ELT(DAYOFWEEK(data), ...) devolve o mesmo texto da PRF
--    ("segunda-feira") e não depende da configuração lc_time_names da sessão.
--  * causas/tipos/traçados: GROUP_CONCAT junta as linhas das tabelas
--    associativas numa célula — o caminho inverso da normalização.
--  * Subconsultas correlacionadas (e não JOIN + GROUP BY) para que, ao filtrar
--    por id ou por data, o MySQL calcule só as linhas pedidas.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_acidente_detalhe AS
SELECT a.id,
       a.data,
       ELT(DAYOFWEEK(a.data), 'domingo', 'segunda-feira', 'terça-feira', 'quarta-feira',
           'quinta-feira', 'sexta-feira', 'sábado')                     AS dia_semana,
       a.horario,
       c.uf,
       c.nome                                                           AS municipio,
       a.br,
       a.km,
       a.sentido,
       a.tipo_pista,
       a.uso_solo,
       a.classificacao,
       a.condicao_meteorologica,                         -- v2: coluna com CHECK, sem JOIN
       a.fase_dia,
       a.latitude,
       a.longitude,
       u.sigla                                                          AS uop,
       d.sigla                                                          AS delegacia,
       s.sigla                                                          AS superintendencia,
       (SELECT cz.descricao
          FROM causa_acidente ca JOIN causa cz ON cz.id = ca.id_causa
         WHERE ca.id_acidente = a.id AND ca.principal = TRUE)           AS causa_principal,
       (SELECT GROUP_CONCAT(cz.descricao ORDER BY ca.principal DESC, cz.descricao SEPARATOR '; ')
          FROM causa_acidente ca JOIN causa cz ON cz.id = ca.id_causa
         WHERE ca.id_acidente = a.id)                                   AS causas,
       (SELECT GROUP_CONCAT(ta.descricao ORDER BY at1.ordem SEPARATOR ' > ')
          FROM acidente_tipo at1 JOIN tipo_acidente ta ON ta.id = at1.id_tipo
         WHERE at1.id_acidente = a.id)                                  AS tipos,
       (SELECT GROUP_CONCAT(tr.descricao ORDER BY tr.descricao SEPARATOR '; ')
          FROM acidente_tracado x JOIN tracado tr ON tr.id = x.id_tracado
         WHERE x.id_acidente = a.id)                                    AS tracados,
       (SELECT COUNT(*) FROM veiculo v WHERE v.id_acidente = a.id)      AS veiculos,
       (SELECT COUNT(*) FROM pessoa  p WHERE p.id_acidente = a.id)      AS pessoas,
       (SELECT COUNT(*) FROM pessoa  p
         WHERE p.id_acidente = a.id AND p.estado_fisico IN ('Lesões Leves', 'Lesões Graves')) AS feridos,
       (SELECT COUNT(*) FROM pessoa  p
         WHERE p.id_acidente = a.id AND p.estado_fisico = 'Óbito')      AS mortos
  FROM acidente a
  JOIN cidade                 c  ON c.id  = a.id_cidade
  LEFT JOIN uop               u  ON u.id  = a.id_uop
  LEFT JOIN delegacia         d  ON d.id  = COALESCE(u.id_delegacia, a.id_delegacia)
  LEFT JOIN superintendencia  s  ON s.id  = COALESCE(d.id_superintendencia, a.id_superintendencia);

-- -----------------------------------------------------------------------------
-- vw_pessoa_detalhe: pessoa com dados do acidente e do veículo ocupado
-- (LEFT JOIN: pedestres e testemunhas não têm veículo).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_pessoa_detalhe AS
SELECT p.pesid,
       p.id_acidente,
       a.data,
       c.uf,
       c.nome          AS municipio,
       p.tipo_envolvido,
       p.estado_fisico,
       p.idade,
       p.sexo,
       p.id_veiculo,
       tv.descricao    AS tipo_veiculo,
       v.marca,
       v.ano_fabricacao
  FROM pessoa p
  JOIN acidente a          ON a.id  = p.id_acidente
  JOIN cidade   c          ON c.id  = a.id_cidade
  LEFT JOIN veiculo v      ON v.id  = p.id_veiculo
  LEFT JOIN tipo_veiculo tv ON tv.id = v.id_tipo_veiculo;

-- -----------------------------------------------------------------------------
-- vw_classificacao_conferencia: compara a classificação registrada pela PRF
-- com a que se calcula do estado físico das pessoas (regra RN08).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_classificacao_conferencia AS
SELECT t.id_acidente,
       a.classificacao                                       AS registrada,
       CASE WHEN t.mortos > 0                           THEN 'Com Vítimas Fatais'
            WHEN t.feridos_leves + t.feridos_graves > 0 THEN 'Com Vítimas Feridas'
            ELSE 'Sem Vítimas' END                           AS calculada
  FROM vw_acidente_totais t
  JOIN acidente a ON a.id = t.id_acidente;

-- Conferência: exemplo de uso das views.
SELECT id, data, dia_semana, municipio, uf, causa_principal, tipos, tracados,
       veiculos, pessoas, feridos, mortos
  FROM vw_acidente_detalhe
 WHERE id IN (571774, 571778, 661235, 571802, 661121, 9000001);

SELECT COUNT(*)                                AS acidentes_conferidos,
       SUM(registrada = calculada)             AS iguais,
       SUM(registrada <> calculada)            AS diferentes,
       SUM(registrada IS NULL)                 AS sem_classificacao_registrada
  FROM vw_classificacao_conferencia;
