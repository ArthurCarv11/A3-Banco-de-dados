# Dados

Coloque aqui o arquivo entregue pelo professor para o cenário USUPORT:

```
dados/acidentes2024_todas_causas_tipos_Usuport.csv
```

| Propriedade | Valor |
|---|---|
| Origem | planilha de sinistros em rodovias federais — PRF, 2024 (todas as causas e tipos) |
| Tamanho | ~222 MB · 603.215 linhas + cabeçalho · 37 colunas |
| Codificação | Latin-1 (ISO-8859-1) |
| Separador | `;`, textos entre aspas duplas, fim de linha CRLF |
| Ausência de valor | textos `NA` ou `N/A` |

O CSV **não** vai no `.zip` de entrega, por causa do tamanho (o professor já tem o arquivo). O `sql/02_staging.sql` lê o arquivo exatamente deste caminho, relativo à raiz do projeto.
