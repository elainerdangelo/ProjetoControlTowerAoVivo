-- silver.entregas_fornecedor
-- Sujeira #15: a mesma consultoria escrita de 4 jeitos ('CodeForge Consultoria Ltda',
-- 'Codeforge Consultoria', 'CODEFORGE CONSULTORIA LTDA', 'Code Forge Consultoria').
-- data_entrega vazia NÃO é sujeira: a entrega está em aberto.
-- "Hoje" do dataset = 16/10/2026 (nunca current_date()).

CREATE OR REFRESH MATERIALIZED VIEW entregas_fornecedor
COMMENT 'Entregas das consultorias contratadas: o que foi pedido, quando foi prometido e quando chegou. Fornecedor normalizado (fornecedor_como_veio guarda a grafia original). em_aberto = ainda não entregue; em_atraso = em aberto com a data prometida já vencida em 16/10/2026. Prazos e atraso em dias corridos.'
AS
WITH base AS (
  SELECT
    entrega_id,
    projeto_id,
    CASE WHEN replace(lower(fornecedor), ' ', '') LIKE '%codeforge%'
         THEN 'CodeForge Consultoria Ltda'
         ELSE fornecedor END                                AS fornecedor,
    fornecedor                                              AS fornecedor_como_veio,
    item,
    status,
    CAST(valor AS DECIMAL(18, 2))                           AS valor,
    CAST(prazo_contratado_dias AS INT)                      AS prazo_contratado_dias,
    to_date(data_pedido)                                    AS data_pedido,
    to_date(data_prometida)                                 AS data_prometida,
    to_date(nullif(data_entrega, ''))                       AS data_entrega
  FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT
  *,
  datediff(data_prometida, data_pedido)                     AS prazo_prometido_dias,
  datediff(data_entrega, data_pedido)                       AS prazo_real_dias,
  greatest(datediff(data_entrega, data_prometida), 0)       AS dias_de_atraso_na_entrega,
  data_entrega IS NULL                                      AS em_aberto,
  data_entrega IS NULL AND data_prometida < DATE'2026-10-16' AS em_atraso
FROM base;
