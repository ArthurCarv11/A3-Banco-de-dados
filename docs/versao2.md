# Versão 2 — evolução do modelo em 5 partes

> Time Índice — Grupo 4 · Cenário USUPORT. Documento de projeto da versão 2. O trabalho foi dividido por **tema técnico**: a base (Arthur) prepara o terreno, e cada integrante ficou responsável por uma parte, da implementação à explicação na banca.

## 1. Objetivo

A versão 1 já está correta e validada: 16 tabelas em 3FN, carga com 0 divergências e app funcionando. A versão 2 melhora três coisas, sem quebrar nada:

1. **Coerência do critério tabela × CHECK.** As listas pequenas e fixas que ainda eram tabela passam a ser coluna com CHECK.
2. **Desempenho** das consultas que contam vítimas: ilesos, óbitos e "não informado".
3. **Regras dentro do banco.** A exclusão completa vira procedure, e a reclassificação do acidente vira trigger. O SGBD passa a garantir sozinho regras que antes dependiam do app.

## 2. As partes

| Ordem | Parte | Responsável | O que muda | Por que |
|---|---|---|---|---|
| 0 | Base | Arthur | este documento; `00_completo` aceita o `08_rotinas.sql`; exemplo de UPDATE de catálogo (Semirreboque); `GRANT EXECUTE` e avisos na VM | prepara as partes sem mudar o comportamento |
| 1 | Fase do dia e condição meteorológica → CHECK | Alisson | as tabelas `fase_dia` e `condicao_meteorologica` deixam de existir; viram colunas de `acidente` com CHECK | listas pequenas (4 e 10 valores), textos curtos, quase nunca mudam: o CHECK dispensa 2 JOINs |
| 2 | Traçado → CHECK | Guilherme | o catálogo `tracado` deixa de existir; `acidente_tracado` guarda o texto com CHECK. **A associativa continua:** ela resolve o atributo multivalorado (1FN) | lista pequena (12 valores) e fixa: −1 tabela, −1 JOIN |
| 3 | Índice de cobertura + consultas de estado físico | Filipe | índice `pessoa(id_acidente, estado_fisico)`; Q19 (qualidade do registro: "não informado"); Q20 (busca por estado físico: ilesos, óbitos, não informado) | as contagens por acidente passam a ler só o índice |
| 4 | Procedure de exclusão | Cláudio | `sp_excluir_acidente` em `sql/08_rotinas.sql`; o app só faz `CALL` | a regra "filhos antes do pai, numa transação" fica num lugar só: o banco |
| 5 | Trigger de classificação | Miguel | triggers em `pessoa` recalculam `acidente.classificacao` quando o estado físico muda | a regra RN08 passa a ser garantida pelo banco, não mais pelo app |

O que **continua tabela** e por quê: causa (70 valores), tipo de acidente (17) e tipo de veículo (25). São listas longas, com textos de até 77 caracteres, e a PRF as revisa. Com tabela, corrigir um nome é 1 linha (veja o "Semirreboque" no `05_dml_exemplos.sql` §2.4). Com CHECK seriam milhares de linhas e um `ALTER TABLE`.

**Por que não `ENUM`?** O `ENUM` do MySQL guardaria 1 byte por linha, mas não é SQL padrão, ordena pela posição interna e não pelo texto, e o edital pede CHECK. Para listas de até 12 valores curtos, o espaço do texto é desprezível.

## 3. Por que esta ordem

- **Esquema primeiro (1 e 2), rotinas por último (4 e 5).** A procedure e a trigger citam nomes de tabelas; criadas antes, teriam que ser reescritas.
- **O índice (3) vem depois das mudanças de esquema** para ser medido sobre a estrutura final.
- **Cada commit deixa o sistema inteiro funcionando.** Cada parte altera todas as camadas que toca (DDL, carga, validação, consultas, views, app e documentação). Nunca existe um commit com o banco "pela metade".

## 4. Riscos conhecidos e como foram tratados

| Risco | Tratamento |
|---|---|
| Apagar uma tabela quebra views, consultas e o app que a usam | varredura por nome em todos os arquivos + reconstrução do banco do zero ao fim de cada parte |
| A colação `utf8mb4_0900_ai_ci` faz o CHECK aceitar "pleno dia" e "Pleno Dia" | a carga grava sempre a grafia padronizada (regra R12) |
| Ao criar o índice `(id_acidente, estado_fisico)`, o MySQL apaga **em silêncio** o índice implícito da FK `id_acidente` | é o comportamento esperado (evita índice duplicado), mas o índice novo passa a sustentar a FK: removê-lo dá erro 1553 |
| `CREATE TRIGGER` com log binário ligado exige SUPER | o `08_rotinas.sql` roda como root na VM, nunca pelo `usuport_admin` |
| Erro 1442: uma trigger não pode alterar uma tabela que o próprio comando está usando | a trigger fica em `pessoa` e só altera `acidente`; não existe trigger em `acidente` |
| A trigger disparar durante a carga (179 mil vezes) | ela só é criada no `08`, depois da carga |
| Procedure com transação própria chamada dentro de outra transação (commit implícito) | o app chama só `CALL`, sem abrir transação por fora |
| O app sem permissão para `CALL` | `GRANT … EXECUTE` ao `usuport_app`; a procedure usa `SQL SECURITY INVOKER` (menor privilégio) |
| `DELIMITER` só existe no cliente `mysql` | o `08_rotinas.sql` é executado pelo cliente `mysql` (como todos os scripts) |

## 5. Protocolo de teste de cada parte

Antes do commit, quem entrega a parte confirma:

1. **Reconstrução do zero:** `DROP DATABASE usuport;` e depois `00_completo.sql` como root, sem nenhuma linha `ERROR` e sem nenhuma `DIVERGENTE` na validação.
2. **Consultas:** as 18+ consultas do `06_dql_consultas.sql` rodam sem erro.
3. **App:** Consulta (ficha do 661121), Inserção, Exclusão e Painel abrem sem erro, e uma inserção seguida de exclusão funciona.
4. **Medição:** o tempo das consultas antes e depois, registrado na tabela abaixo.

## 6. Resultados medidos

Mediana de 5 execuções, em milissegundos, com MySQL 8.0.46 no Docker e base de 2024 completa. Cada parte preenche a sua linha.

| Versão | Q02 causas | Q03 veículo | Q04 fase × condição | Q06 traçado | Q10 urbano × rural | Q16 ficha | painel (indicadores) | aba Veículos |
|---|---|---|---|---|---|---|---|---|
| v1 (base) | 307 | 485 | 265 | 343 | 255 | 6,5 | 268 | 1.191 |
