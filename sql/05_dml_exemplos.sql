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
