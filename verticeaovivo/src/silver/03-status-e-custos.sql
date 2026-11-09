-- silver.status_semanal e silver.custos
-- Sujeiras #13 (vírgula decimal), #14 (estorno negativo), #17 (farol em caixas diferentes),
-- #18 (status vazio).

-- O status que o gerente reporta toda sexta. É o histórico do avanço (as ferramentas só têm o % de hoje).
CREATE OR REFRESH MATERIALIZED VIEW status_semanal (
  CONSTRAINT farol_conhecido EXPECT (farol IN ('verde', 'amarelo', 'vermelho')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Status semanal (toda sexta) de cada projeto reportado pelo gerente: % concluído, farol do gerente (verde, amarelo, vermelho) e o texto livre com bloqueios. status_vazio marca os textos sem conteúdo (vazio, N/A, ver ata da reunião), que são mantidos.'
AS
SELECT
  projeto_id,
  to_date(data_status)                                  AS data_status,
  gerente,
  lower(trim(farol))                                    AS farol,          -- #17: 'Verde', 'VERDE' → 'verde'
  CAST(nullif(trim(pct_concluido), '') AS INT)          AS pct_concluido,
  texto_status,
  -- #18: NÃO descarta a linha; só sinaliza
  coalesce(trim(texto_status), '') IN ('', 'N/A', 'ver ata da reunião') AS status_vazio
FROM lakehouse_vertice.bronze.status_semanal;


-- Os lançamentos de custo real. O teste da limpeza: o total continua R$ 193,35 mi.
CREATE OR REFRESH MATERIALIZED VIEW custos
COMMENT 'Lançamentos de custo real por projeto (pessoal, consultoria, cloud, licenças, despesas), em reais. Estornos ficam como valor negativo (o custo é líquido) com a flag estorno. semana é a sexta-feira da semana do lançamento, para cruzar com o status semanal.'
AS
SELECT
  lancamento_id,
  projeto_id,
  to_date(data)                                                    AS data,
  date_add(to_date(date_trunc('WEEK', to_date(data))), 4)          AS semana,   -- segunda + 4 = sexta
  categoria,
  centro_custo,
  descricao,
  -- #13: 671 valores vêm com vírgula decimal. replace ANTES do CAST; try_cast jogaria
  -- R$ 5,4 mi fora em silêncio, e CAST puro falharia (o que é melhor, mas não resolve)
  CAST(replace(valor, ',', '.') AS DECIMAL(18, 2))                 AS valor,
  -- #14: estorno é negativo e FICA
  CAST(replace(valor, ',', '.') AS DECIMAL(18, 2)) < 0             AS estorno
FROM lakehouse_vertice.bronze.custos;
