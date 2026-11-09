-- Projetos em andamento, do pior para o melhor: crítico → atenção → ok, e dentro de cada
-- situação o menor índice (SPI ou CPI) primeiro. Traz a causa mais frequente do status
-- semanal dos últimos 90 dias e os dias de impacto por falta de SRE e por rotatividade
-- (o simulador usa esses dias para estimar o cronograma recuperado).
WITH causas AS (
  SELECT
    projeto_id,
    causa_bloqueio,
    COUNT(*)                         AS semanas,
    SUM(coalesce(dias_impacto, 0))   AS dias
  FROM lakehouse_vertice.gold.status_estruturado
  WHERE data_status >= DATE'2026-07-18'
    AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
  GROUP BY projeto_id, causa_bloqueio
),
por_projeto AS (
  SELECT
    projeto_id,
    max_by(causa_bloqueio, struct(semanas, dias))                  AS causa_principal,
    max(semanas)                                                   AS semanas_causa_principal,
    coalesce(SUM(dias) FILTER (WHERE causa_bloqueio = 'falta_sre'), 0)    AS dias_falta_sre,
    coalesce(SUM(dias) FILTER (WHERE causa_bloqueio = 'rotatividade'), 0) AS dias_rotatividade
  FROM causas
  GROUP BY projeto_id
)
SELECT
  p.projeto_id,
  p.nome_projeto,
  p.cliente,
  p.situacao,
  p.spi,
  p.cpi,
  p.estouro_previsto,
  p.atraso_projetado_dias,
  p.farol_do_gerente,
  p.farol_calculado,
  p.melancia,
  c.causa_principal,
  coalesce(c.semanas_causa_principal, 0)   AS semanas_causa_principal,
  coalesce(c.dias_falta_sre, 0)            AS dias_falta_sre,
  coalesce(c.dias_rotatividade, 0)         AS dias_rotatividade
FROM lakehouse_vertice.gold.projeto_situacao_atual p
LEFT JOIN por_projeto c ON c.projeto_id = p.projeto_id
WHERE p.status = 'em_andamento'
ORDER BY
  CASE p.situacao WHEN 'crítico' THEN 0 WHEN 'atenção' THEN 1 ELSE 2 END,
  least(p.spi, p.cpi)
