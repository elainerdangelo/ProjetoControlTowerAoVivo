-- gold.projeto_situacao_atual · "quais projetos estão atrasados, de quais clientes, e quanto vai custar?"
-- gold.utilizacao_pessoa_semana · "tenho gente parada enquanto outro projeto pede gente?"
-- A fotografia de hoje usa o % das TAREFAS (as três ferramentas). O fato semanal usa o status.
-- Hoje = 16/10/2026. Regras de corte: SPI ou CPI < 0,9 = atenção; < 0,8 = crítico.

CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.projeto_situacao_atual
COMMENT 'Fotografia de 16/10/2026 dos 60 projetos, uma linha por projeto: o cadastro (cliente, segmento, tipo, ferramenta, gerente, contrato, orçamento, prazo baseline) e os KPIs calculados sobre as tarefas das três ferramentas: PV, EV, AC, SPI, CPI, EAC, estouro previsto, margem projetada, atraso e término projetados. situacao = concluído, crítico (SPI ou CPI < 0,8), atenção (< 0,9) ou ok. Traz o farol do gerente ao lado do farol calculado pelo SPI; melancia = farol do gerente verde com SPI < 0,9.'
AS
WITH
-- PV e EV de hoje, ponderados pelas horas de cada tarefa
tarefas_hoje AS (
  SELECT
    projeto_id,
    SUM(horas)                                                       AS horas_totais,
    SUM(horas * greatest(0, least(1, coalesce(
      try_divide(datediff(DATE'2026-10-16', inicio_baseline), datediff(fim_baseline, inicio_baseline)), 0))))
                                                                     AS horas_planejadas,
    SUM(horas * pct_concluido / 100)                                 AS horas_agregadas
  FROM tarefas
  GROUP BY projeto_id
),
custo_hoje AS (
  SELECT projeto_id, SUM(valor) AS ac
  FROM custos
  WHERE data <= DATE'2026-10-16'
  GROUP BY projeto_id
),
farol_hoje AS (
  -- um status por projeto na sexta de hoje (os concluídos não publicam mais: fica nulo)
  SELECT projeto_id, farol AS farol_do_gerente
  FROM status_semanal
  WHERE data_status = DATE'2026-10-16'
),
kpis AS (
  SELECT
    p.*,
    datediff(p.data_fim_baseline, p.data_inicio)                              AS duracao_baseline_dias,
    round(p.orcamento_custo * t.horas_planejadas / t.horas_totais, 2)         AS pv,
    round(p.orcamento_custo * t.horas_agregadas  / t.horas_totais, 2)         AS ev,
    round(coalesce(c.ac, 0), 2)                                               AS ac,
    f.farol_do_gerente
  FROM projetos p
  LEFT JOIN tarefas_hoje t ON t.projeto_id = p.projeto_id
  LEFT JOIN custo_hoje   c ON c.projeto_id = p.projeto_id
  LEFT JOIN farol_hoje   f ON f.projeto_id = p.projeto_id
),
indices AS (
  SELECT
    *,
    round(try_divide(ev, pv), 4) AS spi,
    round(try_divide(ev, ac), 4) AS cpi
  FROM kpis
),
projecao AS (
  SELECT
    *,
    round(try_divide(orcamento_custo, cpi), 2)          AS eac,
    try_divide(duracao_baseline_dias, spi)              AS duracao_projetada_dias
  FROM indices
)
SELECT
  -- projeto = o código (PRJ-xxx), como o dono fala. O nome fica em nome_projeto.
  projeto_id                                                                AS projeto,
  projeto_id,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,
  ferramenta,
  gerente_projeto,
  valor_contrato,
  orcamento_custo                                                           AS orcamento,
  data_inicio,
  data_fim_baseline,
  duracao_baseline_dias,
  status,
  pv,
  ev,
  ac,
  spi,
  cpi,
  eac,
  greatest(eac - orcamento_custo, 0)                                        AS estouro_previsto,
  round(try_divide(valor_contrato - eac, valor_contrato), 4)                AS margem_projetada,
  CAST(round(duracao_projetada_dias - duracao_baseline_dias) AS INT)       AS atraso_projetado_dias,
  date_add(data_inicio, CAST(round(duracao_projetada_dias) AS INT))         AS termino_projetado,
  CASE
    WHEN status <> 'em_andamento'   THEN 'concluído'
    WHEN spi < 0.8 OR cpi < 0.8     THEN 'crítico'
    WHEN spi < 0.9 OR cpi < 0.9     THEN 'atenção'
    ELSE 'ok'
  END                                                                       AS situacao,
  farol_do_gerente,
  -- regra do manual da Vértice
  CASE WHEN spi >= 0.95 THEN 'verde'
       WHEN spi >= 0.90 THEN 'amarelo'
       ELSE 'vermelho' END                                                  AS farol_calculado,
  -- o gerente diz verde, o número diz atraso
  coalesce(status = 'em_andamento' AND farol_do_gerente = 'verde' AND spi < 0.9, false) AS melancia
FROM projecao;


CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.utilizacao_pessoa_semana
COMMENT 'Utilização do timesheet por pessoa, projeto e semana (sexta-feira): nome, papel, senioridade, horas disponíveis, apontadas e ociosas, utilização (apontadas ÷ disponíveis), custo das horas ociosas (horas ociosas × custo/hora) e o SPI do projeto naquela semana. Responde se há gente parada enquanto outro projeto atrasa.'
AS
SELECT
  a.colaborador_id,
  c.nome,
  c.papel,
  c.senioridade,
  a.projeto_id,
  a.semana,
  a.horas_disponiveis,
  a.horas_apontadas,
  a.horas_disponiveis - a.horas_apontadas                                    AS horas_ociosas,
  round(try_divide(a.horas_apontadas, a.horas_disponiveis), 4)               AS utilizacao,
  round((a.horas_disponiveis - a.horas_apontadas) * c.custo_hora, 2)         AS custo_ocioso,
  f.spi                                                                      AS spi_do_projeto
FROM apontamentos a
JOIN colaboradores c ON c.colaborador_id = a.colaborador_id
LEFT JOIN lakehouse_vertice.gold.fato_projeto_semana f
  ON f.projeto_id = a.projeto_id AND f.semana = a.semana;
