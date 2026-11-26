# Dicionário de dados — banco `usuport`

> Time Índice — Grupo 4 · Cenário USUPORT. Gerado automaticamente por `scripts/gerar_dicionario.py` a partir do `INFORMATION_SCHEMA` do MySQL; as finalidades são os `COMMENT` definidos no `sql/01_ddl.sql`.

Legenda da coluna **Chave**: PK = chave primária · FK = chave estrangeira · UQ = participa de restrição UNIQUE · IX = indexada. **Nulo**: NÃO = `NOT NULL`.

## Visão geral

| # | Tabela | Finalidade |
|---|---|---|
| 1 | `superintendencia` | Superintendências regionais da PRF (topo da hierarquia administrativa) |
| 2 | `delegacia` | Delegacias da PRF; cada uma pertence a exatamente uma superintendência |
| 3 | `uop` | Unidades Operacionais (postos) da PRF; cada uma pertence a uma delegacia |
| 4 | `cidade` | Municípios onde ocorreram acidentes; chave natural (nome, uf) |
| 5 | `condicao_meteorologica` | Catálogo de condições meteorológicas (10 valores no CSV de 2024) |
| 6 | `fase_dia` | Catálogo de fases do dia |
| 7 | `causa` | Catálogo de causas de acidente (70 valores no CSV de 2024) |
| 8 | `tipo_acidente` | Catálogo de tipos de acidente (17 valores no CSV de 2024) |
| 9 | `tracado` | Catálogo de traçados de via (12 valores, extraídos da célula multivalorada) |
| 10 | `tipo_veiculo` | Catálogo de tipos de veículo (25 valores no CSV de 2024) |
| 11 | `acidente` | Acidente (sinistro) em rodovia federal registrado pela PRF |
| 12 | `causa_acidente` | Associação N:N entre acidente e causa, com a marcação da causa principal |
| 13 | `acidente_tipo` | Sequência ordenada de tipos de evento de cada acidente |
| 14 | `acidente_tracado` | Associação N:N entre acidente e traçado da via |
| 15 | `veiculo` | Veículo envolvido em um acidente (um registro por veículo por acidente) |
| 16 | `pessoa` | Pessoa envolvida em um acidente (condutor, passageiro, pedestre, testemunha ou cavaleiro) |

## 1. `superintendencia`

**Finalidade:** Superintendências regionais da PRF (topo da hierarquia administrativa)

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id` | smallint unsigned | NÃO | PK | auto_increment | Chave substituta (surrogate) da superintendência |
| `sigla` | varchar(10) | NÃO | UQ |  | Sigla da superintendência regional da PRF (ex.: SPRF-BA) ou UniPRF |

**Índices**

- `PRIMARY` (PRIMARY KEY): id
- `uq_superintendencia_sigla` (UNIQUE): sigla

## 2. `delegacia`

**Finalidade:** Delegacias da PRF; cada uma pertence a exatamente uma superintendência

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id` | smallint unsigned | NÃO | PK | auto_increment | Chave substituta da delegacia |
| `sigla` | varchar(12) | NÃO | UQ |  | Sigla da delegacia (ex.: DEL01-BA) |
| `id_superintendencia` | smallint unsigned | NÃO | FK |  | FK: superintendência à qual a delegacia está subordinada |

**Chaves estrangeiras**

- `fk_delegacia_superintendencia`: (id_superintendencia) → `superintendencia` (id), ON DELETE NO ACTION

**Índices**

- `fk_delegacia_superintendencia` (índice): id_superintendencia
- `PRIMARY` (PRIMARY KEY): id
- `uq_delegacia_sigla` (UNIQUE): sigla

## 3. `uop`

**Finalidade:** Unidades Operacionais (postos) da PRF; cada uma pertence a uma delegacia

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id` | smallint unsigned | NÃO | PK | auto_increment | Chave substituta da UOP |
| `sigla` | varchar(20) | NÃO | UQ |  | Sigla da Unidade Operacional (ex.: UOP01-DEL01-BA) |
| `id_delegacia` | smallint unsigned | NÃO | FK |  | FK: delegacia à qual a UOP está subordinada |

**Chaves estrangeiras**

- `fk_uop_delegacia`: (id_delegacia) → `delegacia` (id), ON DELETE NO ACTION

**Índices**

- `fk_uop_delegacia` (índice): id_delegacia
- `PRIMARY` (PRIMARY KEY): id
- `uq_uop_sigla` (UNIQUE): sigla

## 4. `cidade`

**Finalidade:** Municípios onde ocorreram acidentes; chave natural (nome, uf)

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id` | smallint unsigned | NÃO | PK | auto_increment | Chave substituta da cidade |
| `nome` | varchar(60) | NÃO | IX |  | Nome do município como registrado pela PRF (maiúsculas, sem acento) |
| `uf` | char(2) | NÃO | IX |  | Sigla da unidade da federação do município |

**Restrições CHECK**

- `ck_cidade_uf`: `(uf in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'))`

**Índices**

- `idx_cidade_uf` (índice): uf
- `PRIMARY` (PRIMARY KEY): id
- `uq_cidade_nome_uf` (UNIQUE): nome,uf

## 5. `condicao_meteorologica`

**Finalidade:** Catálogo de condições meteorológicas (10 valores no CSV de 2024)

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id` | tinyint unsigned | NÃO | PK | auto_increment | Chave substituta da condição meteorológica |
| `descricao` | varchar(30) | NÃO | UQ |  | Condição do tempo no momento do acidente (ex.: Céu Claro, Chuva, Ignorado) |

**Índices**

- `PRIMARY` (PRIMARY KEY): id
- `uq_condicao_meteorologica_descricao` (UNIQUE): descricao

## 6. `fase_dia`

**Finalidade:** Catálogo de fases do dia

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id` | tinyint unsigned | NÃO | PK | auto_increment | Chave substituta da fase do dia |
| `descricao` | varchar(20) | NÃO | UQ |  | Fase do dia (Amanhecer, Pleno dia, Anoitecer, Plena Noite) |

**Índices**

- `PRIMARY` (PRIMARY KEY): id
- `uq_fase_dia_descricao` (UNIQUE): descricao

## 7. `causa`

**Finalidade:** Catálogo de causas de acidente (70 valores no CSV de 2024)

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id` | smallint unsigned | NÃO | PK | auto_increment | Chave substituta da causa |
| `descricao` | varchar(120) | NÃO | UQ |  | Descrição da causa apontada pela PRF (ex.: Velocidade Incompatível) |

**Índices**

- `PRIMARY` (PRIMARY KEY): id
- `uq_causa_descricao` (UNIQUE): descricao

## 8. `tipo_acidente`

**Finalidade:** Catálogo de tipos de acidente (17 valores no CSV de 2024)

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id` | tinyint unsigned | NÃO | PK | auto_increment | Chave substituta do tipo de acidente |
| `descricao` | varchar(50) | NÃO | UQ |  | Tipo do evento (ex.: Colisão traseira, Tombamento) |

**Índices**

- `PRIMARY` (PRIMARY KEY): id
- `uq_tipo_acidente_descricao` (UNIQUE): descricao

## 9. `tracado`

**Finalidade:** Catálogo de traçados de via (12 valores, extraídos da célula multivalorada)

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id` | tinyint unsigned | NÃO | PK | auto_increment | Chave substituta do traçado |
| `descricao` | varchar(30) | NÃO | UQ |  | Característica do traçado da via (ex.: Reta, Curva, Declive) |

**Índices**

- `PRIMARY` (PRIMARY KEY): id
- `uq_tracado_descricao` (UNIQUE): descricao

## 10. `tipo_veiculo`

**Finalidade:** Catálogo de tipos de veículo (25 valores no CSV de 2024)

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id` | tinyint unsigned | NÃO | PK | auto_increment | Chave substituta do tipo de veículo |
| `descricao` | varchar(30) | NÃO | UQ |  | Tipo do veículo (ex.: Automóvel, Motocicleta, Ônibus) |

**Índices**

- `PRIMARY` (PRIMARY KEY): id
- `uq_tipo_veiculo_descricao` (UNIQUE): descricao

## 11. `acidente`

**Finalidade:** Acidente (sinistro) em rodovia federal registrado pela PRF

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id` | int unsigned | NÃO | PK | auto_increment | Identificador do acidente atribuído pela PRF (coluna id do CSV) |
| `data` | date | NÃO | IX |  | Data do acidente (data_inversa no CSV); dia da semana é calculado a partir dela |
| `horario` | time | NÃO |  |  | Hora do acidente |
| `br` | smallint unsigned | SIM | IX |  | Número da rodovia federal (BR); NULL em 186 acidentes sem BR informada |
| `km` | decimal(6,1) | SIM |  |  | Quilômetro da BR (vírgula decimal convertida para ponto) |
| `sentido` | varchar(13) | NÃO |  |  | Sentido da via: Crescente, Decrescente ou Não Informado |
| `tipo_pista` | varchar(8) | NÃO |  |  | Tipo de pista: Simples, Dupla ou Múltipla |
| `uso_solo` | varchar(6) | NÃO |  |  | Urbano (uso_solo = Sim no CSV) ou Rural (uso_solo = Não) |
| `classificacao` | varchar(20) | SIM | IX |  | Classificação da PRF: Sem Vítimas, Com Vítimas Feridas ou Com Vítimas Fatais |
| `latitude` | decimal(12,10) | NÃO |  |  | Latitude em graus decimais (parte do atributo composto coordenadas) |
| `longitude` | decimal(13,10) | NÃO |  |  | Longitude em graus decimais (parte do atributo composto coordenadas) |
| `id_cidade` | smallint unsigned | NÃO | FK |  | FK: município onde ocorreu o acidente (e, por ele, a UF) |
| `id_condicao` | tinyint unsigned | NÃO | FK |  | FK: condição meteorológica no momento do acidente |
| `id_fase_dia` | tinyint unsigned | NÃO | FK |  | FK: fase do dia em que ocorreu o acidente |
| `id_uop` | smallint unsigned | SIM | FK |  | FK (arco): UOP responsável; preenchida quando a UOP é conhecida |
| `id_delegacia` | smallint unsigned | SIM | FK |  | FK (arco): delegacia responsável, só quando NÃO há UOP |
| `id_superintendencia` | smallint unsigned | SIM | FK |  | FK (arco): superintendência responsável, só quando NÃO há UOP nem delegacia |

**Chaves estrangeiras**

- `fk_acidente_cidade`: (id_cidade) → `cidade` (id), ON DELETE NO ACTION
- `fk_acidente_condicao`: (id_condicao) → `condicao_meteorologica` (id), ON DELETE NO ACTION
- `fk_acidente_delegacia`: (id_delegacia) → `delegacia` (id), ON DELETE NO ACTION
- `fk_acidente_fase_dia`: (id_fase_dia) → `fase_dia` (id), ON DELETE NO ACTION
- `fk_acidente_superintendencia`: (id_superintendencia) → `superintendencia` (id), ON DELETE NO ACTION
- `fk_acidente_uop`: (id_uop) → `uop` (id), ON DELETE NO ACTION

**Restrições CHECK**

- `ck_acidente_br`: `((br is null) or (br between 1 and 499))`
- `ck_acidente_classificacao`: `((classificacao is null) or (classificacao in ('Sem Vítimas','Com Vítimas Feridas','Com Vítimas Fatais')))`
- `ck_acidente_data`: `(data >= '2007-01-01')`
- `ck_acidente_horario`: `(horario between '00:00:00' and '23:59:59')`
- `ck_acidente_km`: `((km is null) or (km >= 0))`
- `ck_acidente_km_br`: `((km is null) or (br is not null))`
- `ck_acidente_latitude`: `(latitude between -(34) and 6)`
- `ck_acidente_longitude`: `(longitude between -(74) and -(28))`
- `ck_acidente_sentido`: `(sentido in ('Crescente','Decrescente','Não Informado'))`
- `ck_acidente_tipo_pista`: `(tipo_pista in ('Simples','Dupla','Múltipla'))`
- `ck_acidente_unidade_unica`: `((((id_uop is not null) + (id_delegacia is not null)) + (id_superintendencia is not null)) <= 1)`
- `ck_acidente_uso_solo`: `(uso_solo in ('Urbano','Rural'))`

**Índices**

- `fk_acidente_cidade` (índice): id_cidade
- `fk_acidente_condicao` (índice): id_condicao
- `fk_acidente_delegacia` (índice): id_delegacia
- `fk_acidente_fase_dia` (índice): id_fase_dia
- `fk_acidente_superintendencia` (índice): id_superintendencia
- `fk_acidente_uop` (índice): id_uop
- `idx_acidente_br_km` (índice): br,km
- `idx_acidente_classificacao` (índice): classificacao
- `idx_acidente_data` (índice): data
- `PRIMARY` (PRIMARY KEY): id

## 12. `causa_acidente`

**Finalidade:** Associação N:N entre acidente e causa, com a marcação da causa principal

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id_acidente` | int unsigned | NÃO | PK FK |  | FK: acidente |
| `id_causa` | smallint unsigned | NÃO | PK FK |  | FK: causa apontada para o acidente |
| `principal` | tinyint(1) | NÃO |  | padrão 0 | TRUE se for a causa principal do acidente (exatamente uma por acidente) |
| `marcador_principal` | int unsigned | SIM | UQ | gerada (virtual) | Coluna gerada: id_acidente se a causa for principal, senão NULL (apoia a UNIQUE) |

**Chaves estrangeiras**

- `fk_causa_acidente_acidente`: (id_acidente) → `acidente` (id), ON DELETE NO ACTION
- `fk_causa_acidente_causa`: (id_causa) → `causa` (id), ON DELETE NO ACTION

**Restrições CHECK**

- `ck_causa_acidente_principal`: `(principal in (0,1))`

**Índices**

- `fk_causa_acidente_causa` (índice): id_causa
- `PRIMARY` (PRIMARY KEY): id_acidente,id_causa
- `uq_causa_acidente_uma_principal` (UNIQUE): marcador_principal

## 13. `acidente_tipo`

**Finalidade:** Sequência ordenada de tipos de evento de cada acidente

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id_acidente` | int unsigned | NÃO | PK FK |  | FK: acidente |
| `ordem` | tinyint unsigned | NÃO | PK |  | Posição do evento na sequência do acidente (1 = primeiro evento) |
| `id_tipo` | tinyint unsigned | NÃO | FK |  | FK: tipo de acidente ocorrido nessa posição da sequência |

**Chaves estrangeiras**

- `fk_acidente_tipo_acidente`: (id_acidente) → `acidente` (id), ON DELETE NO ACTION
- `fk_acidente_tipo_tipo`: (id_tipo) → `tipo_acidente` (id), ON DELETE NO ACTION

**Restrições CHECK**

- `ck_acidente_tipo_ordem`: `(ordem between 1 and 50)`

**Índices**

- `fk_acidente_tipo_tipo` (índice): id_tipo
- `PRIMARY` (PRIMARY KEY): id_acidente,ordem

## 14. `acidente_tracado`

**Finalidade:** Associação N:N entre acidente e traçado da via

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id_acidente` | int unsigned | NÃO | PK FK |  | FK: acidente |
| `id_tracado` | tinyint unsigned | NÃO | PK FK |  | FK: característica de traçado presente no local |

**Chaves estrangeiras**

- `fk_acidente_tracado_acidente`: (id_acidente) → `acidente` (id), ON DELETE NO ACTION
- `fk_acidente_tracado_tracado`: (id_tracado) → `tracado` (id), ON DELETE NO ACTION

**Índices**

- `fk_acidente_tracado_tracado` (índice): id_tracado
- `PRIMARY` (PRIMARY KEY): id_acidente,id_tracado

## 15. `veiculo`

**Finalidade:** Veículo envolvido em um acidente (um registro por veículo por acidente)

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `id` | int unsigned | NÃO | PK | auto_increment | Identificador do veículo no acidente atribuído pela PRF (id_veiculo) |
| `id_acidente` | int unsigned | NÃO | FK |  | FK: acidente em que o veículo se envolveu |
| `id_tipo_veiculo` | tinyint unsigned | NÃO | FK |  | FK: tipo do veículo |
| `marca` | varchar(40) | SIM | IX |  | Marca/modelo informado (ex.: HONDA/CG 160 FAN); NULL quando não informado |
| `ano_fabricacao` | smallint unsigned | SIM |  |  | Ano de fabricação; NULL quando ausente (0 no CSV) |

**Chaves estrangeiras**

- `fk_veiculo_acidente`: (id_acidente) → `acidente` (id), ON DELETE NO ACTION
- `fk_veiculo_tipo_veiculo`: (id_tipo_veiculo) → `tipo_veiculo` (id), ON DELETE NO ACTION

**Restrições CHECK**

- `ck_veiculo_ano`: `((ano_fabricacao is null) or (ano_fabricacao between 1900 and 2100))`

**Índices**

- `fk_veiculo_acidente` (índice): id_acidente
- `fk_veiculo_tipo_veiculo` (índice): id_tipo_veiculo
- `idx_veiculo_marca` (índice): marca
- `PRIMARY` (PRIMARY KEY): id
- `uq_veiculo_id_acidente` (UNIQUE): id,id_acidente

## 16. `pessoa`

**Finalidade:** Pessoa envolvida em um acidente (condutor, passageiro, pedestre, testemunha ou cavaleiro)

| Campo | Tipo | Nulo | Chave | Padrão / extra | Finalidade |
|---|---|---|---|---|---|
| `pesid` | int unsigned | NÃO | PK | auto_increment | Identificador da pessoa no acidente atribuído pela PRF (pesid) |
| `id_acidente` | int unsigned | NÃO | FK |  | FK: acidente em que a pessoa se envolveu |
| `id_veiculo` | int unsigned | SIM | FK |  | FK: veículo ocupado pela pessoa; NULL para pedestre, testemunha e cavaleiro |
| `tipo_envolvido` | varchar(10) | NÃO |  |  | Papel no acidente: Condutor, Passageiro, Pedestre, Testemunha ou Cavaleiro |
| `estado_fisico` | varchar(15) | NÃO | IX |  | Ileso, Lesões Leves, Lesões Graves, Óbito ou Não Informado |
| `idade` | tinyint unsigned | SIM |  |  | Idade em anos; NULL quando ausente ou inválida (> 110 no CSV) |
| `sexo` | varchar(13) | NÃO |  |  | Masculino, Feminino, Não Informado ou Ignorado |

**Chaves estrangeiras**

- `fk_pessoa_acidente`: (id_acidente) → `acidente` (id), ON DELETE NO ACTION
- `fk_pessoa_veiculo_mesmo_acidente`: (id_veiculo,id_acidente) → `veiculo` (id,id_acidente), ON DELETE NO ACTION

**Restrições CHECK**

- `ck_pessoa_envolvido_veiculo`: `((tipo_envolvido in ('Condutor','Passageiro')) = (id_veiculo is not null))`
- `ck_pessoa_estado_fisico`: `(estado_fisico in ('Ileso','Lesões Leves','Lesões Graves','Óbito','Não Informado'))`
- `ck_pessoa_idade`: `((idade is null) or (idade between 0 and 110))`
- `ck_pessoa_sexo`: `(sexo in ('Masculino','Feminino','Não Informado','Ignorado'))`
- `ck_pessoa_tipo_envolvido`: `(tipo_envolvido in ('Condutor','Passageiro','Pedestre','Testemunha','Cavaleiro'))`

**Índices**

- `fk_pessoa_acidente` (índice): id_acidente
- `fk_pessoa_veiculo_mesmo_acidente` (índice): id_veiculo,id_acidente
- `idx_pessoa_estado_fisico` (índice): estado_fisico
- `PRIMARY` (PRIMARY KEY): pesid
