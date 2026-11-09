# Projeto Farol · Vértice Tecnologia: contexto da noite 4

Noite 4 da Imersão Jornada de Dados (**quinta, 22/10/2026, 19h30**): **Cientista de dados e
Engenheiro de IA**. Leia este arquivo antes de escrever qualquer código. Ele vale para os prompts da
noite e completa o `CLAUDE.md` da raiz do repositório (o da noite 3), que continua valendo.

> **A pergunta da noite: "O que vai dar errado no próximo mês? E o dono, que não escreve SQL?"**
> A noite 3 deixou a Torre rodando sozinha toda segunda às 6h, com um dashboard. Hoje ela ganha um
> modelo que avisa **antes**, um Genie que responde em português e um app com URL.

---

## 1. O que já existe (noites 1 a 3)

Catálogo `lakehouse_vertice`. O "hoje" do dataset é **16/10/2026**: nunca use `current_date()`.
O bundle `vertice` está na raiz do repositório, com o job `vertice_farol` (6 tarefas: 2 de ingestão,
conferência, medalhão, testes, IA) e o dashboard "Projeto Farol · Portfólio".

| Tabela | O que é |
|---|---|
| `gold.projeto_situacao_atual` | fotografia de hoje por projeto: SPI, CPI, EAC, estouro previsto, margem, atraso projetado, situação (ok, atenção, crítico, concluído), farol do gerente × farol calculado, `melancia` |
| `gold.fato_projeto_semana` | projeto × semana: PV, EV, AC **acumulados**, SPI, CPI, farol, horas |
| `gold.status_estruturado` | status semanal em colunas: causa_bloqueio (change_freeze, falta_sre, dependencia_fornecedor, rotatividade, mudanca_escopo, bug_retrabalho, aprovacao_cliente, sem_bloqueio, nao_reportado), bloqueio, quem_destrava, dias_impacto |
| `gold.utilizacao_pessoa_semana` | pessoa × projeto × semana: papel, senioridade, utilização, horas e custo ociosos |
| `silver.entregas_fornecedor` | cada entrega de fornecedor: prometido × entregue, `em_atraso` (a CodeForge entrega com prazo ×1,41) |

## 2. O que a noite 4 constrói

```
 job vertice_farol (o mesmo da noite 3, mais 4 tarefas)
   ... testes_de_qualidade ─┬─ ml_features ── ml_modelo ── ml_score ──▶ gold.score_estouro_30d
   ... status_com_ia ───────┤   (ml.features_projeto_semana · ml.modelo_estouro_30d@prod · ml.modelo_metricas)
                            └─ metricas_governadas ──▶ gold.mv_projetos (metric view)

 Genie "Farol · Diretoria" (recurso do bundle vertice) ◀── gold + mv_projetos + score + entregas_fornecedor
        ▲
        │ aba "Perguntar"
 App "Projeto Farol" (Databricks App, AppKit, bundle próprio em minha-torre/)
        ├── leitura: config/queries/*.sql no SQL warehouse (gold)
        ├── score: rota do servidor /api/score-estouro (opcional, não quebra o build)
        └── escrita (prompt 4, opcional): Lakebase (Postgres) torre.decisoes
        Projetos em risco · Simulador de realocação · Perguntar · (Decisões)
```

| Prompt | Entrega |
|---|---|
| 1 · o app | `minha-torre/` (AppKit, só o plugin `analytics`): KPIs, projetos em risco com P(estouro), simulador |
| 2 · o agente de IA | `src/metricas/metricas.sql` (`mv_projetos`), tarefa `metricas_governadas`, `scripts/gerar_genie.py` + `resources/genie.genie_space.yml`; no fim, o plugin `genie` no app (aba Perguntar, `user_api_scopes: dashboards.genie`) |
| bônus · o modelo | `src/ml/` (features SQL, modelo e score em notebook), 3 tarefas `ml_*`, `gold.score_estouro_30d` (`bonus/prompt-modelo-ml.md`; ao vivo, só demonstrado) |
| bônus · aprovação | Lakebase + botão Aprovar/Recusar + tela Decisões (`bonus/prompt-aprovacao-lakebase.md`) |

**Ao vivo são 2 prompts: primeiro o app, depois o agente (que é plugado no app).** O modelo é demonstrado pelo instrutor; no repositório do aluno
o `gold.score_estouro_30d` **pode não existir**: o Genie só inclui a tabela se ela existir, e o app lê o
score por uma rota do servidor que responde `{disponivel:false}`. Nenhuma query de `config/queries` usa o score.

**Contrato do score** (o Genie e o app leem daqui; nome e tipo fixos):
`projeto_id STRING, data_referencia DATE, prob_estouro_30d DOUBLE, ranking INT, faixa_risco STRING, principais_fatores STRING`.
Projeto já abaixo de 0,9 na fotografia de hoje tem prob 1,0. Faixas: alto ≥ 0,5, medio ≥ 0,2, baixo.

**Onde fica cada coisa:** o laboratório (features, métricas, modelo) no schema `ml`; na `gold` só o
resultado (`score_estouro_30d`) e a metric view.

## 3. Armadilhas medidas neste workspace (Free Edition, outubro/2026)

### ML

| Armadilha | O que fazer |
|---|---|
| Registrar modelo no Unity Catalog falha (`s3:PutObject ... explicit deny`) | O serverless traz MLflow 2.11: `%pip install -U "mlflow-skinny[databricks]>=2.21,<3"` + `dbutils.library.restartPython()` na 1ª célula |
| XGBoost treina e não carrega de volta | `HistGradientBoostingRegressor` / `Classifier` do sklearn |
| `spark_udf` quebra no serverless (`InvalidVersion`) | `mlflow.sklearn.load_model("models:/...@prod")` + pandas |
| `mlflow.set_experiment` não cria a pasta pai | `WorkspaceClient().workspace.mkdirs(...)` antes |
| MLflow 2.x | `log_model(..., artifact_path="modelo")`, nunca `name=` |
| `Object of type Decimal is not JSON serializable` | `.astype(float)` antes do `input_example` |
| Célula de texto sem `# MAGIC %md` | vira código Python e quebra com `SyntaxError` |
| Janela nomeada com frame (`OVER (w ROWS BETWEEN ...)`) | `PARSE_SYNTAX_ERROR`: escreva a janela por extenso |
| Registro que falhou deixa versão órfã (`Function ... is not empty`) | `prd/99-limpar-modelo.sh` apaga as versões antes do modelo |

### Métricas e Genie

| Armadilha | O que fazer |
|---|---|
| Metric view pelo `aitools tools query` falha (`Missing required creator property 'expr'`) | O YAML perde a indentação: `sql_task` ou `python3 scripts/run_sql.py` |
| A `sql_task` corta o arquivo em todo `;`, inclusive dentro do `$$ ... $$` | Nada de `;` dentro do YAML da metric view (nem em comment) |
| O Genie do bundle falha com `Table ... does not exist` | O Genie precisa das tabelas existindo: deploy → run → deploy |
| Editar o Genie no workspace trava o `bundle deploy` ("modified remotely") | Leve a mudança para o `gerar_genie.py`; `--force` só depois |

### App

| Armadilha | O que fazer |
|---|---|
| **O Free Edition aceita no máximo 3 apps por workspace** (`reached the maximum limit of 3 apps`) | Antes do prompt 3, `databricks apps list`; apague um app que você não usa mais |
| O app dentro da pasta do bundle `vertice` | `sync: { exclude: ["minha-torre/**"] }` no `databricks.yml` da raiz, senão o deploy do vertice sobe o `node_modules` |
| `bundle deploy` cria o app **parado** | O deploy do código é `databricks apps deploy --profile <perfil>` (dentro da pasta do app) |
| O app é um **usuário do Unity Catalog** e nasce sem acesso | Depois do `bundle deploy`: `GRANT USE CATALOG`, `USE SCHEMA` e `SELECT` na gold e na silver para o service principal (`apps get` → `service_principal_client_id`). Sem isso o **build** falha no typegen com `INSUFFICIENT_PERMISSIONS` |
| Query em `config/queries/` com tabela inexistente **quebra o build** (typegen `--wait`) | Tabela que pode faltar (o score) é lida por uma rota do servidor que responde `{disponivel:false}` |
| `npm run typegen` fora do deploy dá `OFFLINE` em 0 s | Exporte o `.env` antes (`set -a; . ./.env; set +a`) e rode `npm run typegen -- --wait` |
| O warehouse devolve **todo número como string** | `Number()` antes de formatar; `z.coerce.number()` no servidor |
| Arquivo `*.geniespace.json` dentro da pasta do app | `Requested node type [UNKNOWN] is not supported`: nenhum JSON de Genie dentro do app |
| A 1ª visita ao app pede **consentimento OAuth** ("Permission Requested") | É esperado: o app pede para usar o Genie em seu nome. Authorize uma vez |
| Lakebase: o service principal **não enxerga o schema `public`** | O app cria o próprio schema (`torre`) na subida. Se você testou local antes (`npm run dev`), apague o schema `torre` que **você** criou antes do deploy |
| Lakebase apagado sem `--purge` prende o nome por 7 dias | `delete-project --purge`; confira com `list-projects`, não com `get-project` |

## 4. Convenções

- Nome do app: **≤ 26 caracteres**, minúsculas e hífen (`minha-torre`, `farol-torre`).
- Leitura = `config/queries/*.sql`. Escrita = rota do servidor + Lakebase, com validação zod
  (projeto `PRJ-000`, pessoa `COL0000`, tipo `pessoa`).
- Toda decisão grava o **e-mail de quem clicou** (header `x-forwarded-email`), não o service principal.
- Telas em português, números em `R$` e índices com 2 casas.
- `random_state=42` em todo modelo. Sempre `--profile <perfil>`.

## 5. Números que servem como teste (seed 42)

| O que | Valor |
|---|---|
| `ml.features_projeto_semana` · treino · taxa base | 4.235 linhas · 1.643 · 16,7% |
| Teste (a partir de 03/04/2026) | 580 projetos × semana, 70 terminaram o mês abaixo de 0,9 |
| AUC: regra da folga · classificador · **modelo** | 0,87 · 0,90 · **0,92** |
| Estouros avisados no top 5 · antecedência | **9 de 10** · **41 dias** |
| Score: alto · medio · baixo | 18 · 4 · 19 |
| O caso da noite | **PRJ-024**, ok hoje (SPI 0,91), 46% de chance; e-commerce, freeze a partir de 01/11 |
| Vazamento: corte no tempo · aleatório · com índice do futuro | 0,92 · 0,92 · **0,99** (barrado pelo `assert < 0,98`) |
| `mv_projetos`: SPI · CPI · estouro · críticos · melancias | 0,92 · 0,97 · R$ 6,47 mi · 7 · 4 |
| Genie "Farol · Diretoria" | 20/20 no `prd/genie-benchmark-diretoria.json` (18/10, antes do score) |
| App: em risco · críticos · melancias · estouro · alto risco em 30 dias | **17 de 41** · 7 · 4 · R$ 6,5 mi · 18 |
| SREs ociosos | COL0017 e COL0018 no PRJ-007, uso de 5 a 6% |
| PRJ-011 | 12 semanas com `falta_sre`, 57 dias de impacto declarados em 90 dias |
| Simulador COL0017 (PRJ-007) → PRJ-011 | 151 h no mês · R$ 30,1 mil de ociosidade evitada · 19,0 dias recuperados · onboarding R$ 8,0 mil · saldo R$ 22,1 mil |
