# Prompt 2 · O agente de IA: o dono pergunta em português

**Entrega:** o agente de IA da diretoria, um **Genie Agent** ("Farol · Diretoria") que recebe a pergunta
em português, escreve o SQL, roda nas tabelas que você liberou e responde citando os números. Embaixo
dele, a metric view `gold.mv_projetos` (a fórmula de cada KPI num lugar só, tarefa
`metricas_governadas` no job). O Genie é recurso do bundle e lê a gold, a metric view e, **se existir**,
o score do modelo (`gold.score_estouro_30d`, demonstrado na abertura e no [bônus](../bonus/prompt-modelo-ml.md)).
Testado com um benchmark de 20 perguntas e, no fim, **plugado no app do prompt 1** como a aba
**Perguntar**. **Deploy nº 2 da noite** (o bundle `vertice` e o `apps deploy` do app).

> Na segunda, o Genie da noite 1 errou as quatro perguntas do dono ("nenhum atraso custa nada"). O
> modelo de IA dele é o mesmo de hoje. Mudou tudo que está embaixo: o dado integrado e testado, a
> fórmula escrita uma vez e as instruções de negócio.

---

## O que mostrar antes (3 min)

O problema que a metric view resolve, em uma imagem: a mesma pergunta, três respostas.

```
SQL da noite 1 ...... CPI do PRJ-009 = 0,77   (EV / AC, com CASE e replace)
Genie da noite 1 .... CPI do PRJ-009 = 1,9    (inventou: valor do contrato ÷ custo)
Planilha do PMO ..... CPI do PRJ-009 = ?      (cada gerente calcula de um jeito)
```

*"Quando o dono recebe três números, ele não confia em nenhum. A fórmula do CPI precisa morar num
lugar só."*

Depois, abra o Genie da noite 1 ("Farol · Noite 1 (bronze, sem curadoria)") e faça as perguntas que ele errou:

```
"Quanto esse atraso vai me custar?"                      → noite 1: "nenhum atraso tem impacto financeiro"
"Tenho gente parada enquanto outro projeto pede gente?"  → noite 1: "não há colaboradores parados"
```

**Enquanto ele trabalha, você explica:**

- **O que faz disso um agente.** Um chat comum responde de memória e inventa. O Genie tem uma
  **ferramenta** (escrever e rodar SQL no warehouse), olha o resultado e decide o próximo passo; no
  modo Agent ele quebra uma pergunta aberta em várias consultas. E só enxerga o que o Unity Catalog
  deixa a pessoa que pergunta enxergar.
- **Metric view guarda a FÓRMULA, não o número.** `MEASURE(cpi)` no Genie, no SQL e no app é sempre
  `SUM(ev) / SUM(ac)`, recalculado no grão que a pergunta pedir (projeto, cliente, segmento,
  ferramenta, carteira). Razão não se soma: o CPI da carteira é ΣEV ÷ ΣAC, não a média dos CPIs.
- **`comment` e `synonyms` são para o Genie.** "índice de custo" e "desempenho de custo" passam a
  significar CPI; "farol mentiroso" passa a significar melancia.
- **Genie como código.** As instruções de negócio (o "hoje" do dataset, as regras de corte, onde achar a
  causa do atraso, o que é "próximo mês") viram arquivo versionado, com diff e revisão.
- **A pergunta 4 ganha resposta.** "O que vai dar errado no próximo mês" junta as entregas de
  consultoria atrasadas (CodeForge) e o change freeze da Black Friday nos e-commerces, que começa em
  01/11. Com o score do modelo nas tabelas, entram também os projetos "ok" com risco alto ou médio: o
  PRJ-024 aparece duas vezes, 46% no modelo **e** no freeze.
- **Benchmark é teste de IA.** 20 perguntas com a resposta certa em SQL. O script roda cada uma no
  Genie e compara. Mudou a instrução? Roda o benchmark. É o mesmo raciocínio do teste da gold.
- **Ordem que importa:** o Genie só é criado se as tabelas já existem (a metric view nasce no job).
  Do zero: deploy → run → deploy.

---

## O prompt

```
Leia o CLAUDE.md da raiz e aulas/aula-04-produtos-de-dados-ia/prd/CLAUDE.md.
Continue o bundle vertice na raiz deste repositório. Agora a fórmula de
cada KPI num lugar só, e o agente (Genie) que o dono vai usar.

1. Métricas governadas: src/metricas/metricas.sql (sql_task)
   CREATE OR REPLACE VIEW lakehouse_vertice.gold.mv_projetos WITH METRICS
   LANGUAGE YAML AS $$ ... $$ (version 1.1), comment em toda dimensão e
   medida que não for óbvia, e synonyms em português.
   - source: lakehouse_vertice.gold.projeto_situacao_atual, com
     filter status = 'em_andamento'.
   - Dimensões: projeto_id, projeto, cliente, segmento, ferramenta, situacao,
     farol_do_gerente, farol_calculado, gerente_projeto.
   - Medidas: projetos, carteira (SUM valor_contrato), spi (SUM(ev)/SUM(pv)),
     cpi (SUM(ev)/SUM(ac)), eac, estouro_previsto, margem_projetada
     ((SUM(valor_contrato) - SUM(eac)) / SUM(valor_contrato)),
     atraso_projetado_medio_dias, projetos_em_risco, projetos_criticos,
     projetos_melancia (COUNT FILTER WHERE melancia).
   ARMADILHAS MEDIDAS: o YAML precisa da indentação intacta (teste com
   python3 scripts/run_sql.py <arquivo> --profile <perfil>), e NUNCA use ';'
   dentro do YAML, nem num comment: a sql_task do job corta o arquivo em todo ';'.
   Acrescente ao job a tarefa metricas_governadas, depois de
   testes_de_qualidade E status_com_ia.

2. Genie Agent como código
   - scripts/gerar_genie.py gera resources/farol.geniespace.json
     (serialized_space versão 2; ids de 32 caracteres hex, únicos e em ordem):
     tabelas gold.fato_projeto_semana, gold.projeto_situacao_atual,
     gold.status_estruturado, gold.utilizacao_pessoa_semana e
     silver.entregas_fornecedor, e a metric view gold.mv_projetos; as 4
     perguntas do dono como perguntas de exemplo.
     gold.score_estouro_30d (o modelo) entra SÓ se existir: confira com
     databricks tables exists lakehouse_vertice.gold.score_estouro_30d
     --profile <perfil>. Sem ela, nada de instrução nem exemplo sobre score.
   - Instruções de texto: quem pergunta (o dono e a diretoria); HOJE =
     2026-10-16 e o que é "últimos 90 dias / 12 semanas / próximo mês"; as
     fórmulas e as regras de corte; mv_projetos para totais de hoje e
     projeto_situacao_atual para ranking; PV/EV/AC acumulados no fato (nunca
     somar semanas); farol e melancia; "por que o projeto X atrasou" responde
     com status_estruturado dos últimos 90 dias (sem sem_bloqueio e
     nao_reportado), mais o SPI e SREs ociosos se a causa for falta_sre;
     gente parada = utilização < 20% em 12 semanas; fornecedor = prazo real ÷
     prometido na silver.entregas_fornecedor; "o que vai dar errado no
     próximo mês" junta as entregas de consultoria em atraso, o change
     freeze de varejo (01/11/2026 a 10/01/2027) nos projetos de e-commerce
     e, se o score existir, os projetos com situacao = 'ok' e faixa alto ou
     medio (com principais_fatores, na data_referencia mais recente);
     "quais clientes" devolve cada cliente uma vez.
   - Um exemplo de SQL para cada uma das 4 perguntas do dono (e, se o
     score existir, um para "qual a chance de o PRJ-024 estourar?").
   - resources/genie.genie_space.yml: recurso genie_farol, título
     "Farol · Diretoria", warehouse ${var.warehouse_id}.

Rode e me mostre a saída:
  databricks bundle deploy --profile <perfil>
  databricks bundle run vertice_farol --only metricas_governadas --profile <perfil>
  databricks bundle deploy --profile <perfil>
  databricks bundle summary --profile <perfil>
  python3 scripts/genie.py perguntar "Farol · Diretoria" "O que vai dar errado no próximo mês, e o que eu faço agora?" --profile <perfil>
  python3 scripts/genie.py benchmark "Farol · Diretoria" aulas/aula-04-produtos-de-dados-ia/prd/genie-benchmark-diretoria.json --profile <perfil>
Se o benchmark der menos de 16/20, mostre os erros e ajuste a INSTRUÇÃO
(não a pergunta), gere o JSON, faça deploy e rode de novo.

3. Plugue o agente no app minha-torre/ (o do prompt 1), como a tela Perguntar:
   - databricks.yml do app: variáveis genie_space_id e genie_space_name
     (o id do "Farol · Diretoria", pelo bundle summary); no recurso do app,
     user_api_scopes: [dashboards.genie] e o recurso
     { name: genie-space, genie_space: { name, space_id, permission: CAN_RUN } }.
   - app.yaml: env DATABRICKS_GENIE_SPACE_ID com valueFrom: genie-space.
   - server: genie() nos plugins do createApp.
   - client: tela Perguntar com <GenieChat alias="default" /> e o item no menu.
   Nenhum arquivo *.geniespace.json dentro da pasta do app.
   Dentro de minha-torre/: npm run typecheck, databricks bundle deploy e
   databricks apps deploy --profile <perfil>. Me mostre a URL.
```

> **O `genie.py` e o benchmark** vêm do repositório do curso: o passo 0 do
> [README](../README.md#0-antes-de-começar-5-min) baixa os dois para o seu repositório.

---

## O que conferir

```sql
SELECT MEASURE(spi) AS spi, MEASURE(cpi) AS cpi, MEASURE(estouro_previsto) AS estouro,
       MEASURE(projetos_criticos) AS criticos, MEASURE(projetos_melancia) AS melancias
FROM lakehouse_vertice.gold.mv_projetos;
-- 0,92 · 0,97 · R$ 6,47 mi · 7 · 4

-- o mesmo KPI, em outro grão, sem reescrever fórmula nenhuma
SELECT ferramenta, MEASURE(spi) AS spi, MEASURE(projetos_em_risco) AS em_risco
FROM lakehouse_vertice.gold.mv_projetos GROUP BY ferramenta ORDER BY spi;
```

As quatro perguntas do dono, no Genie:

1. *atrasados e de quais clientes* → 17 projetos, com SPI e CPI;
2. *quanto custa* → **R$ 6,47 mi** de estouro previsto, margem projetada de 20%;
3. *gente parada* → as duas SREs do PRJ-007 a ~5% de utilização, e o PRJ-011 pedindo SRE no status;
4. *o que vai dar errado no próximo mês* → as 5 entregas atrasadas da CodeForge e o freeze de 01/11
   nos e-commerces (PRJ-003, 011, 024); com o score, também os projetos "ok" com risco alto ou médio
   (entre eles o **PRJ-024, 46%**).

O benchmark de 20 perguntas: **20/20** no ensaio de 18/10, sem o score. Leva ~6 min: rode enquanto
explica as 5 peças da curadoria.

**No app:** a aba **Perguntar** aparece. Na primeira visita depois do deploy, a tela "Permission
Requested": o app pede para usar o Genie **em seu nome** (por isso o `user_api_scopes`). **Authorize**,
uma vez. Pergunte *"Por que o PRJ-011 atrasou?"* → falta de SRE, 12 semanas, 57 dias de impacto.

> *"Na segunda ele disse que o atraso não custava nada. Hoje ele diz quanto custa, quem está parado,
> qual projeto vai estourar no mês que vem e por quê. O modelo de IA é o mesmo. A diferença foi tudo
> que a gente construiu nas três noites."*

---

## Se der errado

| Sintoma | Causa | Correção |
|---|---|---|
| `METRIC_VIEW_INVALID_VIEW_DEFINITION ... Missing required creator property 'expr'` | Rodou pelo `aitools tools query` | `sql_task` ou `scripts/run_sql.py` |
| `metricas_governadas` falha no job, mas roda pelo `run_sql.py` | Um `;` dentro do YAML (num comment) | A `sql_task` corta o arquivo em todo `;`: troque por vírgula |
| `Table 'lakehouse_vertice.gold.x' does not exist` no deploy | O Genie foi criado antes de a tabela existir | `bundle run vertice_farol` e deploy de novo |
| `Duplicate question ID` | ids não únicos no JSON do Genie | ids de 32 caracteres com prefixo diferente por tipo |
| `must be sorted by id` | lista fora de ordem | ordene por id; tabelas por identifier |
| `modified remotely` no deploy | o Genie foi editado no workspace | leve a mudança para o `gerar_genie.py` e use `--force` só depois disso |
| "O que vai dar errado" volta FAILED | pergunta aberta, três fontes | o exemplo de SQL com `UNION ALL` (score, entregas, freeze) resolve |
| App: tela pede "Permission Requested" | consentimento OAuth (o Genie age em seu nome) | **Authorize**, uma vez |
| App: a aba Perguntar não responde | id do Genie errado no `databricks.yml` do app | confira o id do "Farol · Diretoria" (`bundle summary`) e faça deploy de novo |
| App: `Requested node type [UNKNOWN] is not supported` | arquivo `*.geniespace.json` dentro da pasta do app | o JSON do Genie mora no bundle `vertice`, nunca no app |
| O Genie diz que o PRJ-016 tem "100% de chance" como novidade | não filtrou os que já estão abaixo do corte | instrução: no futuro, interessa `situacao = 'ok'` com faixa alto ou medio |

**Tempo medido:** metric view ~10 s; deploy ~10 s; benchmark de 20 perguntas ~6 min (18/10).
