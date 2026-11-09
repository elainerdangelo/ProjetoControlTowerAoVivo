-- testes_de_qualidade · roda depois do medalhão e QUEBRA o job se algo estiver errado.
-- Melhor o dashboard ficar com o dado da semana passada do que com o dado errado de hoje.
-- Cada linha é um teste: se a condição falhar, raise_error() diz qual teste e o valor encontrado.

WITH resultados AS (

  -- 1 · os 60 projetos têm cronograma na silver.tarefas
  SELECT 1 AS n, 'os 60 projetos têm cronograma na silver.tarefas' AS teste,
         CAST(COUNT(DISTINCT projeto_id) AS STRING) AS valor,
         COUNT(DISTINCT projeto_id) = 60 AS passou
  FROM lakehouse_vertice.silver.tarefas

  UNION ALL
  -- 2 · cada projeto veio de UMA ferramenta, e é a do cadastro do PMO
  SELECT 2, 'cada projeto veio de uma ferramenta, a do cadastro',
         CAST(COUNT(*) AS STRING) || ' projetos fora da regra',
         COUNT(*) = 0
  FROM (
    SELECT t.projeto_id
    FROM lakehouse_vertice.silver.tarefas t
    JOIN lakehouse_vertice.silver.projetos p USING (projeto_id)
    GROUP BY t.projeto_id
    HAVING COUNT(DISTINCT t.ferramenta) <> 1 OR max(t.ferramenta) <> max(p.ferramenta)
  )

  UNION ALL
  -- 3 · as horas do Excel na silver = a soma das linhas de TOTAL das planilhas
  SELECT 3, 'horas do Excel na silver = linhas de TOTAL',
         CAST(s.horas AS STRING) || ' × ' || CAST(b.horas AS STRING),
         abs(s.horas - b.horas) < 0.01
  FROM (SELECT SUM(horas) AS horas FROM lakehouse_vertice.silver.tarefas WHERE ferramenta = 'excel') s,
       (SELECT SUM(CAST(replace(horas_previstas, 'h', '') AS DOUBLE)) AS horas
          FROM lakehouse_vertice.bronze.excel_tarefas WHERE tarefa = 'TOTAL') b

  UNION ALL
  -- 4 · uma linha por pessoa na silver
  SELECT 4, 'uma linha por pessoa em silver.colaboradores',
         CAST(COUNT(*) AS STRING) || ' linhas, ' || CAST(COUNT(DISTINCT colaborador_id) AS STRING) || ' pessoas',
         COUNT(*) = COUNT(DISTINCT colaborador_id)
  FROM lakehouse_vertice.silver.colaboradores

  UNION ALL
  -- 5 · a CodeForge virou um fornecedor só
  SELECT 5, 'a CodeForge virou um fornecedor só',
         CAST(COUNT(DISTINCT fornecedor) AS STRING) || ' grafias na silver',
         COUNT(DISTINCT fornecedor) = 1
  FROM lakehouse_vertice.silver.entregas_fornecedor
  WHERE replace(lower(fornecedor), ' ', '') LIKE '%codeforge%'

  UNION ALL
  -- 6 · a limpeza não mudou o custo total
  SELECT 6, 'a limpeza não mudou o custo total (bronze = silver)',
         CAST(s.total AS STRING) || ' × ' || CAST(b.total AS STRING),
         s.total = b.total
  FROM (SELECT SUM(valor) AS total FROM lakehouse_vertice.silver.custos) s,
       (SELECT SUM(CAST(replace(valor, ',', '.') AS DECIMAL(18, 2))) AS total FROM lakehouse_vertice.bronze.custos) b

  UNION ALL
  -- 7 · os 60 projetos têm fotografia de hoje
  SELECT 7, 'os 60 projetos têm fotografia de hoje (uma linha cada)',
         CAST(COUNT(*) AS STRING) || ' linhas, ' || CAST(COUNT(DISTINCT projeto_id) AS STRING) || ' projetos',
         COUNT(*) = 60 AND COUNT(DISTINCT projeto_id) = 60
  FROM lakehouse_vertice.gold.projeto_situacao_atual

  UNION ALL
  -- 8 · todo projeto em andamento tem SPI e CPI
  SELECT 8, 'todo projeto em andamento tem SPI e CPI',
         CAST(COUNT_IF(spi IS NULL OR cpi IS NULL) AS STRING) || ' sem índice',
         COUNT_IF(spi IS NULL OR cpi IS NULL) = 0
  FROM lakehouse_vertice.gold.projeto_situacao_atual
  WHERE status = 'em_andamento'

  UNION ALL
  -- 9 · o EV de hoje do status semanal bate com o das ferramentas (diferença < 1%)
  SELECT 9, 'EV de hoje: status semanal × ferramentas (< 1%)',
         CAST(round(abs(f.ev - s.ev) / s.ev * 100, 3) AS STRING) || '%',
         abs(f.ev - s.ev) / s.ev < 0.01
  FROM (SELECT SUM(ev) AS ev FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16') f,
       (SELECT SUM(ev) AS ev FROM lakehouse_vertice.gold.projeto_situacao_atual) s

  UNION ALL
  -- 10 · AC de hoje no fato = soma dos lançamentos até hoje
  SELECT 10, 'AC de hoje no fato = lançamentos até hoje',
         CAST(f.ac AS STRING) || ' × ' || CAST(c.ac AS STRING),
         abs(f.ac - c.ac) < 0.01
  FROM (SELECT SUM(ac) AS ac FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16') f,
       (SELECT SUM(valor) AS ac FROM lakehouse_vertice.silver.custos WHERE data <= DATE'2026-10-16') c
)
SELECT
  n,
  teste,
  valor,
  CASE WHEN passou THEN 'ok'
       ELSE raise_error(concat('teste ', n, ' falhou: ', teste, ' (', valor, ')')) END AS resultado
FROM resultados
ORDER BY n
