-- Pessoas com utilização abaixo de 20% nas últimas 12 semanas (depois de 24/07/2026),
-- por pessoa e projeto de origem. Horas paradas e custo ocioso são MÉDIAS por semana:
-- o simulador multiplica por 4 para chegar ao mês.
SELECT
  u.colaborador_id,
  u.nome,
  u.papel,
  u.senioridade,
  u.projeto_id                                                   AS projeto_origem,
  COUNT(DISTINCT u.semana)                                       AS semanas,
  SUM(u.horas_apontadas) / SUM(u.horas_disponiveis)              AS utilizacao,
  SUM(u.horas_ociosas) / COUNT(DISTINCT u.semana)                AS horas_paradas_semana,
  SUM(u.custo_ocioso)  / COUNT(DISTINCT u.semana)                AS custo_ocioso_semana,
  max(c.custo_hora)                                              AS custo_hora
FROM lakehouse_vertice.gold.utilizacao_pessoa_semana u
JOIN lakehouse_vertice.silver.colaboradores c ON c.colaborador_id = u.colaborador_id
WHERE u.semana > DATE'2026-07-24'
GROUP BY u.colaborador_id, u.nome, u.papel, u.senioridade, u.projeto_id
HAVING SUM(u.horas_apontadas) / SUM(u.horas_disponiveis) < 0.2
ORDER BY utilizacao
