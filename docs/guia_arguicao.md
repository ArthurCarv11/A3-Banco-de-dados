# Guia de arguição — perguntas prováveis e respostas curtas

> Time Índice — Grupo 4 · Cenário USUPORT. Respostas curtas para falar em 30–60 s. Entre parênteses, onde mostrar no projeto.

## A. Cenário e regras de negócio

**1. Qual é o contexto de aplicabilidade?**
Um sistema de gestão e análise de sinistros em rodovias federais. Ele substitui a planilha da PRF (603 mil linhas, 73 mil acidentes) por um banco normalizado, com consulta, cadastro, exclusão e painel gerencial. (`docs/requisitos_regras.md` §1)

**2. De onde saíram as regras de negócio?**
Do perfilamento do próprio CSV. Por exemplo: 100% dos acidentes têm exatamente uma causa principal; 1.509 repetem um tipo; pedestres nunca têm veículo. Cada regra tem a evidência e a restrição que a garante. (`requisitos_regras.md` §4, `sql/04_validacao.sql` seção C)

**3. Por que a planilha tem 603 mil linhas se são 73 mil acidentes?**
Porque cada linha é uma combinação acidente × pessoa × causa × tipo. O ônibus 661121 tem 53 pessoas × 4 causas × 7 tipos = 1.484 linhas, mais 56 linhas de dois semirreboques sem ocupante: 1.540.

## B. Modelagem conceitual (DER)

**4. Quais são os atributos multivalorados e como foram resolvidos?**
São três: causas, tipos (em sequência) e traçado da via. Cada um virou uma tabela associativa: `causa_acidente`, `acidente_tipo` e `acidente_tracado`.

**5. E os compostos?**
**Local**, formado por BR, km, sentido, município e UF, e **coordenadas**, formado por latitude e longitude. No lógico viraram colunas simples, e o município foi para a tabela `cidade`.

**6. Quais atributos são derivados?**
O dia da semana (vem da data) e os totais de vítimas: ilesos, feridos e mortos (vêm do estado físico). No DER aparecem tracejados e **não são armazenados**.

**7. Qual a cardinalidade entre veículo e pessoa?**
Um veículo tem 0..N pessoas (há 17.192 veículos sem ninguém registrado, principalmente semirreboques). Uma pessoa está em 0..1 veículo (pedestre, testemunha e cavaleiro em nenhum).

**8. O que é o "arco" no DER?**
São três relacionamentos "atende" (UOP, delegacia e superintendência) dos quais **no máximo um** vale para cada acidente. O banco guarda a unidade mais específica conhecida, e o CHECK `ck_acidente_unidade_unica` garante isso. Arcos são um conceito do curso *Database Design* do Oracle Academy.

## C. Normalização

**9. O que é 1FN e onde a planilha a violava?**
1FN exige valores atômicos. O `tracado_via` guardava vários valores numa célula ("Aclive;Curva"). Quebramos em linhas com `JSON_TABLE`.

**10. O que é 2FN aqui?**
Nenhum atributo pode depender só de parte da chave. A chave da planilha era (acidente, pessoa, veículo, causa, ordem, traçado). A data dependia só do acidente; a idade, só da pessoa; o tipo, só de (acidente, ordem). Cada dependência parcial virou uma tabela.

**11. O que é 3FN aqui?**
Nenhum atributo não-chave pode depender de outro não-chave. Exemplos:

- acidente → UOP → delegacia → superintendência. A hierarquia virou 3 tabelas.
- data → dia_semana: o atributo foi removido.
- estado_físico → mortos: removido.

**12. Por que não guardar o dia da semana?**
Ele depende da data (dependência transitiva) e pode ser calculado: `DAYNAME(data)` com `lc_time_names = 'pt_BR'`, ou `ELT(DAYOFWEEK(data), …)` na view. Guardar abriria espaço para incoerência, como "2024-01-01 = terça".

**13. Por que não guardar ilesos/feridos/mortos?**
Eram contadores 0/1 que repetiam o `estado_fisico` (conferimos 100%). Os totais saem de `SUM(estado_fisico = 'Óbito')` com GROUP BY, ou da `vw_acidente_totais`.

**14. `pessoa` tem `id_acidente` e `id_veiculo`, e o veículo já tem acidente. Isso não fere a 3FN?**
Para quem está num veículo, sim: há uma redundância (pesid → id_veiculo → id_acidente). Foi uma **decisão consciente**. Pedestres e testemunhas precisam do `id_acidente`, e manter a coluna para todos simplifica as consultas. Ela é **controlada** pela FK composta `(id_veiculo, id_acidente) → veiculo(id, id_acidente)`: o MySQL recusa (erro 1452) uma pessoa num veículo de outro acidente, então a anomalia não acontece. A alternativa pura seria um arco "veículo OU acidente".

**15. A classificação do acidente não é derivável das pessoas?**
É, e confere em 100%. Nós a mantivemos porque é a classificação oficial registrada pela PRF. Dentro da tabela `acidente` ela depende só do id, então não há dependência transitiva. Para não divergir: o app **calcula** a classificação ao inserir, o UPDATE de óbito atualiza as duas na mesma transação e a C-RN08 confere tudo.

**16. A tabela `cidade` é exigida pela 3FN?**
O nome sozinho não determina a UF (36 homônimos, como BOM JESUS em 4 UFs). A UF é um fato **do município**, que tem chave natural (nome, uf). Separar a cidade evita repetir o par em 73 mil acidentes e permite acrescentar atributos do município sem anomalia. Seguimos o critério do grupo de que a tabela "traz informação junto".

**17. Causa, tipo, traçado e tipo de veículo são exigência da 3FN?**
Não. É **padronização** (critério b): as listas são grandes ou podem mudar. A grafia fica num lugar só. Corrigir "Semireboque" para "Semirreboque" mudou **uma** linha do catálogo em vez de 50.449 células da planilha (`05_dml_exemplos.sql` §2.4).

**18. Por que sexo, sentido e estado físico são CHECK e não tabelas?**
São listas pequenas e fixas (2 a 5 valores). Um CHECK com a lista garante o domínio sem um JOIN a mais.

## D. Chaves e restrições (DDL)

**19. Por que a PK de `acidente_tipo` é (id_acidente, ordem) e não (id_acidente, id_tipo)?**
Porque o mesmo tipo pode se repetir. No 571802 houve duas "Colisão com objeto". Quem identifica o evento é a **posição na sequência**.

**20. Por que a PK de `causa_acidente` é (id_acidente, id_causa)?**
A mesma causa não se repete num acidente, e não existe ordem entre causas.

**21. Como o banco garante "uma única causa principal"?**
CHECK não enxerga outras linhas. Criamos uma **coluna gerada virtual** `marcador_principal = IF(principal, id_acidente, NULL)` com **UNIQUE**. O MySQL aceita vários NULL, mas não dois iguais; logo, no máximo uma principal. O "pelo menos uma" vem da transação do app e da validação C-RN01.

**22. Por que as PKs de acidente, pessoa e veículo usam o id da PRF?**
É a chave natural e estável da fonte, o que garante rastreabilidade. O AUTO_INCREMENT serve só para registros novos, numa faixa reservada a partir de 9.000.001 (`ALTER TABLE … AUTO_INCREMENT`).

**23. Onde fica cada FK e por quê?**
Sempre no lado **N**:

- veículo → acidente;
- pessoa → acidente e (veículo, acidente);
- associativas → acidente e catálogo;
- acidente → cidade, condição, fase e unidade (arco);
- uop → delegacia → superintendência.

**24. Por que ON DELETE RESTRICT e não CASCADE?**
Para não apagar dados "sem querer". A exclusão é explícita, filho → pai, numa transação. Além disso, o MySQL proíbe CHECK em coluna usada por FK com CASCADE/SET NULL, e temos CHECK em `pessoa.id_veiculo`. (O dicionário mostra "NO ACTION", que no InnoDB é igual a RESTRICT.)

**25. Que CHECKs existem?**
São 21, entre eles:

- domínios (sexo, estado físico, sentido…);
- faixas (idade 0–110, ano 1900–2100, BR 1–499, coordenadas dentro do Brasil);
- regras entre colunas: km exige BR; condutor/passageiro ⇔ tem veículo; no máximo uma unidade PRF.

**26. Por que `ano_fabricacao` é SMALLINT e não YEAR?**
O tipo YEAR vai de 1901 a 2155, e o CSV tem veículos com ano 1900.

**27. Por que DECIMAL e não FLOAT para km e coordenadas?**
DECIMAL é exato. `DECIMAL(12,10)` guarda as 10 casas da latitude sem erro de arredondamento, e o km tem 1 casa.

**28. Que índices criaram e para quê?**
`idx_acidente_data` (filtros por período), `idx_acidente_br_km` (trechos), `idx_acidente_classificacao`, `idx_cidade_uf`, `idx_pessoa_estado_fisico` (contagem de óbitos) e `idx_veiculo_marca`. As FKs e UNIQUEs já criam índice automaticamente.

**29. Para que serve a colação `utf8mb4_0900_ai_ci`?**
utf8mb4 guarda qualquer acento. "ai_ci" significa sem distinção de acento e de caixa: buscar "sao paulo" encontra "SÃO PAULO".

## E. Carga e DML

**30. Como o CSV entrou no banco?**
Em duas etapas. Primeiro, `LOAD DATA LOCAL INFILE … CHARACTER SET latin1` numa **staging**, com tudo como texto. Depois, `INSERT … SELECT DISTINCT` para cada tabela, na ordem das FKs. A alternativa sem LOAD DATA é `scripts/carregar_staging.py`.

**31. Que dados sujos encontraram?**

- id "6e+05" → 600000;
- NA → NULL;
- vírgula decimal no km;
- 282 idades > 110 → NULL;
- 10.122 anos = 0 → NULL;
- 8.070 marcas "Não Informado" → NULL;
- 57.641 linhas sem pessoa → geram só o veículo.

Os números estão na seção B do `04_validacao.sql`.

**32. Como garantiram que a carga está certa?**
O `04_validacao.sql` compara o esperado (perfilamento em Python) com o obtido no banco: as 16 contagens, as regras de limpeza e as de negócio. Resultado: **0 divergências**.

**33. Mostrem um UPDATE e um DELETE controlado.**
`05_dml_exemplos.sql`:

- correção de idade;
- óbito + reclassificação na mesma transação;
- troca da causa principal (desmarca e depois marca, por causa da UNIQUE);
- padronização do catálogo;
- ROLLBACK de demonstração;
- expurgo do acidente fictício, filho → pai, com a trava `id >= 9000001`.

## F. DQL

**34. Qual a diferença entre INNER JOIN e LEFT JOIN, com exemplo de vocês?**
INNER traz só o que casa dos dois lados; LEFT mantém todas as linhas da esquerda. Na Q11, `veiculo LEFT JOIN (ocupantes)` mantém todos os veículos, e os sem pessoa vêm com NULL: é isso que contamos. Com INNER, eles sumiriam.

**35. Por que a Q07 usa COALESCE nos JOINs?**
Por causa do arco. A delegacia vem da UOP ou direto do acidente (`COALESCE(u.id_delegacia, a.id_delegacia)`), e a superintendência vem da delegacia ou do acidente.

**36. Como evitam contar mortos em dobro?**
Juntar acidente com pessoa **e** com causa multiplica as linhas (pessoa × causa). Por isso os mortos são somados antes, por acidente, numa CTE (`WITH totais AS …`), e só depois juntados.

**37. Onde está o filtro temporal?**
Em quase todas as consultas: `WHERE a.data BETWEEN @data_ini AND @data_fim`. Ele usa o índice `idx_acidente_data`. A Q02 é o exemplo do edital: o volume de acidentes por causa num intervalo de datas.

**38. O que a Q16 faz?**
Remonta a "linha da planilha" de um acidente com junções em 10 tabelas, mais GROUP_CONCAT para causas, tipos e traçados. É o caminho inverso da normalização.

## G. Aplicação

**39. Como o app fala com o banco? Usa ORM?**
Não. Usa o `mysql-connector-python` com SQL escrito à mão em `app/db.py`. Toda tela tem o expander "SQL executado", que mostra cada comando e os parâmetros.

**40. O que é SQL parametrizado e por que usar?**
Os valores vão separados do texto do SQL (`%s`), e o driver faz o escape. Isso impede **SQL injection**: um filtro como `' OR 1=1 --` vira só texto. Nome de tabela não pode ser parâmetro, por isso cada catálogo tem um SQL fixo.

**41. Como funciona a inserção?**
Numa única transação:

1. INSERT do acidente, que devolve o id (`lastrowid`);
2. causas (`executemany`);
3. tipos, com a posição na lista virando a "ordem";
4. traçados;
5. veículos;
6. pessoas, com o rótulo V1/V2 trocado pelo id real do veículo;
7. COMMIT.

Qualquer erro (CHECK, FK…) gera ROLLBACK.

**42. E a exclusão?**
A tela mostra uma pré-visualização das linhas por tabela, pede confirmação digitando o id e então executa uma transação com 6 DELETEs: pessoa → veículo → causas → tipos → traçados → acidente. Depois relê o banco para provar que o acidente sumiu. Registros da PRF (id < 9.000.001) exigem confirmação extra.

**43. Onde fica a senha do banco?**
No `.env`, que não vai para a entrega (o modelo é o `.env.example`). O app usa o `usuport_app`, que só tem SELECT/INSERT/UPDATE/DELETE: não consegue dar DROP nem criar tabelas.

**44. Por que o painel lê o arquivo `.sql`?**
Para o SQL ficar num lugar só. O que roda no DBeaver é exatamente o que roda no app. O app só define `@data_ini` e `@data_fim` com SET parametrizado antes de executar.

## H. Infraestrutura

**45. Como o DBeaver alcança o MySQL dentro da VM?**
Pela rede da VM: em Bridge, ela tem IP próprio na LAN; em NAT, usa redirecionamento da porta 3306. No MySQL, `bind-address = 0.0.0.0` e usuário criado com host `'%'`.

**46. O que significa `bind-address = 127.0.0.1` (o padrão)?**
Que o MySQL só aceita conexões de dentro da própria VM. Por isso mudamos para 0.0.0.0.

**47. Por que `local_infile`?**
O `LOAD DATA LOCAL INFILE` lê o arquivo na máquina do cliente. Por segurança, servidor e cliente precisam permitir: `local_infile = 1` e `--local-infile=1`.

**48. Por que dois usuários?**
É o menor privilégio. O `usuport_admin` (DBeaver) administra o banco; o `usuport_app` (aplicação) só manipula dados.
