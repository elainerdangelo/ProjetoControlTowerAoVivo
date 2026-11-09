# Prompt 4 · O dashboard: o dono vê a Torre

**Entrega:** o dashboard **"Projeto Farol · Portfólio"** (3 páginas: Portfólio, Pessoas,
Fornecedores) como código no bundle, lendo a gold que o job recalcula toda segunda.
**Deploy nº 5**, o último da noite.

> O fechamento da noite. Na segunda, o dashboard da noite 1 lia a bronze, com `CASE`, `replace` e
> `try_cast` dentro de cada gráfico. Hoje ele lê a gold: integrada, limpa e testada. O SQL de
> cada gráfico cabe em cinco linhas.

---

## O que mostrar antes

Abra lado a lado o dashboard da noite 1 ("Projeto Farol · Noite 1 (bronze)") e uma das queries
dele. Mostre o tamanho do SQL: o `CASE` do número de série do Excel, o `replace` da vírgula, o
`filter(custom_fields, ...)` do ClickUp. *"Toda essa limpeza morava dentro do gráfico. Se alguém
mudasse um, o outro ficava diferente."*

**Enquanto ele trabalha, você explica:**

- **Dashboard como código.** O JSON fica no Git, dentro do bundle: tem diff, revisão e
  rollback. Um script Python (`gerar_dashboard.py`) escreve o JSON, porque escrever o JSON à
  mão é pedir para errar uma vírgula.
- **Nome de tabela puro.** As queries dizem `FROM projeto_situacao_atual`, sem catálogo nem
  schema. Quem completa é o recurso do bundle (`dataset_catalog`, `dataset_schema`). O mesmo
  dashboard aponta para dev ou prod sem mudar uma linha.
- **Razão não se soma.** O SPI da carteira é `SUM(ev) / SUM(pv)`, não a média dos SPIs dos
  projetos. Um projeto pequeno atrasado não pode pesar igual a um grande. (Amanhã essa fórmula
  vai morar num lugar só, a metric view, e o Genie e o app vão usar a mesma.)
- **O farol do gerente ao lado do farol pelo número.** É a pergunta bônus do dono: *posso
  confiar no farol?* As melancias aparecem sozinhas.
- **Não edite o dashboard no workspace.** Se editar, o próximo `bundle deploy` recusa
  ("modified remotely"). A mudança vai para o script, e o script gera o JSON.

---

## O prompt

```
Continue o bundle na raiz deste repositório. O job está pronto e a gold
atualizada. Agora o dashboard, como código. Use a skill
databricks-aibi-dashboards.

1. scripts/gerar_dashboard.py gera resources/dashboard-portfolio.lvdash.json
   (AI/BI, GRID_V1). As queries da gold usam o nome de tabela PURO, sem
   catálogo nem schema; a silver.entregas_fornecedor vai com o nome completo
   lakehouse_vertice.silver.entregas_fornecedor. Três páginas:

   Portfólio
   - KPIs da carteira em andamento, calculados na projeto_situacao_atual
     (WHERE status = 'em_andamento'): carteira (SUM(valor_contrato)), SPI
     (SUM(ev)/SUM(pv)), CPI (SUM(ev)/SUM(ac)), estouro previsto, projetos em
     risco (atenção + crítico), críticos e melancias. Razão é SUM/SUM, nunca
     AVG de razão.
   - barra de estouro previsto por projeto, colorida por situação
     (crítico #FF5F46, atenção #F6C344, ok #22C2F4)
   - dispersão SPI × CPI, um ponto por projeto
   - linha de SPI e CPI semanais da carteira (SUM(ev)/SUM(pv) por semana no
     fato_projeto_semana, a partir de 2025-03-07)
   - tabela dos projetos em andamento com o farol do gerente ao lado do
     farol pelo número e a coluna melancia

   Pessoas
   - top 15 pessoas por custo da hora parada (utilizacao_pessoa_semana,
     semana > 2026-07-24, as últimas 12 semanas)
   - tabela de utilização por pessoa e projeto, da mais parada à mais ocupada
   - barras de causas de bloqueio por projeto (status_estruturado, últimos
     90 dias, sem 'sem_bloqueio' e 'nao_reportado')

   Fornecedores (sobre silver.entregas_fornecedor)
   - tabela por fornecedor: grafias no cadastro, entregas, prazo real ÷
     prometido, % no prazo, em atraso hoje
   - tabela das entregas em atraso hoje

   Tema nas cores da Jornada: #0059DB, #22C2F4, fundo #14141A no escuro.
   Um título de texto em cada página com a pergunta do dono que ela responde.

2. resources/dashboard.dashboard.yml: recurso dashboard_portfolio, display
   name "Projeto Farol · Portfólio", file_path para o JSON, dataset_catalog
   ${var.catalog}, dataset_schema gold, warehouse_id ${var.warehouse_id}.

Antes do deploy, rode cada query do dashboard (prefixando
lakehouse_vertice.gold. nas tabelas da gold) e me mostre a contagem de linhas
de cada uma e os valores dos KPIs.

Rode e me mostre a saída:
  python3 scripts/gerar_dashboard.py
  databricks bundle validate --profile DEFAULT
  databricks bundle deploy --profile DEFAULT
  databricks bundle summary --profile DEFAULT
```

---

## O que conferir

`bundle summary` mostra a URL do dashboard. Abra e publique (**Publish**). Na página **Portfólio**:

| KPI | Valor |
|---|---|
| Carteira em andamento | R$ 208,6 mi |
| SPI · CPI da carteira | 0,92 · 0,97 (CPI exato 0,965: o widget mostra 0,96, só formatação) |
| Estouro previsto | **R$ 6,47 mi** |
| Projetos em risco · críticos · melancias | 17 · 7 · 4 |

Na página **Pessoas**, COL0017 e COL0018 (as SREs do PRJ-007) no topo do custo parado, e o
PRJ-011 com a barra de `falta_sre`. Na página **Fornecedores**, a CodeForge com 4 grafias, prazo
×1,41 e 0% no prazo.

> *"Na segunda, o Genie disse que o atraso não custava nada. Hoje o dashboard diz quanto custa
> (R$ 6,47 milhões), quem está parado e qual fornecedor não cumpre prazo. E toda segunda às 6h
> esses números se atualizam sozinhos. Amanhã o dono vai poder perguntar em português, e ganhar
> um app."*

---

## Bônus · só o professor: o Claude Code confere a tela (`/chrome`)

O fechamento da noite: o Claude Code escreveu o código, fez o deploy, e agora abre o workspace no
navegador para conferir o que fez, como uma pessoa faria.

```
/chrome
Abra o dashboard "Projeto Farol · Portfólio" no workspace, publique,
e me diga se os KPIs batem com a tabela do "O que conferir" do prompt 4.
```

Ele navega, clica em **Publish** e compara carteira, SPI · CPI, estouro e as contagens com a tabela
acima.

- **Não é passo da turma.** Pede a extensão Claude in Chrome instalada, login e permissão de site:
  mais 10 minutos e mais um ponto de falha. A CLI e a verificação SQL já provam tudo.
- **Ensaie uma vez antes** (o dashboard já existe no workspace, dá sem rodar o resto): a extensão
  conectada, e o workspace sem pedir login no meio.
- Se o navegador travar ao vivo, siga sem ele: abra o dashboard você mesmo e publique.

---

## Se der errado

| Sintoma | Causa | Correção |
|---|---|---|
| Widget "no selected fields to visualize" | `fields[].name` ≠ `encodings.fieldName` | Os dois nomes têm que ser idênticos |
| Dashboard vazio ou `TABLE_OR_VIEW_NOT_FOUND` | Query com catálogo escrito à mão, ou sem `dataset_schema` | Nome puro no SQL + `dataset_catalog`/`dataset_schema` no YAML |
| `modified remotely` no deploy | O dashboard foi editado no workspace | Leve a mudança para o script, gere o JSON e use `--force` só depois disso |
| KPI do SPI diferente de 0,92 | Média dos SPIs em vez de razão das somas | `SUM(ev) / SUM(pv)` |
| Página Pessoas sem as causas | A tarefa `status_com_ia` não rodou | Rode o job (prompt 3) e recarregue |

**Tempo medido:** deploy ~10 s.
