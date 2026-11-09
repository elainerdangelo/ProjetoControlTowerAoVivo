-- silver.tarefas · AS TRÊS FERRAMENTAS VIRAM UMA
-- A integração é um CONTRATO DE COLUNAS: cada ferramenta vira uma visão temporária com as
-- MESMAS 13 colunas, e as três são empilhadas (UNION ALL). Ferramenta nova = mais uma visão.
--   projeto_id, ferramenta, id_na_ferramenta, fase, tarefa, responsavel,
--   inicio_baseline, fim_baseline, inicio_real, fim_real, pct_como_veio, horas, status_na_ferramenta
-- Quem diz a qual projeto pertence cada arquivo/lista é o cadastro do PMO (silver.projetos).


-- ─── 1 · Excel: 20 planilhas, tudo texto ─────────────────────────────────────────────
-- Sujeiras #4 (data em texto OU número de série), #5 (% em 3 formatos), #6 (linha TOTAL), #7 ('40h')
CREATE TEMPORARY VIEW tarefas_excel AS
WITH bruto AS (
  SELECT
    -- de-para pelo nome do arquivo; se não casar (código vazio, ou o arquivo chegou sem acento:
    -- 'Core bancario' × 'Core bancário'), o PRJ-xxx que está no próprio nome do arquivo
    coalesce(p.projeto_id, regexp_extract(e.arquivo, 'PRJ-[0-9]{3}', 0)) AS projeto_id,
    e.*
  FROM lakehouse_vertice.bronze.excel_tarefas e
  LEFT JOIN projetos p
    ON p.ferramenta = 'excel' AND p.codigo_ferramenta = e.arquivo
  WHERE e.tarefa <> 'TOTAL'                     -- #6: a linha de TOTAL dobraria as horas
)
SELECT
  projeto_id,
  'excel'                                        AS ferramenta,
  CAST(id AS STRING)                             AS id_na_ferramenta,
  fase,
  tarefa,
  nullif(trim(responsavel), '')                  AS responsavel,
  -- #4: com '/' é dd/MM/yyyy; senão é o número de série do Excel (dias desde 30/12/1899)
  CASE WHEN inicio_previsto LIKE '%/%' THEN to_date(inicio_previsto, 'dd/MM/yyyy')
       WHEN nullif(inicio_previsto, '') IS NOT NULL
       THEN date_add(DATE'1899-12-30', CAST(CAST(inicio_previsto AS DOUBLE) AS INT)) END   AS inicio_baseline,
  CASE WHEN termino_previsto LIKE '%/%' THEN to_date(termino_previsto, 'dd/MM/yyyy')
       WHEN nullif(termino_previsto, '') IS NOT NULL
       THEN date_add(DATE'1899-12-30', CAST(CAST(termino_previsto AS DOUBLE) AS INT)) END  AS fim_baseline,
  CASE WHEN inicio_real LIKE '%/%' THEN to_date(inicio_real, 'dd/MM/yyyy')
       WHEN nullif(inicio_real, '') IS NOT NULL
       THEN date_add(DATE'1899-12-30', CAST(CAST(inicio_real AS DOUBLE) AS INT)) END       AS inicio_real,
  CASE WHEN termino_real LIKE '%/%' THEN to_date(termino_real, 'dd/MM/yyyy')
       WHEN nullif(termino_real, '') IS NOT NULL
       THEN date_add(DATE'1899-12-30', CAST(CAST(termino_real AS DOUBLE) AS INT)) END      AS fim_real,
  -- #5: '45%' e '10,5%' → tira o % e troca a vírgula; sem % (0.45) é fração → × 100
  CASE WHEN contains(pct_concluido, '%')
       THEN CAST(replace(replace(pct_concluido, '%', ''), ',', '.') AS DOUBLE)
       ELSE CAST(replace(pct_concluido, ',', '.') AS DOUBLE) * 100 END                     AS pct_como_veio,
  -- #7: '40h' → 40
  CAST(replace(horas_previstas, 'h', '') AS DOUBLE)                                        AS horas,
  -- a planilha não tem coluna de status: a MV tarefas deriva do %
  CAST(NULL AS STRING)                                                                    AS status_na_ferramenta
FROM bruto;


-- ─── 2 · ClickUp: 25 listas, datas em milissegundos, campos dentro de custom_fields ─────
-- Sujeiras #3 (código da lista vazio), #8 (ms + custom_fields), #9 (status de 12 jeitos)
CREATE TEMPORARY VIEW tarefas_clickup AS
SELECT
  -- de-para pelo list_id; se o código faltar no cadastro, casa pelo nome da lista
  coalesce(p_cod.projeto_id, p_nome.projeto_id)                                            AS projeto_id,
  'clickup'                                                                                AS ferramenta,
  c.id                                                                                     AS id_na_ferramenta,
  filter(c.custom_fields, f -> f.name = 'Fase')[0].value                                   AS fase,
  c.name                                                                                   AS tarefa,
  c.assignees[0].username                                                                  AS responsavel,
  to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Início baseline')[0].value AS BIGINT))) AS inicio_baseline,
  to_date(timestamp_millis(CAST(filter(c.custom_fields, f -> f.name = 'Fim baseline')[0].value    AS BIGINT))) AS fim_baseline,
  to_date(timestamp_millis(CAST(nullif(c.start_date, '') AS BIGINT)))                       AS inicio_real,
  to_date(timestamp_millis(CAST(nullif(c.date_done, '')  AS BIGINT)))                       AS fim_real,
  CAST(filter(c.custom_fields, f -> f.name = 'Progresso (%)')[0].value AS DOUBLE)          AS pct_como_veio,
  c.time_estimate / 3600000.0                                                              AS horas,       -- ms → horas
  -- #9: Done/done/concluído/closed · to do/backlog/a fazer · in progress/em andamento/review/doing
  CASE
    WHEN lower(trim(c.status.status)) IN ('done', 'closed')
      OR lower(trim(c.status.status)) LIKE 'conclu%'                                      THEN 'concluida'
    WHEN lower(trim(c.status.status)) IN ('to do', 'backlog', 'a fazer')                   THEN 'a_fazer'
    WHEN lower(trim(c.status.status)) IN ('in progress', 'em andamento', 'review', 'doing') THEN 'em_andamento'
  END                                                                                      AS status_na_ferramenta
FROM lakehouse_vertice.bronze.clickup_tarefas c
LEFT JOIN projetos p_cod
  ON p_cod.ferramenta = 'clickup' AND p_cod.codigo_ferramenta = c.list_id
LEFT JOIN projetos p_nome
  ON p_nome.ferramenta = 'clickup' AND p_nome.codigo_ferramenta IS NULL AND p_nome.nome_projeto = c.list_name;


-- ─── 3 · MS Project: 15 cronogramas XML ──────────────────────────────────────────────
-- Sujeiras #10 (tarefas-resumo somam as de baixo), #11 (a fase não está na tarefa), #12 ('PT40H0M0S')
CREATE TEMPORARY VIEW tarefas_msproject AS
WITH com_fase AS (
  -- a fase é a última tarefa-resumo de nível 1 que aparece antes da tarefa (na ordem do UID).
  -- A janela roda ANTES do filtro Summary = 0, senão as linhas de fase sumiriam.
  SELECT
    m.*,
    last_value(CASE WHEN m.OutlineLevel = 1 THEN m.Name END, true)
      OVER (PARTITION BY m.arquivo ORDER BY m.UID) AS fase
  FROM lakehouse_vertice.bronze.msproject_tarefas m
)
SELECT
  p.projeto_id,
  'msproject'                                                     AS ferramenta,
  CAST(f.UID AS STRING)                                           AS id_na_ferramenta,
  f.fase,
  f.Name                                                          AS tarefa,
  CAST(NULL AS STRING)                                            AS responsavel,   -- o XML não traz
  to_date(f.Baseline.Start)                                       AS inicio_baseline,
  to_date(f.Baseline.Finish)                                      AS fim_baseline,
  to_date(f.ActualStart)                                          AS inicio_real,
  to_date(f.ActualFinish)                                         AS fim_real,
  CAST(f.PercentComplete AS DOUBLE)                               AS pct_como_veio,
  CAST(regexp_extract(f.Work, 'PT([0-9]+)H', 1) AS DOUBLE)        AS horas,         -- 'PT40H0M0S' → 40
  CAST(NULL AS STRING)                                            AS status_na_ferramenta
FROM com_fase f
LEFT JOIN projetos p
  ON p.ferramenta = 'msproject' AND p.codigo_ferramenta = f.arquivo
WHERE f.Summary = 0;                                              -- #10: só as tarefas de verdade


-- ─── 4 · A tabela única ──────────────────────────────────────────────────────────────
CREATE OR REFRESH MATERIALIZED VIEW tarefas (
  CONSTRAINT achou_o_projeto   EXPECT (projeto_id IS NOT NULL)            ON VIOLATION FAIL UPDATE,
  CONSTRAINT pct_entre_0_e_100 EXPECT (pct_concluido BETWEEN 0 AND 100)   ON VIOLATION FAIL UPDATE,
  CONSTRAINT horas_positivas   EXPECT (horas > 0)                         ON VIOLATION FAIL UPDATE
)
COMMENT 'Todas as tarefas dos 60 projetos num modelo só: integra as 20 planilhas Excel, as 25 listas do ClickUp e os 15 cronogramas do MS Project. Uma linha por tarefa (tarefa_id = projeto-ferramenta-id), com fase, responsável, datas de baseline e reais, % concluído (limitado a 100, com a flag pct_veio_acima_de_100), horas previstas e status (concluida, a_fazer, em_andamento). Sem a linha de TOTAL do Excel e sem as tarefas-resumo do Project.'
AS
WITH todas AS (
  SELECT * FROM tarefas_excel
  UNION ALL
  SELECT * FROM tarefas_clickup
  UNION ALL
  SELECT * FROM tarefas_msproject
)
SELECT
  concat_ws('-', projeto_id, ferramenta, id_na_ferramenta)  AS tarefa_id,
  projeto_id,
  ferramenta,
  id_na_ferramenta,
  fase,
  tarefa,
  responsavel,
  inicio_baseline,
  fim_baseline,
  inicio_real,
  fim_real,
  pct_como_veio,
  least(pct_como_veio, 100)                                 AS pct_concluido,
  pct_como_veio > 100                                       AS pct_veio_acima_de_100,
  horas,
  -- Excel e Project não têm coluna de status: deriva do % (o ClickUp traz o dele)
  coalesce(status_na_ferramenta,
           CASE WHEN pct_como_veio >= 100 THEN 'concluida'
                WHEN pct_como_veio  = 0   THEN 'a_fazer'
                ELSE 'em_andamento' END)                    AS status
FROM todas;
