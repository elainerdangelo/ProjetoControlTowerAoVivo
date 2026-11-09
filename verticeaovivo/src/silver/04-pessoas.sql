-- silver.colaboradores e silver.apontamentos
-- Sujeira #16: COL0102, COL0257 e COL0433 estão cadastrados duas vezes (a cópia vem com
-- nome e papel em CAIXA ALTA). Fica o cadastro com o papel em minúsculas.

CREATE OR REFRESH MATERIALIZED VIEW colaboradores
COMMENT 'As 520 pessoas da Vértice, uma linha por colaborador_id: nome, papel (dev, qa, sre, product_owner...), senioridade, custo por hora, data de admissão e de desligamento (nula para quem está ativo).'
AS
WITH ranqueado AS (
  SELECT
    *,
    row_number() OVER (
      PARTITION BY colaborador_id
      ORDER BY CASE WHEN papel = lower(papel) THEN 0 ELSE 1 END   -- o cadastro em minúsculas primeiro
    ) AS ordem
  FROM lakehouse_vertice.bronze.colaboradores
)
SELECT
  colaborador_id,
  nome,
  lower(papel)                                  AS papel,
  senioridade,
  CAST(custo_hora AS DECIMAL(10, 2))            AS custo_hora,
  to_date(nullif(data_admissao, ''))            AS data_admissao,
  to_date(nullif(data_desligamento, ''))        AS data_desligamento
FROM ranqueado
WHERE ordem = 1;


-- O timesheet: horas disponíveis × apontadas por pessoa, projeto e semana.
CREATE OR REFRESH MATERIALIZED VIEW apontamentos
COMMENT 'Timesheet semanal: horas disponíveis e horas apontadas por colaborador e projeto. semana_inicio é a segunda-feira; semana é a sexta (semana_inicio + 4), a mesma data do status semanal.'
AS
SELECT
  colaborador_id,
  projeto_id,
  to_date(semana_inicio)                        AS semana_inicio,
  date_add(to_date(semana_inicio), 4)           AS semana,
  CAST(horas_disponiveis AS DOUBLE)             AS horas_disponiveis,
  CAST(horas_apontadas   AS DOUBLE)             AS horas_apontadas
FROM lakehouse_vertice.bronze.apontamentos;
