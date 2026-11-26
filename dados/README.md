# Dados

O arquivo da PRF entregue à equipe para o cenário USUPORT está aqui **compactado**:

```
dados/acidentes2024_todas_causas_tipos_Usuport.csv.gz
```

O original tem 222 MB e passa do limite de 100 MB por arquivo do GitHub; compactado com gzip, fica com 13 MB. Antes de carregar o banco, descompacte na raiz do projeto:

```bash
gunzip -k dados/acidentes2024_todas_causas_tipos_Usuport.csv.gz
```

O `-k` mantém o `.gz` e cria o `.csv` ao lado. O `sql/02_staging.sql` lê exatamente esse caminho, relativo à raiz do projeto. O `.csv` descompactado não vai para o GitHub (está no `.gitignore`).

| Propriedade | Valor |
|---|---|
| Origem | planilha de sinistros em rodovias federais — PRF, 2024 (todas as causas e tipos) |
| Tamanho | ~222 MB descompactado · 603.215 linhas + cabeçalho · 37 colunas |
| Codificação | Latin-1 (ISO-8859-1) |
| Separador | `;`, textos entre aspas duplas, fim de linha CRLF |
| Ausência de valor | textos `NA` ou `N/A` |
