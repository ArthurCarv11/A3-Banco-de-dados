# Infraestrutura — VirtualBox + Ubuntu + MySQL 8 + DBeaver

> Time Índice — Grupo 4 · Cenário USUPORT. O edital exige que o SGBD rode **dentro de uma VM do Oracle VM VirtualBox** e que o esquema seja inspecionado por uma ferramenta administrativa conectada à VM **pela rede**.

```
 ┌──────────────── Computador (Windows) ────────────────┐
 │  DBeaver / Workbench ──┐                              │
 │  App Streamlit ────────┼──► rede (Bridge ou NAT:3306) │
 │                        │                              │
 │   ┌──────── VirtualBox: VM Ubuntu Server ─────────┐   │
 │   │  MySQL 8.0  (bind-address 0.0.0.0, porta 3306) │   │
 │   │  banco: usuport  (16 tabelas, 5 views)         │   │
 │   └────────────────────────────────────────────────┘   │
 └──────────────────────────────────────────────────────┘
```

## 1. Criar a VM

1. Baixe a ISO do **Ubuntu Server 24.04 LTS** (ou 22.04).
2. No VirtualBox: **Novo** → nome `usuport-db`, tipo Linux / Ubuntu (64-bit).
   - **Memória:** 4096 MB (o MySQL usa ~1 GB de buffer na carga). Funciona com 2048 MB, porém mais devagar.
   - **CPUs:** 2.
   - **Disco:** 25 GB, dinamicamente alocado.
3. Instale o Ubuntu com as opções padrão e marque **Install OpenSSH server**, que facilita copiar arquivos.

## 2. Rede — escolha UMA das opções

### Opção A — Placa em modo Bridge (recomendada para a apresentação)

`Configurações da VM → Rede → Adaptador 1 → Conectado a: Placa em modo Bridge`.

A VM recebe um IP da mesma rede do computador. Descubra-o dentro da VM:

```bash
ip -4 addr show | grep inet
```

Exemplo: `192.168.0.50`. O DBeaver e o app conectam em `192.168.0.50:3306`.

### Opção B — NAT com redirecionamento de porta (funciona até sem Wi-Fi)

`Rede → Adaptador 1 → NAT → Avançado → Redirecionamento de Portas → +`:

| Nome | Protocolo | IP do hospedeiro | Porta do hospedeiro | IP do convidado | Porta do convidado |
|---|---|---|---|---|---|
| mysql | TCP | 127.0.0.1 | 3306 | (vazio) | 3306 |
| ssh | TCP | 127.0.0.1 | 2222 | (vazio) | 22 |

O DBeaver e o app conectam em `127.0.0.1:3306`.

> Se o Windows já tiver um MySQL usando a porta 3306, use **3307** como porta do hospedeiro. Foi assim nos testes do grupo.

## 3. Instalar e configurar o MySQL 8

```bash
sudo apt update
sudo apt install -y mysql-server
mysql --version                  # deve mostrar 8.0.x
sudo systemctl enable --now mysql
```

Edite `/etc/mysql/mysql.conf.d/mysqld.cnf` (por exemplo com `sudo nano`) e, na seção `[mysqld]`:

```ini
bind-address        = 0.0.0.0     # aceitar conexões vindas de fora da VM (padrão: 127.0.0.1)
mysqlx-bind-address = 0.0.0.0
local_infile        = 1           # permitir LOAD DATA LOCAL INFILE (carga do CSV)
character-set-server = utf8mb4
collation-server     = utf8mb4_0900_ai_ci
```

```bash
sudo systemctl restart mysql
sudo ss -tlnp | grep 3306        # deve mostrar 0.0.0.0:3306
sudo ufw allow 3306/tcp          # só se o firewall (ufw) estiver ativo
```

### Usuários

No Ubuntu, o `root` do MySQL entra **sem senha** pelo `sudo mysql` (autenticação `auth_socket`) e **não** aceita conexão remota. Crie dois usuários com host `'%'` (qualquer origem):

```bash
sudo mysql
```

```sql
-- administrador (DBeaver/Workbench): pode tudo, mas só no banco usuport
CREATE USER 'usuport_admin'@'%' IDENTIFIED BY 'TROQUE_A_SENHA_ADMIN';
GRANT ALL PRIVILEGES ON usuport.* TO 'usuport_admin'@'%';

-- aplicação Streamlit: princípio do menor privilégio (só DML, nada de DDL)
-- EXECUTE: permite ao app chamar as procedures do 08_rotinas.sql (CALL)
CREATE USER 'usuport_app'@'%' IDENTIFIED BY 'TROQUE_A_SENHA_APP';
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON usuport.* TO 'usuport_app'@'%';

FLUSH PRIVILEGES;
```

> Os `GRANT … ON usuport.*` funcionam mesmo antes de o banco existir. Se o usuário já tinha sido criado sem `EXECUTE`, basta rodar só a linha do `GRANT`.

> **Procedures e triggers (`sql/08_rotinas.sql`) precisam ser criadas como root.** Com o log binário ligado (padrão do MySQL 8), `CREATE TRIGGER` exige o privilégio SUPER, que o `usuport_admin` não tem. Rode esse arquivo pelo cliente `mysql` dentro da VM (`sudo mysql …`), e não pelo DBeaver: o comando `DELIMITER` usado para escrever as rotinas é do cliente `mysql`.

## 4. Levar o projeto e o CSV para a VM

Opção 1, por `scp` a partir do Windows (no PowerShell). Com Bridge use o IP da VM; com NAT use `-P 2222 usuario@127.0.0.1`:

```bash
scp -r "A3 banco de dados" usuario@192.168.0.50:~/usuport
```

Opção 2: pasta compartilhada do VirtualBox (exige os Guest Additions) ou pendrive.

Confira se o CSV está em `~/usuport/dados/acidentes2024_todas_causas_tipos_Usuport.csv`.

## 5. Criar e carregar o banco (dentro da VM)

Rode **a partir da raiz do projeto**, porque o caminho do CSV no `LOAD DATA LOCAL INFILE` é relativo a ela:

```bash
cd ~/usuport
sudo mysql --local-infile=1 --default-character-set=utf8mb4 < sql/00_completo.sql
```

O processo leva cerca de 1 minuto. Ele executa DDL → staging → carga → validação (todas as linhas devem sair `OK`) → DML de exemplo → DQL → views → rotinas. Para rodar por etapas, execute `01_ddl.sql` … `08_rotinas.sql` na ordem (o `08` só existe a partir da versão 2).

Se o `LOAD DATA` falhar (erros 3948 ou 2068), carregue a staging pelo Python e siga com o `03_carga.sql`:

```bash
sudo mysql < sql/01_ddl.sql
python3 scripts/carregar_staging.py       # usa o .env; cria a staging e carrega o CSV
sudo mysql < sql/03_carga.sql && sudo mysql < sql/04_validacao.sql
```

## 6. Conectar o DBeaver (inspeção do esquema físico)

1. **Banco de dados → Nova conexão → MySQL**.
2. **Host:** IP da VM (Bridge) ou `127.0.0.1` (NAT). **Porta:** 3306. **Banco:** `usuport`. **Usuário:** `usuport_admin`.
3. Aba **Propriedades do driver**: `allowPublicKeyRetrieval = true` e `useSSL = false` (laboratório).
4. **Testar conexão**. Se ele pedir para baixar o driver, aceite.

O que mostrar na banca:

- **Navegador:** `usuport → Tabelas` (16) e `Views` (5). Em cada tabela, as abas **Colunas** (com os comentários = finalidade), **Restrições** (PK, UNIQUE, **CHECK**), **Chaves estrangeiras** e **Índices**.
- **Diagrama ER do banco:** botão direito em `usuport` → **Visualizar diagrama**. Para **exportar**: no diagrama, botão direito → **Exportar diagrama** (ou o ícone de salvar da barra do diagrama) → PNG/SVG. Esse é o diagrama físico gerado pelo próprio SGBD, que complementa o `docs/der_logico.png`.
- **Editor SQL** (`Ctrl+]`): rode `sql/04_validacao.sql`, que deve dar tudo `OK`, e consultas do `sql/06_dql_consultas.sql`.
- **Persistência:** depois de inserir pelo app, `SELECT * FROM vw_acidente_detalhe WHERE id >= 9000001;`.

### Alternativa: MySQL Workbench

**Database → Manage Connections** com os mesmos dados. Para o diagrama: **Database → Reverse Engineer…** → escolha `usuport` → o EER Diagram é gerado → **File → Export → Export as PNG**.

## 7. Conectar o app (no computador)

```bash
pip install -r requirements.txt
copy .env.example .env          # Windows (no Linux: cp)
```

Edite o `.env`: `DB_HOST` = IP da VM (ou 127.0.0.1 no NAT), `DB_PORT`, `DB_USER=usuport_app` e `DB_PASSWORD`. Depois:

```bash
streamlit run app/app.py
```

A barra lateral mostra "MySQL 8.0.x em <hostname da VM>". O hostname da VM é a prova de que o app fala com o banco virtualizado.

## 8. Checklist do dia da apresentação

- [ ] VM ligada **antes** da apresentação (o boot leva ~1 min)
- [ ] `sudo systemctl status mysql` → active (running)
- [ ] No Windows: `Test-NetConnection 192.168.0.50 -Port 3306` → `TcpTestSucceeded : True`
- [ ] DBeaver conectado, com a conexão já salva
- [ ] `.env` apontando para a VM; app aberto em `http://localhost:8501`
- [ ] Um acidente de teste pronto para excluir (ou inserir um na hora)

## 9. Problemas comuns

| Erro | Causa | Solução |
|---|---|---|
| `2003 Can't connect to MySQL server` | bind-address em 127.0.0.1, firewall, IP errado ou VM em NAT sem redirecionamento | revise as seções 2 e 3; `ss -tlnp \| grep 3306` |
| `1130 Host '...' is not allowed to connect` | usuário criado como `'usuario'@'localhost'` | crie o usuário com `@'%'` |
| `1045 Access denied` | senha errada ou tentativa de usar o `root` remotamente | use `usuport_admin` / `usuport_app` |
| `Public Key Retrieval is not allowed` (DBeaver) | autenticação caching_sha2 sem SSL | `allowPublicKeyRetrieval=true` |
| `3948 Loading local data is disabled` | servidor com local_infile=0 | `local_infile = 1` no mysqld.cnf, ou `SET GLOBAL local_infile = 1;` |
| `2068 LOAD DATA LOCAL INFILE file request rejected` | cliente sem `--local-infile=1` | rode o cliente com `--local-infile=1` ou use `scripts/carregar_staging.py` |
| `Errcode: 2 - No such file` no LOAD DATA | cliente rodando fora da raiz do projeto | `cd ~/usuport` antes de executar |
| acentos estranhos (`VÃ­timas`) só em `information_schema.CHECK_CONSTRAINTS` | defeito de exibição do MySQL 8 | a restrição está correta: confira com `SHOW CREATE TABLE` |

## 10. Ambiente de teste usado pelo grupo

Antes de ir para a VM, todo o pacote foi testado num **MySQL 8.0.46 em Docker**: carga completa, validação com 0 divergências, DML, as 18 consultas DQL, as views e o app.

```bash
docker run -d --name usuport-mysql -p 3307:3306 -e MYSQL_ROOT_PASSWORD=<senha> \
  -v "<pasta do projeto>:/repo" mysql:8.0 --local-infile=1
docker exec -w /repo usuport-mysql sh -c "mysql -uroot -p<senha> --local-infile=1 < sql/00_completo.sql"
```

O Docker serviu **só para testar**: na apresentação, o banco precisa estar na VM do VirtualBox.
