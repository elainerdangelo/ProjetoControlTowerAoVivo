-- KPIs da carteira em andamento (fotografia de 16/10/2026). Uma linha.
-- O score do modelo NÃO entra aqui: ele pode não existir (vem da rota /api/score-estouro).
SELECT
  COUNT(*)                                        AS em_andamento,
  COUNT_IF(situacao IN ('atenção', 'crítico'))    AS em_risco,
  COUNT_IF(situacao = 'crítico')                  AS criticos,
  COUNT_IF(melancia)                              AS melancias,
  SUM(estouro_previsto)                           AS estouro_previsto,
  SUM(valor_contrato)                             AS carteira
FROM lakehouse_vertice.gold.projeto_situacao_atual
WHERE status = 'em_andamento'
