# Memorial de normalização — da planilha (0FN) à 3FN

> Time Índice — Grupo 4 · Cenário USUPORT. Todos os exemplos são linhas reais do arquivo `acidentes2024_todas_causas_tipos_Usuport.csv`.

## 0FN — a planilha original

A planilha é uma única tabela com 37 colunas e 603.215 linhas. **Cada linha é uma combinação acidente × pessoa × causa × tipo.** Os dados do acidente se repetem em todas as combinações, e o traçado da via vem numa só célula, com vários valores separados por `;`.

Colunas: `id, pesid, data_inversa, dia_semana, horario, uf, br, km, municipio, causa_principal, causa_acidente, ordem_tipo_acidente, tipo_acidente, classificacao_acidente, fase_dia, sentido_via, condicao_metereologica, tipo_pista, tracado_via, uso_solo, id_veiculo, tipo_veiculo, marca, ano_fabricacao_veiculo, tipo_envolvido, estado_fisico, idade, sexo, ilesos, feridos_leves, feridos_graves, mortos, latitude, longitude, regional, delegacia, uop`

### Exemplo 1 — acidente 571774: 1 pessoa × 2 causas = 2 linhas

| id | pesid | causa_principal | causa_acidente | tipo_acidente | tracado_via | id_veiculo | tipo_veiculo | estado_fisico |
|---|---|---|---|---|---|---|---|---|
| 571774 | 1268985 | Não | Animais na Pista | Colisão com objeto | Reta | 1018226 | Automóvel | Ileso |
| 571774 | 1268985 | **Sim** | Velocidade Incompatível | Colisão com objeto | Reta | 1018226 | Automóvel | Ileso |

A mesma pessoa, o mesmo veículo, a data, o local e o tipo aparecem duas vezes. A única informação nova na 2ª linha é a segunda causa.

### Exemplo 2 — acidente 571778: 2 pessoas × 2 causas = 4 linhas

| id | pesid | causa_principal | causa_acidente | tipo_acidente | tracado_via | id_veiculo | tipo_envolvido | estado_fisico | idade |
|---|---|---|---|---|---|---|---|---|---|
| 571778 | 1269028 | Não | Reação tardia ou ineficiente do condutor | Saída de leito carroçável | Curva | 1018261 | Condutor | Ileso | 53 |
| 571778 | 1269045 | Não | Reação tardia ou ineficiente do condutor | Saída de leito carroçável | Curva | 1018261 | Passageiro | Lesões Leves | 33 |
| 571778 | 1269028 | **Sim** | Acumulo de água sobre o pavimento | Saída de leito carroçável | Curva | 1018261 | Condutor | Ileso | 53 |
| 571778 | 1269045 | **Sim** | Acumulo de água sobre o pavimento | Saída de leito carroçável | Curva | 1018261 | Passageiro | Lesões Leves | 33 |

### Exemplo 3 — acidente 661235: tipos em sequência e traçado multivalorado

| id | pesid | ordem_tipo_acidente | tipo_acidente | tracado_via | id_veiculo | tipo_veiculo |
|---|---|---|---|---|---|---|
| 661235 | 1491055 | 2 | Saída de leito carroçável | Aclive;Curva | 1189616 | Caminhonete |
| 661235 | 1491054 | 2 | Saída de leito carroçável | Aclive;Curva | 1189615 | Caminhão |
| 661235 | 1491055 | 1 | Colisão traseira | Aclive;Curva | 1189616 | Caminhonete |
| 661235 | 1491054 | 1 | Colisão traseira | Aclive;Curva | 1189615 | Caminhão |

Primeiro houve uma colisão traseira e depois a saída da pista. A coluna `tracado_via` guarda **dois valores numa célula** ("Aclive;Curva").

### Exemplo 4 — acidente 571802: o mesmo tipo em ordens diferentes

| id | pesid | ordem_tipo_acidente | tipo_acidente | tipo_envolvido |
|---|---|---|---|---|
| 571802 | 1270945 | 2 | Colisão com objeto | Condutor |
| 571802 | 1269041 | 2 | Colisão com objeto | Passageiro |
| 571802 | 1270945 | 1 | Colisão com objeto | Condutor |
| 571802 | 1269041 | 1 | Colisão com objeto | Passageiro |

O veículo bateu em dois objetos em sequência. Por isso, o tipo **não** identifica o evento: quem identifica é a **ordem**. O mesmo acontece em 1.509 acidentes.

### Exemplo 5 — acidente 661121 (ônibus): 1.540 linhas

Acidente em Teófilo Otoni/MG, BR-116 km 286,5, em 21/12/2024 às 03:45, com **53 pessoas** (37 óbitos), **7 veículos**, **4 causas** e **7 tipos em sequência** (colisão lateral → derramamento de carga → colisão com objeto → queda de ocupante → incêndio → colisão traseira → colisão frontal). As linhas da planilha são 53 pessoas × 4 causas × 7 tipos = 1.484, mais 2 semirreboques sem ocupante × 4 × 7 = 56, **total 1.540**. Os dados do acidente (data, local, classificação, unidade da PRF...) foram escritos **1.540 vezes**.

### Anomalias que a 0FN provoca

| Anomalia | Exemplo concreto |
|---|---|
| **Atualização** | corrigir o km do acidente 661121 exige alterar 1.540 linhas; se alguma ficar para trás, o banco passa a ter dois km para o mesmo acidente |
| **Inserção** | não há como cadastrar uma nova causa no catálogo, ou uma UOP nova, sem inventar um acidente; um veículo sem ocupante precisa de linhas com pessoa "NA" |
| **Exclusão** | ao apagar as linhas do único acidente de uma UOP, perde-se a informação de que essa UOP pertence à DEL01-BA |
| **Redundância** | 603.215 linhas para 73.156 acidentes; `dia_semana` repete o que a data já diz; `mortos` repete o que `estado_fisico` já diz |

---

## 1FN — valores atômicos

**Regra:** cada célula contém um único valor indivisível e não há grupos repetitivos.

A única coluna que violava a atomicidade era **`tracado_via`** ("Reta;Declive", com até 8 valores e 12 valores distintos). Ela é quebrada em um valor por linha. A carga faz isso com `JSON_TABLE` (`sql/03_carga.sql`; há também a alternativa com CTE recursiva, comentada no script). Nenhuma célula tinha valor repetido, mas o `DISTINCT` ficou como proteção.

Tratamos também os valores que não eram atômicos no sentido de **tipo**:

- `km` "272,5" vira o número 272.5;
- latitude e longitude, que eram texto, viram `DECIMAL`;
- os textos `NA`/`N/A` viram `NULL`.

Também listamos os atributos **compostos** do conceito e os decompusemos em simples:

- **local** = (br, km, sentido, município, UF);
- **coordenadas** = (latitude, longitude).

Resultado — relação única **R1**, sem célula multivalorada:

> R1(**id, pesid, id_veiculo, causa_acidente, ordem_tipo_acidente, tracado**, data, dia_semana, horario, uf, br, km, municipio, causa_principal, tipo_acidente, classificacao, fase_dia, sentido, condicao, tipo_pista, uso_solo, tipo_veiculo, marca, ano_fabricacao, tipo_envolvido, estado_fisico, idade, sexo, ilesos, feridos_leves, feridos_graves, mortos, latitude, longitude, regional, delegacia, uop)

Os atributos em negrito formam a chave da linha. É uma chave composta enorme, porque cada linha é uma combinação. Ainda há muita redundância: a 1FN não resolve repetição, só atomicidade.

### Dependências funcionais (DF) levantadas e conferidas no CSV

| DF | Determinante → dependentes | Conferência no CSV |
|---|---|---|
| DF1 | `id` → data, dia_semana, horario, uf, br, km, municipio, classificacao, fase_dia, sentido, condicao, tipo_pista, uso_solo, latitude, longitude, uop, delegacia, regional | todos constantes dentro do mesmo id (0 exceções) |
| DF2 | `pesid` → id, id_veiculo, tipo_envolvido, estado_fisico, idade, sexo, ilesos, feridos_leves, feridos_graves, mortos | nenhuma pessoa varia atributo; nenhum pesid em dois acidentes |
| DF3 | `id_veiculo` → id, tipo_veiculo, marca, ano_fabricacao | nenhum veículo em dois acidentes |
| DF4 | (`id`, `causa_acidente`) → causa_principal | nenhum par com "Sim" e "Não" ao mesmo tempo |
| DF5 | (`id`, `ordem_tipo_acidente`) → tipo_acidente | nenhum (id, ordem) com dois tipos |
| DF6 | `uop` → delegacia; `delegacia` → regional | hierarquia estrita em 100% dos casos |
| DF7 | `data` → dia_semana | 100% coincidente com o calendário |
| DF8 | `estado_fisico` → ilesos, feridos_leves, feridos_graves, mortos | 100% coincidente (ex.: mortos = 1 ⇔ "Óbito") |
| DF9 | (`municipio`, `uf`) identificam o município | o nome sozinho **não** determina a UF (36 homônimos) |

---

## 2FN — sem dependências parciais

**Regra:** estar na 1FN, e todo atributo não-chave depender da chave **inteira**, não de parte dela.

Em R1 quase nada depende da chave inteira. Cada grupo de atributos depende de **uma parte** da chave, e cada parte vira uma relação:

| Parte da chave | Atributos que dependem só dela | Nova relação |
|---|---|---|
| `id` | DF1 | **ACIDENTE**(<u>id</u>, data, dia_semana, horario, uf, br, km, municipio, classificacao, fase_dia, sentido, condicao, tipo_pista, uso_solo, latitude, longitude, uop, delegacia, regional) |
| `pesid` | DF2 | **PESSOA**(<u>pesid</u>, id_acidente, id_veiculo, tipo_envolvido, estado_fisico, idade, sexo, ilesos, feridos_leves, feridos_graves, mortos) |
| `id_veiculo` | DF3 | **VEICULO**(<u>id</u>, id_acidente, tipo_veiculo, marca, ano_fabricacao) |
| (`id`, `causa`) | DF4 | **CAUSA_ACIDENTE**(<u>id_acidente, causa</u>, principal) |
| (`id`, `ordem`) | DF5 | **ACIDENTE_TIPO**(<u>id_acidente, ordem</u>, tipo) |
| (`id`, `tracado`) | — (só chave) | **ACIDENTE_TRACADO**(<u>id_acidente, tracado</u>) |

A chave composta de R1 não determina mais nada sozinha. A planilha era apenas o **produto** dessas listas independentes (pessoas × causas × tipos × traçados de um mesmo acidente). Por isso, depois da decomposição, a relação R1 pode ser **descartada**: ela é reconstruída por JOIN, e é exatamente isso que a `vw_acidente_detalhe` faz. Em termos formais, eliminar esse produto de listas independentes também atende à 4FN (dependências multivaloradas id ↠ causas, id ↠ tipos, id ↠ traçados, id ↠ pessoas).

Efeito nos exemplos:

| Acidente | Linhas na planilha | Linhas no banco (por tabela) |
|---|---|---|
| 571774 | 2 | acidente 1 · pessoa 1 · veículo 1 · causa_acidente 2 · acidente_tipo 1 · acidente_tracado 1 |
| 571778 | 4 | acidente 1 · pessoa 2 · veículo 1 · causa_acidente 2 · acidente_tipo 1 · acidente_tracado 1 |
| 661235 | 4 | acidente 1 · pessoa 2 · veículo 2 · causa_acidente 1 · acidente_tipo 2 · acidente_tracado 2 |
| 571802 | 4 | acidente 1 · pessoa 2 · veículo 1 · causa_acidente 1 · acidente_tipo **2** (ordem 1 e 2, mesmo tipo) · acidente_tracado 1 |
| 661121 | **1.540** | acidente 1 · pessoa 53 · veículo 7 · causa_acidente 4 · acidente_tipo 7 · acidente_tracado 2 = **74** |

No banco inteiro: 603.215 linhas viram 73.156 acidentes + 179.114 pessoas + 139.617 veículos + 111.307 causas de acidente + 124.173 tipos + 93.850 traçados. Agora **cada fato é gravado uma única vez**.

---

## 3FN — sem dependências transitivas

**Regra:** estar na 2FN, e nenhum atributo não-chave depender de outro atributo não-chave.

| Relação | Dependência transitiva encontrada | Solução |
|---|---|---|
| ACIDENTE | `id` → `uop` → `delegacia` → `regional` (DF6) | **UOP**(<u>id</u>, sigla, id_delegacia), **DELEGACIA**(<u>id</u>, sigla, id_superintendencia), **SUPERINTENDENCIA**(<u>id</u>, sigla). O acidente guarda só a FK da unidade |
| ACIDENTE | `id` → `data` → `dia_semana` (DF7) | `dia_semana` **removido**: é calculado com `DAYNAME(data)` ou `ELT(DAYOFWEEK(data), …)` |
| PESSOA | `pesid` → `estado_fisico` → `mortos`, `ilesos`, `feridos_*` (DF8) | contadores **removidos**: são somados com `SUM(estado_fisico = 'Óbito')` etc. e expostos em `vw_acidente_totais` |

### O caso da unidade da PRF ausente — arco exclusivo

Ao mover a hierarquia para tabelas próprias, o acidente deveria apontar só para a UOP. Mas no CSV:

- 76 acidentes têm delegacia e não têm UOP;
- 33 têm superintendência e não têm delegacia;
- 3 não têm nenhuma das três.

Apontar só para a UOP **perderia** a unidade desses 109 acidentes. Gravar as três siglas recriaria a dependência transitiva. A solução foi um **arco exclusivo**: `acidente` tem `id_uop`, `id_delegacia` e `id_superintendencia`, e o CHECK `ck_acidente_unidade_unica` garante que **no máximo uma** esteja preenchida, sempre a mais específica conhecida. Assim nunca há duas unidades no mesmo registro (não existe dependência transitiva) e nenhuma informação se perde.

### Cidade

Usamos o mesmo critério da hierarquia da PRF ("traz informação junto"): a **UF é um fato sobre o município**, não sobre o acidente. Daí a tabela **CIDADE**(<u>id</u>, nome, uf). Um cuidado técnico: como o nome do município sozinho **não** determina a UF (36 homônimos, ex.: BOM JESUS em PB, PI, RN e RS), a dependência só aparece quando o município é tratado como entidade, com chave natural **(nome, uf)** (UNIQUE `uq_cidade_nome_uf`). Separar a cidade elimina a repetição do par em 73 mil acidentes. Também prepara o modelo para atributos do próprio município (por exemplo, o código IBGE) sem anomalias de atualização.

### Catálogos (padronização, não exigência da 3FN)

Causa, tipo de acidente, traçado, tipo de veículo, condição meteorológica e fase do dia viraram tabelas **por decisão de padronização** (critério b, abaixo). A grafia fica num único lugar: a demonstração está em `05_dml_exemplos.sql` §2.4, em que corrigir "Semireboque" para "Semirreboque" foi **uma** linha alterada no catálogo, em vez de 50.449 células na planilha. Isso também permite incluir novos valores sem criar acidentes.

### Critério do grupo: catálogo (tabela) × CHECK (coluna)

Uma lista de valores vira **tabela nova** quando:

- **(a)** traz informação junto (cidade → UF; UOP → delegacia → superintendência). Nesses casos a separação vem da normalização;
- **(b)** a lista é grande ou pode mudar (70 causas, 17 tipos, 12 traçados, 25 tipos de veículo, 10 condições, 4 fases do dia). Aqui a separação é uma escolha de padronização.

Listas **pequenas e fixas** viram coluna com **CHECK**:

- sexo (4 valores);
- sentido (3);
- tipo de pista (3);
- uso do solo (2);
- estado físico (5);
- tipo de envolvido (5);
- classificação (3).

### Decisões conscientes registradas (para a arguição)

1. **`pessoa.id_acidente` junto com `pessoa.id_veiculo`.** Pedestres, testemunhas e cavaleiros (6.577 pessoas) não têm veículo, então precisam de `id_acidente`. Para quem está num veículo, o acidente também pode ser obtido pelo veículo (`pesid → id_veiculo → id_acidente`). O grupo manteve as duas colunas, para simplificar consultas e o app, e tratou isso como **redundância controlada**: a FK composta `(id_veiculo, id_acidente) → veiculo(id, id_acidente)` faz o próprio SGBD rejeitar qualquer pessoa num veículo de outro acidente (erro 1452). Assim, a anomalia de atualização que a 3FN quer evitar não pode acontecer. A alternativa pura seria um arco "veículo OU acidente" na pessoa.
2. **`acidente.classificacao` mantida.** É a classificação oficial registrada pela PRF no boletim. Ela coincide em 100% com a regra "óbito → fatal; ferido → feridas; senão → sem vítimas", calculada a partir das pessoas. Não há dependência transitiva *dentro* de `acidente` (a classificação depende do id), mas há um dado que poderia ser derivado de outra tabela. Por isso: o app calcula a classificação ao inserir, o UPDATE de óbito atualiza a classificação na mesma transação, e a consulta C-RN08 e a `vw_classificacao_conferencia` acusam qualquer divergência.
3. **`causa_acidente.marcador_principal`.** É uma coluna **gerada virtual** (não armazena dado) que só existe para sustentar a UNIQUE "uma causa principal por acidente". Ela não é um atributo do negócio.

---

## Esquema final (3FN) — 16 tabelas

| Tabela | Chave primária | Chaves estrangeiras | Linhas |
|---|---|---|---|
| superintendencia | id | — | 28 |
| delegacia | id | id_superintendencia → superintendencia | 152 |
| uop | id | id_delegacia → delegacia | 394 |
| cidade | id (natural: nome + uf) | — | 1.873 |
| condicao_meteorologica | id | — | 10 |
| fase_dia | id | — | 4 |
| causa | id | — | 70 |
| tipo_acidente | id | — | 17 |
| tracado | id | — | 12 |
| tipo_veiculo | id | — | 25 |
| acidente | id (da PRF) | id_cidade, id_condicao, id_fase_dia, id_uop / id_delegacia / id_superintendencia (arco) | 73.156 |
| causa_acidente | (id_acidente, id_causa) | id_acidente → acidente, id_causa → causa | 111.307 |
| acidente_tipo | (id_acidente, ordem) | id_acidente → acidente, id_tipo → tipo_acidente | 124.173 |
| acidente_tracado | (id_acidente, id_tracado) | id_acidente → acidente, id_tracado → tracado | 93.850 |
| veiculo | id (da PRF) | id_acidente → acidente, id_tipo_veiculo → tipo_veiculo | 139.617 |
| pessoa | pesid (da PRF) | id_acidente → acidente, (id_veiculo, id_acidente) → veiculo | 179.114 |

Verificação final, tabela a tabela: todo atributo não-chave depende **da chave** (1FN), **da chave inteira** (2FN, o que importa nas 3 associativas de chave composta) e **de nada além da chave** (3FN). As exceções são as decisões conscientes acima, cada uma com uma restrição do banco que impede inconsistência.
