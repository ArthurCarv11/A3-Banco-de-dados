# Roteiro da apresentação (15–20 min) + arguição (5–10 min)

> **UNIFACS — Campus CTN, Salvador** · UC Projeto Integrador de Banco de Dados — Avaliação A3
> Professores: Sergio Spinola e Alexandre Anunciação
> **Equipe: Time Índice — Grupo 4 | Cenário: USUPORT**

A ordem segue o item 5 do edital:

1. regra de negócio e DER;
2. MySQL ativo no VirtualBox e conexão pelo DBeaver/Workbench;
3. app em tempo real (inserção, consulta e exclusão com persistência);
4. perguntas individuais.

Os tempos somam **~19 min**, o que deixa uma folga de 1 min dentro do limite de 20.

## Antes de começar (10 min antes, responsável: Miguel)

- [ ] VM `usuport-db` ligada; `sudo systemctl status mysql` → *active (running)*
- [ ] No Windows: `Test-NetConnection <IP da VM> -Port 3306` → `True`
- [ ] DBeaver aberto e conectado em `usuport` (conexão já salva), com uma aba SQL aberta
- [ ] App rodando (`streamlit run app/app.py`); a barra lateral mostra "MySQL 8.0.x em <hostname da VM>"
- [ ] Abas abertas no navegador: Consulta · Inserção · Exclusão · Painel
- [ ] `docs/der_conceitual.png` e `docs/der_logico.png` abertos em tela cheia
- [ ] Projetor espelhando a tela, fonte do DBeaver aumentada (Ctrl + `+`)

---

## Bloco 1 — Abertura e contexto · **Filipe Albuquerque Oliveira** · 0:00–1:30

**Mostra:** a capa do relatório e, em seguida, o CSV aberto num editor (as primeiras linhas).

**Fala (roteiro):**

- "Somos o Time Índice, grupo 4. Nosso cenário é o **USUPORT**, e a base que recebemos é a planilha de sinistros nas rodovias federais da PRF de 2024."
- "O problema: são **603 mil linhas para só 73 mil acidentes**. Cada linha mistura acidente, pessoa, causa e tipo. O acidente do ônibus em Teófilo Otoni, com 53 pessoas, ocupa **1.540 linhas**."
- "Nosso contexto de aplicabilidade é um **sistema de gestão e análise de sinistros** que troca essa planilha por um banco íntegro, consultável e auditável, com MySQL numa VM e uma aplicação CRUD."

## Bloco 2 — Regras de negócio e DER conceitual · **Guilherme Cabral Teixeira** · 1:30–4:30

**Mostra:** `docs/der_conceitual.png`.

**Fala:**

- Entidades: **acidente, pessoa, veículo** e a hierarquia **UOP → delegacia → superintendência**.
- **Atributos multivalorados** (elipse dupla): causas, tipos em sequência e traçado da via. **Compostos**: local (BR, km, sentido, município, UF) e coordenadas. **Derivados** (tracejados): dia da semana e totais de vítimas. Os derivados **não** são guardados.
- As regras saíram dos dados. Quatro exemplos:
  - todo acidente tem **exatamente uma causa principal** (73.156 de 73.156);
  - o **mesmo tipo pode se repetir** em ordens diferentes (1.509 acidentes);
  - **condutor e passageiro sempre estão num veículo**; pedestre, testemunha e cavaleiro nunca;
  - a superintendência pode ser **de outra UF** (ex.: Goiás atendido pela SPRF-DF).
- Cardinalidades: acidente 1:N pessoa e 1:N veículo; veículo 0..1:N pessoa; o "atende" da PRF é um **arco exclusivo**.

## Bloco 3 — Modelo lógico e normalização · **Arthur Cordeiro de Carvalho Cruz** · 4:30–7:30

**Mostra:** a tabela do acidente 661121 no `memorial_normalizacao.md` e depois o `docs/der_logico.png`.

**Fala:**

- **1FN:** o traçado vinha como "Aclive;Curva" numa célula, então foi quebrado em linhas. km e coordenadas viraram número.
- **2FN:** a chave da planilha era (acidente, pessoa, veículo, causa, ordem, traçado). Cada grupo de atributos dependia só de **parte** dela, e cada parte virou uma tabela: acidente, pessoa, veículo, causa_acidente, acidente_tipo e acidente_tracado. "O ônibus caiu de **1.540 linhas para 74**."
- **3FN:** UOP → delegacia → superintendência era transitivo e virou três tabelas. dia_semana (depende da data) e mortos (dependem do estado físico) foram **removidos**.
- **Decisões que defendemos:**
  - o **arco** (no máximo uma unidade preenchida), para não perder 109 acidentes;
  - a **FK composta** pessoa → veículo do mesmo acidente;
  - a classificação mantida, com consulta de conferência.
- O critério de tabela × CHECK: vira tabela se **traz informação junto** ou se a lista é **grande ou muda**; listas pequenas e fixas viram CHECK.

## Bloco 4 — VirtualBox + MySQL ativo · **Miguel Lima Quadros Gomes** · 7:30–9:30

**Mostra:** a janela do VirtualBox com a VM ligada; o terminal da VM.

**Comandos ao vivo:**

```bash
sudo systemctl status mysql          # active (running)
mysql --version                      # 8.0.x
sudo ss -tlnp | grep 3306            # 0.0.0.0:3306 → aceita conexão externa
grep -E "bind-address|local_infile" /etc/mysql/mysql.conf.d/mysqld.cnf
sudo mysql -e "SELECT user, host FROM mysql.user WHERE user LIKE 'usuport%';"
```

**Fala:** a rede (Bridge ou NAT com redirecionamento da porta 3306); `bind-address = 0.0.0.0`; os dois usuários com host `'%'`; e o `usuport_app` só com DML (**menor privilégio**).

## Bloco 5 — Inspeção no DBeaver · **Alisson Sousa Santos** · 9:30–12:00

**Mostra (DBeaver conectado ao IP da VM):**

1. Propriedades da conexão: host = **IP da VM**, porta 3306. Isso prova que o banco está na VM.
2. `usuport → Tabelas` (16) e `Views` (5). Abra `pessoa`: aba **Restrições** (CHECKs), **Chaves estrangeiras** (inclusive a composta) e **Índices**.
3. Botão direito em `usuport` → **Visualizar diagrama** (o ER físico gerado pelo SGBD).
4. Rode a seção A do `sql/04_validacao.sql` → todas as linhas **OK**.
5. Rode a **Q02** do `sql/06_dql_consultas.sql`: causas principais no período, com INNER JOIN, LEFT JOIN, GROUP BY, COUNT e filtro de datas.

**Fala:** "Todo o banco é recriado do zero pelo `00_completo.sql` em cerca de 40 segundos, com carga, limpeza e validação."

## Bloco 6 — App: inserção e consulta ao vivo · **Cláudio Roberto Cruz Santiago Santos** · 12:00–15:30

**Mostra:** o app no navegador.

1. **Inserção:**
   - preencha a data, Salvador/BA, BR-324, a superintendência SPRF-BA → DEL01-BA → UOP01-DEL01-BA;
   - escolha 2 causas e marque a principal;
   - deixe 2 tipos na sequência e o traçado "Reta";
   - cadastre 2 veículos e 3 pessoas (uma delas uma testemunha **sem** veículo).
   - Mostre a **classificação calculada** e clique **Gravar** → aparece o id (≥ 9.000.001).
2. Abra o expander **"SQL executado"**: `START TRANSACTION`, os INSERTs parametrizados (`%s`) e o `COMMIT`.
3. **Consulta:** filtre pelo id → clique na linha → a ficha com causas, tipos em ordem, veículos e pessoas.
4. **Prova de persistência** no DBeaver: `SELECT * FROM vw_acidente_detalhe WHERE id >= 9000001;`

**Fala:**

- "Tudo numa transação: se uma regra falhar, por exemplo um condutor sem veículo, o MySQL recusa pelo CHECK e o app faz ROLLBACK."
- Se der tempo, demonstre: escolha "Condutor" sem veículo e mostre o aviso.

## Bloco 7 — App: exclusão ao vivo · **Guilherme Cabral Teixeira** · 15:30–17:30

1. **Exclusão:** escolha o acidente recém-criado → a pré-visualização mostra quantas linhas de cada tabela serão apagadas.
2. Digite o id para confirmar → **Excluir definitivamente** → aparecem as linhas removidas por tabela e o SQL da transação (filhos antes do pai).
3. No DBeaver: rode o mesmo SELECT do bloco 6 → o acidente sumiu.

**Fala:** "As FKs são RESTRICT. Apagar o acidente direto daria o erro 1451, por isso o app apaga pessoa → veículo → causas → tipos → traçados → acidente na mesma transação. Registros originais da PRF exigem uma confirmação extra."

## Bloco 8 — Painel e encerramento · **Filipe Albuquerque Oliveira** · 17:30–19:00

**Mostra:** o Painel gerencial com a Q02 (causas) e a Q10 (urbano × rural).

**Fala:**

- "O painel lê o mesmo arquivo `06_dql_consultas.sql` que rodamos no DBeaver: o SQL fica num lugar só."
- "Exemplo de achado: em área rural morrem **11,15 pessoas a cada 100 acidentes**, contra **4,80** em área urbana."
- "Entregamos o relatório em PDF, o pacote SQL modular e único, o app comentado e a pasta dos certificados Oracle Academy. Obrigado; estamos prontos para as perguntas."

---

## Plano B

| Falha | O que fazer |
|---|---|
| Wi-Fi da sala bloqueia a Bridge | trocar a VM para NAT + redirecionamento 127.0.0.1:3306 (`docs/infra_vm.md` §2B) e ajustar `DB_HOST` no `.env` |
| App não sobe | demonstrar o CRUD pelo DBeaver com o `sql/05_dml_exemplos.sql` (INSERT, UPDATE e DELETE em transação) |
| Projetor sem resolução para o DER | abrir o PNG com zoom ou mostrar o diagrama do próprio DBeaver |

## Divisão para estudar a arguição

Cada um domina o seu bloco **e** lê o `docs/guia_arguicao.md` inteiro. As perguntas são sorteadas.

| Integrante | Foco principal | Foco secundário |
|---|---|---|
| Filipe | contexto, requisitos, painel/DQL | views |
| Guilherme | regras de negócio, DER conceitual, exclusão | FKs e RESTRICT |
| Arthur | normalização 1FN–3FN, decisões de modelagem | dicionário de dados |
| Miguel | VirtualBox, rede, MySQL, usuários | LOAD DATA / carga |
| Alisson | DBeaver, DDL (CHECK, UNIQUE, índices), validação | consultas com JOIN |
| Cláudio | app: transação, SQL parametrizado, inserção/consulta | código `app/db.py` |
