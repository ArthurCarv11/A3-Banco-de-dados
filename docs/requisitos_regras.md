# Levantamento de requisitos e regras de negócio

> Time Índice — Grupo 4 · Cenário USUPORT · UC Projeto Integrador de Banco de Dados (A3)

## 1. Contexto de aplicabilidade

**Sistema de gestão e análise de sinistros em rodovias federais.** A base entregue pelo professor para o cenário USUPORT é a planilha de sinistros da Polícia Rodoviária Federal (PRF) de 2024, que tem 603.215 linhas e 37 colunas. Cada linha combina **acidente × pessoa × causa × tipo**. Por isso, os 73.156 acidentes reais aparecem repetidos em média 8 vezes, e um único acidente com ônibus (id 661121) ocupa 1.540 linhas.

O sistema substitui essa planilha desnormalizada por um banco relacional íntegro, consultável e auditável. Os usuários previstos são:

| Perfil | O que faz no sistema |
|---|---|
| Analista de segurança viária | consulta e cruza dados (causas, trechos críticos, horários, perfil das vítimas) para orientar fiscalização e campanhas |
| Gestor da PRF (UOP / delegacia / superintendência) | acompanha volume e gravidade dos acidentes da sua unidade |
| Operador de registro | cadastra um acidente completo (causas, sequência de eventos, veículos e pessoas) e corrige ou exclui registros |
| Administrador de dados | carrega novas bases, valida a carga e mantém a integridade |

> Significado da sigla USUPORT: **[significado de USUPORT — confirmar com o professor]**. Neste trabalho o nome é usado exatamente como consta na planilha oficial de cenários.

## 2. Requisitos funcionais

| Código | Requisito | Onde está atendido |
|---|---|---|
| RF01 | Carregar a planilha da PRF no banco normalizado, aplicando regras de limpeza documentadas | `sql/02_staging.sql`, `sql/03_carga.sql` |
| RF02 | Validar a carga: contagens esperadas, regras de limpeza e regras de negócio | `sql/04_validacao.sql` |
| RF03 | Consultar acidentes por período, UF, município, BR, causa (opcionalmente só a principal), tipo de acidente, classificação e id | app → Consulta / Acidentes |
| RF04 | Exibir a ficha completa de um acidente: dados gerais, causas (com a principal), sequência de tipos, traçados, veículos e pessoas | app → Consulta (clique na linha) |
| RF05 | Consultar pessoas (papel, estado físico, sexo, idade), veículos (tipo, marca, ano, ocupantes) e causas (principal × secundária) | app → Consulta / abas |
| RF06 | Cadastrar um acidente completo numa única transação | app → Inserção |
| RF07 | Excluir um acidente e todos os seus dependentes numa transação, com pré-visualização e confirmação | app → Exclusão |
| RF08 | Exibir indicadores e consultas gerenciais (18 consultas) com tabela e gráfico | app → Painel gerencial · `sql/06_dql_consultas.sql` |
| RF09 | Mostrar, em toda tela, o SQL executado e seus parâmetros | expander "SQL executado" |
| RF10 | Inspecionar o esquema físico por ferramenta administrativa conectada à VM | DBeaver/Workbench (`docs/infra_vm.md`) |

## 3. Requisitos não funcionais

| Código | Requisito | Como foi atendido |
|---|---|---|
| RNF01 | O SGBD roda em máquina virtual Oracle VirtualBox (Ubuntu + MySQL 8) e é acessado pela rede | `docs/infra_vm.md`: bind-address, porta 3306, bridge ou NAT com redirecionamento de porta |
| RNF02 | O esquema segue rigorosamente a 3FN | `docs/memorial_normalizacao.md` |
| RNF03 | A integridade é declarativa, garantida pelo próprio SGBD | 16 PK, 18 FK, 21 CHECK, UNIQUE, NOT NULL (`docs/dicionario_dados.md`) |
| RNF04 | Todo SQL é explícito e parametrizado, sem ORM | `app/db.py`, que usa marcadores `%s` do mysql-connector-python |
| RNF05 | Não há credenciais no código e o usuário da aplicação tem privilégio mínimo | `.env` (modelo em `.env.example`); `usuport_app` só tem SELECT/INSERT/UPDATE/DELETE, sem DDL |
| RNF06 | Escritas atômicas | inserção e exclusão em `START TRANSACTION … COMMIT/ROLLBACK` |
| RNF07 | Bom desempenho | índices em data, BR/km, FKs e descrições; consultas do app medidas entre 0,01 s e 1,2 s sobre 73 mil acidentes |
| RNF08 | Acentuação preservada e busca tolerante | `utf8mb4` + colação `utf8mb4_0900_ai_ci` ("sao paulo" encontra "SÃO PAULO") |
| RNF09 | Reprodutibilidade | `sql/00_completo.sql` recria e recarrega o banco do zero em cerca de 1 minuto |
| RNF10 | Rastreabilidade | os ids originais da PRF são preservados; registros criados pelo sistema usam a faixa ≥ 9.000.001 |

## 4. Regras de negócio

Todas as regras abaixo foram **extraídas dos próprios dados** pelo perfilamento do CSV e conferidas no banco carregado (`sql/04_validacao.sql`). A coluna "Garantia" indica o mecanismo do banco que impede a violação da regra.

| Código | Regra | Evidência no CSV | Garantia |
|---|---|---|---|
| RN01 | Todo acidente tem **exatamente uma** causa principal | 73.156 de 73.156 acidentes | UNIQUE sobre coluna gerada (`uq_causa_acidente_uma_principal`) impede duas; a transação do app e a validação C-RN01 garantem pelo menos uma |
| RN02 | Um acidente pode ter **várias causas** (de 1 a 16) | 23.327 acidentes com mais de uma causa | tabela associativa `causa_acidente`, PK (id_acidente, id_causa) |
| RN03 | Os tipos formam uma **sequência ordenada**, e o mesmo tipo pode se repetir em ordens diferentes | 1.509 acidentes repetem um tipo (ex.: 571802) | `acidente_tipo` com PK (id_acidente, **ordem**) |
| RN04 | O **traçado da via** é multivalorado e sem ordem (até 8 valores) | 18.458 acidentes com mais de um valor na célula | `acidente_tracado`, PK (id_acidente, id_tracado) |
| RN05 | Cada veículo pertence a **um único acidente**: não é cadastro de frota, pois não há placa | 139.617 veículos, nenhum em dois acidentes | FK `veiculo.id_acidente` NOT NULL |
| RN06 | Condutor e Passageiro **sempre** ocupam um veículo; Pedestre, Testemunha e Cavaleiro **nunca** | 172.537 com veículo × 6.577 sem | CHECK `ck_pessoa_envolvido_veiculo` |
| RN07 | Uma pessoa só pode ocupar veículo **do mesmo acidente** | 0 casos divergentes | FK composta `(id_veiculo, id_acidente)` → `veiculo(id, id_acidente)` |
| RN08 | A classificação do acidente acompanha o estado físico mais grave das pessoas | 73.155 de 73.155 coincidem; 1 acidente sem classificação | o app calcula a classificação ao inserir; consulta de consistência C-RN08 e `vw_classificacao_conferencia` |
| RN09 | A hierarquia UOP → delegacia → superintendência é **estrita** | 100% das combinações | FKs `uop.id_delegacia` e `delegacia.id_superintendencia` NOT NULL |
| RN10 | O acidente registra a **unidade mais específica conhecida** (arco exclusivo) | 73.044 com UOP, 76 só com delegacia, 33 só com superintendência, 3 sem unidade | CHECK `ck_acidente_unidade_unica` (no máximo uma das três FKs) |
| RN11 | A superintendência que atende **não precisa** ser da UF do acidente | 1.289 casos (ex.: GO atendido pela SPRF-DF) + 2 pela UniPRF | não há restrição ligando UF e superintendência (é um fato, não um erro) |
| RN12 | O município é identificado por **nome + UF** | 36 nomes repetidos em UFs diferentes (ex.: BOM JESUS em PB, PI, RN e RS) | UNIQUE `(nome, uf)` em `cidade` |
| RN13 | Só existe km se existir BR | 186 acidentes sem BR, todos também sem km e com sentido "Não Informado" | CHECK `ck_acidente_km_br` |
| RN14 | Dia da semana e totais de vítimas são **derivados** e por isso não são armazenados | dia_semana confere 100% com a data; os contadores conferem 100% com estado_fisico | calculados em consulta (`DAYNAME`, `ELT(DAYOFWEEK())`, `SUM(estado_fisico = 'Óbito')`) e nas views |
| RN15 | Valores com faixa válida: idade 0–110, ano 1900–2100, BR 1–499, km ≥ 0, coordenadas no território brasileiro, data ≥ 2007 | 282 idades > 110 (até 2023) tratadas como NULL | CHECKs `ck_pessoa_idade`, `ck_veiculo_ano`, `ck_acidente_*` |
| RN16 | Domínios fixos: sexo (4 valores), estado físico (5), tipo de envolvido (5), sentido (3), tipo de pista (3), uso do solo (2), classificação (3) | levantados do CSV | CHECK com a lista de valores |
| RN17 | Um veículo pode não ter pessoa registrada | 17.192 veículos, sobretudo semirreboques (15.138) e reboques (1.577), que não têm ocupante | `pessoa.id_veiculo` é opcional e veículo não exige pessoa |
| RN18 | Excluir um acidente exclui todos os seus dependentes, de forma atômica; registros originais da PRF exigem confirmação extra | — | FKs RESTRICT + exclusão explícita filho → pai numa transação (`app/db.py`, `05_dml_exemplos.sql`) |
| RN19 | Registros criados pelo sistema ficam numa faixa própria de ids | ids da PRF < 2 milhões | `ALTER TABLE … AUTO_INCREMENT = 9000001` |

## 5. Dados inconsistentes encontrados e tratamento

| Problema no CSV | Registros afetados | Tratamento |
|---|---|---|
| id do acidente em notação científica (`6e+05`) | 3 linhas (acidente 600000) | convertido para 600000 (R0) |
| `NA` / `N/A` como texto | br/km: 186 acidentes; classificação: 1; idade: 17.140 pessoas; uop: 112 acidentes; delegacia: 36; regional: 3 | NULL (R1) |
| km com vírgula decimal (`272,5`) | 27.170 acidentes | `DECIMAL(6,1)` (R2) |
| idade impossível (> 110, até 2023) | 282 pessoas | NULL (R6) |
| ano de fabricação = 0 | 10.122 veículos | NULL (R7) |
| marca "Não Informado/Não Informado" | 8.070 veículos | NULL (R8) |
| linha sem pessoa (pesid NA) | 57.641 linhas → 17.192 veículos | gera o veículo, mas não gera pessoa (R9) |
| acidente 589272 com 16 causas | 1 acidente | mantido; provável erro de preenchimento, citado no relatório |
| acidente 639340 com ordens 1, 2, 4, 5 (sem a 3) | 1 acidente | mantido como veio; a ordem não precisa ser contígua |
| 13 veículos com ano 1900 | 13 | mantidos (valor válido, porém suspeito) |
