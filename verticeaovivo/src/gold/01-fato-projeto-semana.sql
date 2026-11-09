-- gold.fato_projeto_semana · "está piorando?"
-- Grão: projeto × semana (sexta-feira), da semana do início até hoje (16/10/2026).
-- De onde vem o HISTÓRICO? Excel, ClickUp e Project só guardam o % de hoje. O único lugar com o %
-- de cada semana é o status que o gerente publica toda sexta: por isso o EV daqui usa o status.
-- PV, EV e AC são ACUMULADOS: o EV da semana 40 é tudo que ficou pronto até a semana 40.
-- Nunca some EV de semanas diferentes do mesmo projeto.

CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.fato_projeto_semana (
  CONSTRAINT pv_nao_negativo     EXPECT (pv >= 0)            ON VIOLATION FAIL UPDATE,
  CONSTRAINT ev_ate_o_orcamento  EXPECT (ev <= orcamento)    ON VIOLATION FAIL UPDATE
)
COMMENT 'Evolução semanal de cada projeto (uma linha por projeto e sexta-feira, do início até 16/10/2026): valor planejado (pv), valor agregado (ev, pelo % do status semanal do gerente), custo real acumulado (ac), SPI, CPI, EAC, o farol publicado pelo gerente e as horas disponíveis, apontadas e ociosas da semana. Valores em reais e acumulados até a semana.'
AS
WITH
-- 1 · uma linha por projeto e sexta-feira
semanas AS (
  SELECT
    projeto_id,
    orcamento_custo AS orcamento,
    explode(sequence(next_day(date_sub(data_inicio, 1), 'FRI'), DATE'2026-10-16', INTERVAL 1 WEEK)) AS semana
  FROM projetos
),

-- 2 · PV: quanto do trabalho (em horas) o baseline dizia que estaria pronto naquela sexta
pv_semana AS (
  SELECT
    s.projeto_id,
    s.semana,
    s.orcamento * SUM(t.horas * greatest(0, least(1,
        coalesce(try_divide(datediff(s.semana, t.inicio_baseline), datediff(t.fim_baseline, t.inicio_baseline)), 0)
    ))) / SUM(t.horas)                                                      AS pv
  FROM semanas s
  JOIN tarefas t ON t.projeto_id = s.projeto_id
  GROUP BY s.projeto_id, s.semana, s.orcamento
),

-- 3 · o % e o farol do status. Projeto concluído para de publicar: o último valor vale
--     para as semanas seguintes (a janela fica neste CTE; a conta vem no próximo)
status_preenchido AS (
  SELECT
    s.projeto_id,
    s.semana,
    last_value(st.pct_concluido, true) OVER (PARTITION BY s.projeto_id ORDER BY s.semana) AS pct_status,
    last_value(st.farol, true)         OVER (PARTITION BY s.projeto_id ORDER BY s.semana) AS farol_do_gerente
  FROM semanas s
  LEFT JOIN status_semanal st
    ON st.projeto_id = s.projeto_id AND st.data_status = s.semana
),

-- 4 · AC: todo custo lançado até aquela sexta (inclui os lançados antes do início formal)
ac_semana AS (
  SELECT s.projeto_id, s.semana, SUM(c.valor) AS ac
  FROM semanas s
  JOIN custos c ON c.projeto_id = s.projeto_id AND c.semana <= s.semana
  GROUP BY s.projeto_id, s.semana
),

-- 5 · as horas do timesheet na semana (não acumuladas)
horas_semana AS (
  SELECT
    projeto_id,
    semana,
    SUM(horas_disponiveis) AS horas_disponiveis,
    SUM(horas_apontadas)   AS horas_apontadas
  FROM apontamentos
  GROUP BY projeto_id, semana
),

kpis AS (
  SELECT
    s.projeto_id,
    s.semana,
    s.orcamento,
    round(coalesce(pv.pv, 0), 2)                                AS pv,
    round(s.orcamento * coalesce(sp.pct_status, 0) / 100, 2)    AS ev,
    round(coalesce(ac.ac, 0), 2)                                AS ac,
    sp.pct_status,
    sp.farol_do_gerente,
    coalesce(h.horas_disponiveis, 0)                            AS horas_disponiveis,
    coalesce(h.horas_apontadas, 0)                              AS horas_apontadas
  FROM semanas s
  LEFT JOIN pv_semana         pv ON pv.projeto_id = s.projeto_id AND pv.semana = s.semana
  LEFT JOIN status_preenchido sp ON sp.projeto_id = s.projeto_id AND sp.semana = s.semana
  LEFT JOIN ac_semana         ac ON ac.projeto_id = s.projeto_id AND ac.semana = s.semana
  LEFT JOIN horas_semana      h  ON h.projeto_id  = s.projeto_id AND h.semana  = s.semana
)
SELECT
  projeto_id,
  semana,
  orcamento,
  pv,
  ev,
  ac,
  round(try_divide(ev, pv), 4)                                   AS spi,
  round(try_divide(ev, ac), 4)                                   AS cpi,
  round(try_divide(orcamento, round(try_divide(ev, ac), 4)), 2)  AS eac,
  pct_status,
  farol_do_gerente,
  horas_disponiveis,
  horas_apontadas,
  horas_disponiveis - horas_apontadas                            AS horas_ociosas
FROM kpis;
