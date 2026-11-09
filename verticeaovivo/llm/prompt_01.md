# Prompt 1 · Silver — as três ferramentas viram uma

**Entrega:** o pipeline declarativo `vertice_medalhao` com a silver: o cadastro do
PMO, a **`silver.tarefas` que integra Excel, ClickUp e MS Project**, e as outras
cinco tabelas limpas e tipadas (7 no total), com as regras de qualidade declaradas como `EXPECT`.
Começa pela **conferência da bronze** (a primeira tarefa nova do job). **Deploy nº 2.**

> **A entrega mais importante da noite. Não corte.**

---

## Antes de colar: o Claude Code em 5 minutos

O Claude Code é uma conversa dentro do terminal: você escreve em português, ele lê os arquivos da
pasta, escreve código e roda comandos, sempre pedindo licença antes (a não ser no modo auto). Tudo
que começa com `/` é um comando dele; o resto é conversa.

| Digite | O que acontece | Exemplo |
|---|---|---|
| `/model` | abre a lista de modelos. Opus pensa melhor, Sonnet é mais rápido | `/model` → escolha com as setas → Enter |
| `Shift+Tab` | troca o **modo**. Cada aperto passa para o próximo; o rodapé da tela mostra qual está ligado (veja abaixo) | aperte até aparecer `plan mode on` |
| `@` + nome do arquivo | anexa o arquivo à sua mensagem: ele lê antes de responder. Ao digitar `@` aparece a lista de arquivos | `explique a seção 3 do @CLAUDE.md em 3 linhas` |
| `!` + comando | roda o comando **no seu terminal**, sem sair do Claude Code, e a saída entra na conversa (ele vê o resultado) | `! databricks bundle validate --profile DEFAULT` |
| `Esc` | para o que ele está fazendo agora | ele começou a fazer algo errado → `Esc` → corrija em português |
| `Esc` `Esc` (ou `/rewind`) | mostra as mensagens anteriores: escolha uma e ele volta a conversa **e os arquivos** para aquele ponto | desfazer um prompt inteiro |
| `/context` | quanto da "memória" da conversa já foi usada | se passar de ~80%, `/clear` entre um prompt e outro |
| `/clear` | começa uma conversa nova. O `CLAUDE.md` continua valendo | entre o prompt 2 e o 3, se a conversa ficou longa |
| `/voice` | dita a mensagem em vez de digitar (se aparecer na sua versão) | `/voice` → fale → Enter |
| `/help` · `/exit` | a lista de todos os comandos · sair | |

**Os modos (o `Shift+Tab`):**

| Rodapé | Modo | Quando usar |
|---|---|---|
| (nada) | **normal**: pede licença a cada arquivo e a cada comando | para entender o que ele faz, passo a passo |
| `accept edits on` | edita arquivos sem perguntar; comando ainda pede licença | quando você já confia no plano |
| `plan mode on` | **só planeja**: lê, pensa e devolve um plano, sem mexer em nada | antes de um prompt grande (o prompt 1) |
| `auto mode` | faz tudo sozinho; um verificador barra o que for perigoso | depois de aprovar o plano |

**Não rode `/init`.** O `/init` escreve um `CLAUDE.md` novo, resumindo a pasta. O nosso já existe e
é o PRD do curso (o negócio, as sujeiras do dado, as armadilhas do Free Edition): o prompt 1 baixa
e lê esse arquivo. O `/init` jogaria isso fora.

**O ritmo da noite:**

1. **Prompt 1 em plan.** `Shift+Tab` até `plan mode on`, cole o prompt. Ele lê o `CLAUDE.md` e o
   bundle e devolve um plano. Leia com a turma: arrumou o bundle (sem `mode: development`, job
   `vertice_farol`, pausado)? Tirou a linha de TOTAL, as tarefas-resumo, a vírgula decimal? Se
   faltar algo, escreva a correção antes de aprovar.
2. **Aprove e vá para auto.** Ele executa sozinho até o deploy e o run.
3. **Quando o auto recusar** ("Credential Leakage", "Irreversible Deletion"): não é erro. Ele barrou
   um comando que mexe com chave ou apaga dado, e mostra qual é. Rode você, com `!` na frente.
4. **Prompts 2 a 4 direto em auto.** O plano do 1 ensinou o caminho.

---

## O que mostrar antes

O rascunho da noite 1 (`bronze.rascunho_tarefas`) funcionou. Mostre por que ele não
serve como produto, com número:

```sql
-- 1 · a view da noite 1 mora dentro de uma query: se alguém esquecer a linha de TOTAL...
SELECT SUM(CAST(horas_previstas AS DOUBLE)) AS com_total,
       SUM(CAST(horas_previstas AS DOUBLE)) FILTER (WHERE tarefa <> 'TOTAL') AS sem_total
FROM lakehouse_vertice.bronze.excel_tarefas
WHERE horas_previstas NOT LIKE '%h';
-- o Excel inteiro "dobra" de tamanho

-- 2 · ...ou as tarefas-resumo do Project
SELECT Summary, SUM(CAST(regexp_extract(Work, 'PT([0-9]+)H', 1) AS DOUBLE)) AS horas
FROM lakehouse_vertice.bronze.msproject_tarefas GROUP BY Summary;
-- as tarefas-resumo somam o DOBRO das tarefas de verdade

-- 3 · a vírgula decimal: o try_cast "funciona" e joga 671 lançamentos fora em silêncio
SELECT ROUND(SUM(try_cast(valor AS DECIMAL(18,2))) / 1e6, 2) AS errado,
       ROUND(SUM(CAST(replace(valor, ',', '.') AS DECIMAL(18,2))) / 1e6, 2) AS certo
FROM lakehouse_vertice.bronze.custos;
-- 187,94 × 193,35: R$ 5,4 milhões sumiram sem erro nenhum

-- 4 · a mesma consultoria, quatro fornecedores
SELECT fornecedor, COUNT(*) FROM lakehouse_vertice.bronze.entregas_fornecedor
WHERE lower(fornecedor) LIKE '%forge%' GROUP BY 1;
```

**Enquanto ele trabalha, você explica:**

- **Declarativo é dizer O QUE, não COMO.** Cada arquivo diz "a silver.tarefas é
  isto". O Lakeflow lê os `FROM`, descobre a ordem, roda em paralelo o que dá e
  desenha o grafo. Você não escreve orquestração.
- **A integração é um contrato de colunas.** Cada ferramenta vira uma visão com as
  MESMAS colunas (projeto, fase, tarefa, baseline, realizado, %, horas) e as três são
  empilhadas. A ferramenta nova que aparecer amanhã é só mais uma visão.
- **O de-para é dado, não código.** Quem diz que a lista 901200095028 do ClickUp é o
  PRJ-012 é o cadastro do PMO (`silver.projetos`). Quando o código falta, o pipeline
  casa pelo nome — e o `EXPECT achou_o_projeto` garante que nenhuma tarefa ficou órfã.
- **`EXPECT ... ON VIOLATION FAIL UPDATE` é contrato.** Se amanhã um gerente digitar
  "Planilha Google" como ferramenta, o pipeline para em vez de gravar nulo. A regra é
  da tabela, não do script que rodou naquele dia.

---

## O prompt

```
Use as skills databricks-core, databricks-dabs e databricks-pipelines.
Sempre --profile DEFAULT.

Primeiro, o contexto do curso: troque o CLAUDE.md da raiz (o do template)
por este, e leia antes de continuar:
  curl -fsSL -o CLAUDE.md https://raw.githubusercontent.com/lvgalvao/ImersaoControlTower/main/aulas/aula-03-modelagem-claude-code/claude-code/prd/CLAUDE.md
  mkdir -p scripts && curl -fsSL -o scripts/run_sql.py https://raw.githubusercontent.com/lvgalvao/ImersaoControlTower/main/scripts/run_sql.py

O bundle vertice está na raiz: eu criei à mão com bundle init
default-minimal e importei o job de ontem com bundle generate
(resources/ingestão.job.yml, com as chaves do data lake já em variáveis).
NÃO mexa nos valores das chaves, nem no
.databricks/bundle/dev/variable-overrides.json, nem no catálogo e nos
schemas (já existem). Se um comando for recusado por causa das chaves,
pare e me mostre o comando para eu rodar com `!`.

Confira antes: o databricks.yml está na pasta onde você abriu, e existe
resources/*.job.yml com as chaves em ${var.…}. Se faltar, NÃO rode o
bundle generate (ele grava as chaves em texto): pare e me diga qual passo
do bundle-na-mao.md refazer.

Antes de tudo, arrume o bundle:
- databricks.yml: tire o mode: development do target dev (ele prefixa os
  nomes) e ponha presets: trigger_pause_status: PAUSED. Variáveis catalog
  (default lakehouse_vertice) e warehouse_id (descubra com
  databricks warehouses list); saem as variáveis catalog/schema do template.
  Mova os dois notebooks que o generate pôs em src/ para src/ingestao/
  (ajuste o notebook_path). Deixe fixtures/ e tests/ do template onde estão.
- o job: renomeie o arquivo para resources/vertice.job.yml, a chave e o
  name para vertice_farol, as tarefas para ingestao_feriados (a da API) e
  ingestao_data_lake (a do boto3), e schedule.pause_status para PAUSED. O
  bloco variables das duas chaves pode ir para o databricks.yml.
- depois do deploy, pause o agendamento do job antigo "Ingestão" (dois jobs
  recarregando a mesma bronze às 6h brigam). Não apague.

0. Antes da silver, a conferência da bronze: src/conferencia/00-conferencia-bronze.sql,
   sql_task no warehouse ${var.warehouse_id}, tarefa conferencia_bronze no job,
   depois das duas ingestões. Confere as 9 tabelas contra a contagem esperada
   (seed 42): projetos 60 · status_semanal 3911 · excel_tarefas 1663 ·
   clickup_tarefas 2119 · msproject_tarefas 1260 · colaboradores 523 ·
   apontamentos 30883 · custos 23640 · entregas_fornecedor 640
   (bronze.feriados fica de fora: cresce a cada execução). Uma linha por
   tabela com esperado e obtido; se alguma divergir, raise_error() dizendo
   qual tabela e onde olhar (a saída da tarefa ingestao_data_lake).

Agora a silver: integrar as três ferramentas, limpar, tipar e declarar o
contrato.

Crie um pipeline Lakeflow Spark Declarative Pipelines em SQL:
resources/vertice_medalhao.pipeline.yml com name vertice_medalhao, catalog
${var.catalog}, schema silver, serverless: true, photon: true, e libraries com
um glob em ../src/silver/** (o prompt 2 vai acrescentar ../src/gold/**).

Use CREATE OR REFRESH MATERIALIZED VIEW (nunca CREATE OR REPLACE, que não
existe no pipeline) e CREATE TEMPORARY VIEW para as visões intermediárias.
Leia a bronze pelo nome completo lakehouse_vertice.bronze.<tabela>; dentro do
pipeline, referencie as tabelas silver só pelo nome. COMMENT em toda tabela.
Siga a tabela de sujeiras da seção 3 do CLAUDE.md.

Um arquivo por assunto em src/silver/:

01-projetos.sql — o cadastro do PMO (é o de-para da integração)
- data_inicio em yyyy-MM-dd e dd/MM/yyyy: coalesce de dois try_to_date.
- ferramenta escrita de 8 jeitos → 'excel', 'clickup' ou 'msproject'
  (guarde ferramenta_como_veio). codigo_ferramenta vazio → NULL.
- EXPECT data_inicio IS NOT NULL e ferramenta IN (...), FAIL UPDATE.

02-tarefas.sql — AS TRÊS FERRAMENTAS VIRAM UMA
Três CREATE TEMPORARY VIEW com as MESMAS colunas (projeto_id, ferramenta,
id_na_ferramenta, fase, tarefa, responsavel, inicio_baseline, fim_baseline,
inicio_real, fim_real, pct_como_veio, horas, status_na_ferramenta):
- tarefas_excel: projeto pelo de-para (codigo_ferramenta = arquivo) e, se não
  casar (código vazio, ou o arquivo chegou sem acento: 'Core bancario' ×
  'Core bancário'), o PRJ-xxx do nome do arquivo:
  coalesce(p.projeto_id, regexp_extract(arquivo, 'PRJ-[0-9]{3}', 0)). Datas: com '/' é dd/MM/yyyy,
  senão é número de série do Excel: date_add(DATE'1899-12-30', CAST(x AS INT)).
  %: com '%' tire o '%' e troque vírgula por ponto; sem '%' é fração (× 100).
  Horas: tire o 'h'. TIRE a linha onde tarefa = 'TOTAL'.
- tarefas_clickup: projeto pelo de-para (codigo_ferramenta = list_id) e, se o
  código faltar, pelo nome da lista. Datas em milissegundos:
  to_date(timestamp_millis(CAST(x AS BIGINT))). % e baseline estão em
  custom_fields: filter(custom_fields, f -> f.name = 'Progresso (%)')[0].value
  (e 'Início baseline', 'Fim baseline', 'Fase'). Horas = time_estimate / 3600000.
  Status de 12 jeitos → concluida / a_fazer / em_andamento.
- tarefas_msproject: projeto pelo de-para (codigo_ferramenta = arquivo). Só
  Summary = 0 (as tarefas-resumo somam as de baixo). A fase é a última
  tarefa-resumo de OutlineLevel 1 antes da tarefa:
  last_value(CASE WHEN OutlineLevel = 1 THEN Name END, true) OVER (PARTITION
  BY arquivo ORDER BY UID). Baseline.Start/Finish, ActualStart/ActualFinish,
  PercentComplete, horas de 'PT40H0M0S'.
MATERIALIZED VIEW tarefas = UNION ALL das três, com tarefa_id
(projeto-ferramenta-id), pct_concluido = least(pct_como_veio, 100) e a flag
pct_veio_acima_de_100. EXPECT projeto_id IS NOT NULL (achou_o_projeto),
pct entre 0 e 100 e horas > 0, todos FAIL UPDATE.

03-status-e-custos.sql
- status_semanal: data_status DATE, farol em minúsculas (EXPECT farol IN
  ('verde','amarelo','vermelho') FAIL UPDATE), pct_concluido INT, flag
  status_vazio ('', 'N/A', 'ver ata da reunião') — NÃO descarte.
- custos: valor com 671 vírgulas decimais: replace(',', '.') ANTES do CAST,
  nunca try_cast. estorno (negativo) FICA, com a coluna estorno. semana =
  sexta da semana: date_add(date_trunc('WEEK', data), 4).

04-pessoas.sql
- colaboradores: COL0102, COL0257 e COL0433 aparecem duas vezes (nome e papel
  em CAIXA ALTA). Mantenha o cadastro com papel em minúsculas (row_number).
- apontamentos com semana = semana_inicio + 4 (sexta).

05-fornecedores.sql — entregas_fornecedor: a CodeForge vem de 4 jeitos
('CodeForge Consultoria Ltda', 'Codeforge Consultoria', 'CODEFORGE CONSULTORIA
LTDA', 'Code Forge Consultoria'): normalize (replace(lower(x), ' ', '') LIKE
'%codeforge%') e guarde fornecedor_como_veio. data_entrega vazia = em aberto
(não é sujeira). prazo_prometido_dias, prazo_real_dias,
dias_de_atraso_na_entrega, em_aberto e em_atraso (em aberto e data_prometida
antes de DATE'2026-10-16').

São 7 tabelas na silver, nem uma a mais: projetos, tarefas, status_semanal,
custos, colaboradores, apontamentos e entregas_fornecedor.

Acrescente ao job vertice_farol a tarefa medalhao (pipeline_task apontando
para ${resources.pipelines.vertice_medalhao.id}), depois de conferencia_bronze.

Trabalhe direto, sem testar cada SELECT antes do deploy: o EXPECT e o
pipeline são o teste. Se o pipeline falhar, leia o PRIMEIRO erro do evento,
corrija e rode de novo. Nunca dispare um run com outro ainda ativo: o Free
Edition tem limite de compute serverless (RESOURCE_EXHAUSTED).

Rode e me mostre a saída (a bronze já está carregada: a ingestão fica para
o prompt 3):
  databricks bundle validate --profile DEFAULT
  databricks bundle deploy --profile DEFAULT
  databricks bundle run vertice_farol --only conferencia_bronze,medalhao --profile DEFAULT
E no fim, numa tabela: cada tarefa, quanto tempo levou e o resultado.
```

---

## O que conferir

```sql
-- as três ferramentas, num modelo só
SELECT ferramenta, COUNT(DISTINCT projeto_id) AS projetos, COUNT(*) AS tarefas
FROM lakehouse_vertice.silver.tarefas GROUP BY 1;
-- excel 20 · 1.643 | clickup 25 · 2.119 | msproject 15 · 1.155

-- a limpeza NÃO mudou o custo: o mesmo número da noite 1
SELECT ROUND(SUM(valor) / 1e6, 2) FROM lakehouse_vertice.silver.custos;               -- 193,35

SELECT COUNT(*), COUNT(DISTINCT colaborador_id) FROM lakehouse_vertice.silver.colaboradores;   -- 520 e 520
SELECT fornecedor, COUNT(DISTINCT fornecedor_como_veio) FROM lakehouse_vertice.silver.entregas_fornecedor
WHERE fornecedor LIKE 'CodeForge%' GROUP BY 1;                                         -- 1 fornecedor, 4 grafias
SELECT COUNT_IF(pct_veio_acima_de_100) FROM lakehouse_vertice.silver.tarefas;             -- 11
```

Abra o pipeline no workspace: o grafo com as três visões temporárias desaguando em
`tarefas` e, em cada tabela, a aba **Data quality** mostrando quantas linhas cada
`EXPECT` avaliou.

> *"Juntei vinte planilhas, vinte e cinco listas do ClickUp e quinze cronogramas do
> Project numa tabela só. Nenhuma tarefa ficou sem projeto, e o custo total não mudou
> um centavo. É esse o teste."*

---

## Se der errado

| Sintoma | Causa | Correção |
|---|---|---|
| `RESOURCE_EXHAUSTED: You've hit the limit for serverless compute` | Dois runs ao mesmo tempo (o pipeline tenta de novo sozinho depois de uma falha) | Espere o run ativo terminar (`databricks pipelines list-updates`) e rode uma vez só |
| `EXPECT achou_o_projeto` falhou com projeto_id nulo no Excel | O arquivo chegou sem acento e não casou com o cadastro | `coalesce(p.projeto_id, regexp_extract(arquivo, 'PRJ-[0-9]{3}', 0))` |
| `CREATE OR REPLACE ... not supported` | Sintaxe de SQL comum dentro do pipeline | `CREATE OR REFRESH MATERIALIZED VIEW` / `CREATE TEMPORARY VIEW` |
| Pipeline falha em `achou_o_projeto` | Algum arquivo não casou com o cadastro do PMO | Confira o fallback: nome do arquivo (Excel) e nome da lista (ClickUp) |
| Pipeline falha em `pct_entre_0_e_100` | Faltou o `least(…, 100)` ou o % fracionário não foi × 100 | É o `EXPECT` funcionando: corrija a regra, não o EXPECT |
| `CAST_INVALID_INPUT '45661.0'` | Número de série do Excel com casa decimal | `CAST(CAST(x AS DOUBLE) AS INT)` |
| `Cannot resolve Baseline.Start` | A bronze do Project foi lida com `inferColumnTypes => false` | Na noite 1 o XML entra com inferência ligada (é o que mantém a struct) |
| `Update is WAITING_FOR_RESOURCES` por 1 min | Serverless acordando | Normal na primeira execução |

**Tempo medido (21/10):** com `--only conferencia_bronze,medalhao`, ~2 min 30 s de run (conferência 4 s, medalhão 2 min 22 s). No ensaio sem o `--only` e sem a regra do acento, o prompt levou ~15 min: 5 min de ingestão desnecessária e ~4 min de erro e conserto.
