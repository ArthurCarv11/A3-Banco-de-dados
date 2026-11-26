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
       cm.descricao                                                     AS condicao_meteorologica,
       f.descricao                                                      AS fase_dia,
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
  JOIN condicao_meteorologica cm ON cm.id = a.id_condicao
  JOIN fase_dia               f  ON f.id  = a.id_fase_dia
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
