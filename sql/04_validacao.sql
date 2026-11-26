-- =============================================================================
--  UNIFACS — Projeto Integrador de Banco de Dados — A3
--  Time Índice — Grupo 4 | Cenário: USUPORT
--  Arquivo: 04_validacao.sql — conferência da carga
-- -----------------------------------------------------------------------------
--  Cada verificação devolve: o que foi medido, o valor ESPERADO (vindo do
--  perfilamento do CSV), o valor OBTIDO no banco e a situação (OK/DIVERGENTE).
--    A. Contagens das 16 tabelas
--    B. Regras de limpeza: quantos registros cada regra afetou
--    C. Regras de negócio (violações devem ser 0)
--    D. Remoção da staging (o esquema final fica só com as 16 tabelas)
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
    UNION ALL SELECT 'A12 condicoes meteorologicas',     10, (SELECT COUNT(*) FROM condicao_meteorologica)
    UNION ALL SELECT 'A13 fases do dia',                  4, (SELECT COUNT(*) FROM fase_dia)
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
-- D. Remoção da staging — o esquema final fica com as 16 tabelas do modelo.
--    (comente a linha abaixo se quiser manter a staging para inspeção)
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_acidente_csv;
