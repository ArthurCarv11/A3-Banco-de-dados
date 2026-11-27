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
--     @estado              → estado físico procurado na Q20 (v2, parte 3)
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
SET @estado      = 'Não Informado';   -- Ileso, Lesões Leves, Lesões Graves, Óbito ou Não Informado
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
-- v2: o texto do traçado já está na associativa; não há JOIN com catálogo.
WITH totais AS (
    SELECT id_acidente, SUM(estado_fisico = 'Óbito') AS mortos
      FROM pessoa GROUP BY id_acidente
)
SELECT at2.tracado                                            AS tracado,
       COUNT(*)                                               AS acidentes,
       COALESCE(SUM(t.mortos), 0)                             AS obitos,
       ROUND(100 * COALESCE(SUM(t.mortos), 0) / COUNT(*), 2)  AS obitos_por_100_acidentes
  FROM acidente_tracado at2
 INNER JOIN acidente a  ON a.id  = at2.id_acidente
  LEFT JOIN totais   t  ON t.id_acidente = a.id
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY at2.tracado
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
       (SELECT GROUP_CONCAT(x.tracado ORDER BY x.tracado SEPARATOR ', ')
          FROM acidente_tracado x
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

-- @Q19 | Qualidade do registro: dados não informados por superintendência
-- Objetivo: onde a PRF mais deixa de registrar o estado físico, o sexo e a
-- idade das pessoas — o que limita as análises de vítimas daquela região.
-- Técnicas: INNER JOIN, cadeia de LEFT JOIN com COALESCE (arco), GROUP BY,
-- COUNT, SUM e AVG condicionais (AVG de uma comparação = percentual), filtro temporal.
SELECT COALESCE(s.sigla, '(sem unidade)')                         AS superintendencia,
       COUNT(*)                                                   AS pessoas,
       SUM(p.estado_fisico = 'Não Informado')                     AS estado_nao_informado,
       ROUND(100 * AVG(p.estado_fisico = 'Não Informado'), 1)     AS pct_estado_nao_informado,
       SUM(p.sexo IN ('Não Informado', 'Ignorado'))               AS sexo_nao_informado,
       SUM(p.idade IS NULL)                                       AS idade_ausente,
       ROUND(100 * AVG(p.idade IS NULL), 1)                       AS pct_idade_ausente
  FROM pessoa p
 INNER JOIN acidente         a ON a.id = p.id_acidente
  LEFT JOIN uop              u ON u.id = a.id_uop
  LEFT JOIN delegacia        d ON d.id = COALESCE(u.id_delegacia, a.id_delegacia)
  LEFT JOIN superintendencia s ON s.id = COALESCE(d.id_superintendencia, a.id_superintendencia)
 WHERE a.data BETWEEN @data_ini AND @data_fim
 GROUP BY superintendencia
 ORDER BY pct_estado_nao_informado DESC;

-- @Q20 | Busca de acidentes pelo estado físico das vítimas (@estado)
-- Objetivo: localizar os acidentes com mais pessoas num estado físico —
-- ilesos, feridos, óbitos ou "Não Informado" — no período.
-- Técnicas: tabela derivada com GROUP BY + HAVING (lê só o índice de cobertura
-- idx_pessoa_acidente_estado), INNER JOIN, filtro temporal, ORDER BY + LIMIT.
SELECT a.id,
       a.data,
       c.uf,
       c.nome                    AS municipio,
       a.classificacao,
       x.no_estado               AS pessoas_no_estado,
       x.pessoas                 AS pessoas_no_acidente
  FROM (SELECT id_acidente,
               SUM(estado_fisico = @estado) AS no_estado,
               COUNT(*)                     AS pessoas
          FROM pessoa
         GROUP BY id_acidente
        HAVING no_estado > 0) x
 INNER JOIN acidente a ON a.id = x.id_acidente
 INNER JOIN cidade   c ON c.id = a.id_cidade
 WHERE a.data BETWEEN @data_ini AND @data_fim
 ORDER BY x.no_estado DESC, a.data DESC
 LIMIT 50;
