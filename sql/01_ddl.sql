-- =============================================================================
--  UNIFACS — UC Projeto Integrador de Banco de Dados — Avaliação A3
--  Equipe: Time Índice — Grupo 4  |  Cenário: USUPORT
--  Arquivo: 01_ddl.sql — DDL (Data Definition Language)
-- -----------------------------------------------------------------------------
--  O que este script faz, em ordem:
--    1. CREATE DATABASE usuport (utf8mb4, colação sem acento/sem caixa);
--    2. DROP TABLE IF EXISTS das tabelas, na ordem INVERSA das FKs
--       (primeiro quem referencia, depois quem é referenciado);
--    3. CREATE TABLE das 13 tabelas, na ordem DIRETA das FKs
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
DROP TABLE IF EXISTS tracado;          -- catálogo da v1; virou CHECK na v2 (parte 2)
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
--     que a PRF pode revisar (causas, tipos de acidente, tipos de veículo).
--     Listas pequenas, curtas e fixas viram coluna com CHECK (sexo, sentido,
--     fase do dia, condição meteorológica, traçado etc.): o CHECK valida na
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
--     A ordem não importa, por isso a PK é (id_acidente, tracado).
--     v2 (parte 2): o catálogo "tracado" (12 valores curtos e fixos) virou
--     CHECK. A tabela associativa CONTINUA: é ela que resolve o atributo
--     multivalorado (1FN); só passa a guardar o texto em vez do id.
-- -----------------------------------------------------------------------------
CREATE TABLE acidente_tracado (
    id_acidente INT UNSIGNED     NOT NULL
                COMMENT 'FK: acidente',
    tracado     VARCHAR(21)      NOT NULL
                COMMENT 'Característica de traçado presente no local (12 valores fixos; ex.: Reta, Curva)',
    CONSTRAINT pk_acidente_tracado PRIMARY KEY (id_acidente, tracado),
    CONSTRAINT fk_acidente_tracado_acidente FOREIGN KEY (id_acidente) REFERENCES acidente (id),
    CONSTRAINT ck_acidente_tracado_valor CHECK (tracado IN
                      ('Aclive','Curva','Declive','Desvio Temporário','Em Obras','Interseção de Vias',
                       'Ponte','Reta','Retorno Regulamentado','Rotatória','Túnel','Viaduto'))
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

-- ALTER 4 — Índice de COBERTURA para as contagens por acidente (v2, parte 3).
--   Quase todas as consultas gerenciais somam vítimas por acidente:
--       SELECT id_acidente, SUM(estado_fisico = 'Óbito') ... GROUP BY id_acidente
--   Antes, o MySQL percorria o índice da FK (só id_acidente) e, para CADA uma
--   das 179 mil pessoas, buscava estado_fisico na tabela (leitura extra).
--   Com (id_acidente, estado_fisico), as duas colunas estão no próprio índice
--   (EXPLAIN mostra "Extra: Using index"): nenhuma leitura extra.
--   Efeito colateral esperado: o MySQL APAGA SOZINHO o índice implícito da FK
--   fk_pessoa_acidente, porque este índice novo também serve à FK (começa por
--   id_acidente). Não há índice duplicado; mas este índice passa a ser
--   obrigatório: tentar removê-lo dá erro 1553 (needed in a foreign key).
ALTER TABLE pessoa
    ADD INDEX idx_pessoa_acidente_estado (id_acidente, estado_fisico);

-- Conferência rápida: deve listar as 13 tabelas.
SELECT table_name AS tabela, table_comment AS finalidade
  FROM information_schema.tables
 WHERE table_schema = 'usuport' AND table_type = 'BASE TABLE'
 ORDER BY table_name;
