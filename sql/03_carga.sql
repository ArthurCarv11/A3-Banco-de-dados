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
