-- silver.projetos · o cadastro do PMO, que também é o DE-PARA da integração:
-- (ferramenta, codigo_ferramenta) diz em qual arquivo/lista estão as tarefas de cada projeto.
-- Sujeiras tratadas (CLAUDE.md, seção 3): #1 data em dois formatos, #2 ferramenta de 8 jeitos,
-- #3 código da ferramenta vazio.

CREATE OR REFRESH MATERIALIZED VIEW projetos (
  CONSTRAINT data_inicio_valida   EXPECT (data_inicio IS NOT NULL)                          ON VIOLATION FAIL UPDATE,
  CONSTRAINT ferramenta_conhecida EXPECT (ferramenta IN ('excel', 'clickup', 'msproject'))  ON VIOLATION FAIL UPDATE
)
COMMENT 'Cadastro dos 60 projetos da Vértice (PMO): cliente, segmento, contrato, orçamento, datas, gerente e a ferramenta onde o projeto é controlado (excel, clickup ou msproject) com o código nela (arquivo ou lista). É o de-para que liga as tarefas das três ferramentas ao projeto.'
AS
SELECT
  projeto_id,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,
  gerente_projeto,
  status,
  CAST(valor_contrato  AS DECIMAL(18, 2)) AS valor_contrato,
  CAST(orcamento_custo AS DECIMAL(18, 2)) AS orcamento_custo,
  -- #1: a data vem em yyyy-MM-dd ou dd/MM/yyyy
  coalesce(try_to_date(data_inicio, 'yyyy-MM-dd'), try_to_date(data_inicio, 'dd/MM/yyyy'))             AS data_inicio,
  coalesce(try_to_date(data_fim_baseline, 'yyyy-MM-dd'), try_to_date(data_fim_baseline, 'dd/MM/yyyy')) AS data_fim_baseline,
  -- #2: 'Excel', 'Planilha', 'Clickup', 'MS Project', 'Project'... viram 3 valores
  CASE
    WHEN lower(ferramenta) LIKE '%click%'                                   THEN 'clickup'
    WHEN lower(ferramenta) LIKE '%project%'                                 THEN 'msproject'
    WHEN lower(ferramenta) LIKE '%excel%' OR lower(ferramenta) LIKE '%planilha%' THEN 'excel'
  END                                     AS ferramenta,
  ferramenta                              AS ferramenta_como_veio,
  -- #3: código vazio vira NULL (a silver.tarefas cai no plano B: nome do arquivo / da lista)
  nullif(trim(codigo_ferramenta), '')     AS codigo_ferramenta
FROM lakehouse_vertice.bronze.projetos;
