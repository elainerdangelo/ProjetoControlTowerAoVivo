-- gold.status_estruturado · o texto livre do status semanal vira coluna
-- "Por que o projeto atrasou?" A causa está escrita no status de toda sexta. Aqui ela vira dado.
--
-- Cada ferramenta onde ela é a certa (a IA custa ~5 s por texto):
--   regra          o que tem padrão fixo: semana sem bloqueio e status vazio. Custo zero.
--   ia             texto COM bloqueio dos últimos 90 dias (desde 18/07/2026), ~160 status
--   palavra_chave  o histórico mais antigo, onde a resposta não muda decisão
--
-- INCREMENTAL: a tabela acumula. O MERGE só recebe o status que ainda não está nela,
-- então a IA nunca é paga duas vezes pelo mesmo texto.
-- ATENÇÃO: a sql_task corta este arquivo em todo ponto e vírgula. Só use no fim de cada statement.


-- a · a tabela (CREATE TABLE IF NOT EXISTS, nunca OR REPLACE: ela acumula)
CREATE TABLE IF NOT EXISTS lakehouse_vertice.gold.status_estruturado (
  projeto_id        STRING    COMMENT 'Projeto do status (PRJ-xxx)',
  data_status       DATE      COMMENT 'Sexta-feira do status semanal',
  farol             STRING    COMMENT 'Farol informado pelo gerente: verde, amarelo ou vermelho',
  causa_bloqueio    STRING    COMMENT 'Causa do bloqueio: change_freeze, falta_sre, dependencia_fornecedor, rotatividade, mudanca_escopo, bug_retrabalho, aprovacao_cliente, sem_bloqueio, nao_reportado (status vazio) ou outro',
  bloqueio          STRING    COMMENT 'O bloqueio em poucas palavras (só nas linhas classificadas por IA)',
  quem_destrava     STRING    COMMENT 'Quem pode destravar o bloqueio (só nas linhas classificadas por IA)',
  dias_impacto      DOUBLE    COMMENT 'Dias de impacto no cronograma declarados no texto (1 semana = 7)',
  metodo            STRING    COMMENT 'Como a linha foi classificada: regra, ia ou palavra_chave',
  texto_status      STRING    COMMENT 'O texto livre original do status semanal',
  _classificado_em  TIMESTAMP COMMENT 'Quando a linha foi classificada (carimbo da execução)'
)
COMMENT 'Status semanal estruturado: a causa de cada bloqueio tirada do texto livre do gerente, por regra (sem bloqueio ou vazio), por IA (ai_classify + ai_extract, últimos 90 dias com bloqueio) ou por palavra-chave (histórico). Tabela incremental: cada status é classificado uma vez só.';


-- b · só o que ainda não está na tabela
MERGE INTO lakehouse_vertice.gold.status_estruturado AS t
USING (
  WITH
  novos AS (
    SELECT s.*
    FROM lakehouse_vertice.silver.status_semanal s
    LEFT ANTI JOIN lakehouse_vertice.gold.status_estruturado e
      ON e.projeto_id = s.projeto_id AND e.data_status = s.data_status
  ),

  com_metodo AS (
    SELECT
      projeto_id,
      data_status,
      farol,
      texto_status,
      status_vazio,
      CASE
        WHEN status_vazio
          OR lower(texto_status) LIKE '%bloqueios: nenhum%'
          OR lower(texto_status) LIKE '%sem bloqueios%'
          OR lower(texto_status) LIKE '%nada relevante%'  THEN 'regra'
        WHEN data_status >= DATE'2026-07-18'               THEN 'ia'
        ELSE 'palavra_chave'
      END                                                  AS metodo,
      -- a palavra-chave olha só o trecho dos bloqueios (as entregas falam de deploy, escopo...)
      regexp_extract(lower(texto_status), 'bloqueios:(.*)', 1) AS trecho_bloqueio,
      -- impacto declarado: '1 semana' = 7, ou 'de N dias'
      CASE
        WHEN lower(texto_status) LIKE '%impacto estimado: 1 semana%' THEN 7.0
        ELSE CAST(nullif(regexp_extract(lower(texto_status), 'impacto estimado de ([0-9]+) dias', 1), '') AS DOUBLE)
      END                                                  AS dias_regex
    FROM novos
  ),

  -- a IA roda UMA vez por texto, e só nas linhas do método ia
  ia_bruta AS (
    SELECT
      *,
      ai_classify(
        texto_status,
        '["change_freeze","falta_sre","dependencia_fornecedor","rotatividade","mudanca_escopo","bug_retrabalho","aprovacao_cliente","sem_bloqueio"]',
        map('version', '2.0')
      ) AS classe,
      ai_extract(
        texto_status,
        '{"bloqueio":{"type":"string"},"quem_destrava":{"type":"string"},"dias_impacto":{"type":"number","description":"dias de impacto no cronograma. 1 semana = 7"}}',
        map('version', '2.0')
      ) AS extraido
    FROM com_metodo
    WHERE metodo = 'ia'
  )

  -- regra
  SELECT
    projeto_id, data_status, farol,
    CASE WHEN status_vazio THEN 'nao_reportado' ELSE 'sem_bloqueio' END AS causa_bloqueio,
    CAST(NULL AS STRING)                                                AS bloqueio,
    CAST(NULL AS STRING)                                                AS quem_destrava,
    dias_regex                                                          AS dias_impacto,
    metodo, texto_status,
    current_timestamp()                                                 AS _classificado_em
  FROM com_metodo
  WHERE metodo = 'regra'

  UNION ALL
  -- ia
  SELECT
    projeto_id, data_status, farol,
    classe:response[0]::STRING                                          AS causa_bloqueio,
    extraido:response:bloqueio::STRING                                  AS bloqueio,
    extraido:response:quem_destrava::STRING                             AS quem_destrava,
    coalesce(extraido:response:dias_impacto::DOUBLE, dias_regex)        AS dias_impacto,
    metodo, texto_status,
    current_timestamp()                                                 AS _classificado_em
  FROM ia_bruta

  UNION ALL
  -- palavra-chave (a primeira regra que casar vence)
  SELECT
    projeto_id, data_status, farol,
    CASE
      WHEN trecho_bloqueio RLIKE 'freeze|congelamento|janela de deploy'               THEN 'change_freeze'
      WHEN trecho_bloqueio RLIKE 'sre|infraestrutura|ambiente de homologação'         THEN 'falta_sre'
      WHEN trecho_bloqueio RLIKE 'forge|consultoria|fornecedor'                       THEN 'dependencia_fornecedor'
      WHEN trecho_bloqueio RLIKE 'saída de|rotatividade|onboarding'                   THEN 'rotatividade'
      WHEN trecho_bloqueio RLIKE 'escopo|change request|regra de negócio'             THEN 'mudanca_escopo'
      WHEN trecho_bloqueio RLIKE 'bugs|regressão|refazendo'                           THEN 'bug_retrabalho'
      WHEN trecho_bloqueio RLIKE 'aprovação do cliente|homologação do cliente'        THEN 'aprovacao_cliente'
      ELSE 'outro'
    END                                                                 AS causa_bloqueio,
    CAST(NULL AS STRING)                                                AS bloqueio,
    CAST(NULL AS STRING)                                                AS quem_destrava,
    dias_regex                                                          AS dias_impacto,
    metodo, texto_status,
    current_timestamp()                                                 AS _classificado_em
  FROM com_metodo
  WHERE metodo = 'palavra_chave'
) AS s
ON t.projeto_id = s.projeto_id AND t.data_status = s.data_status
WHEN NOT MATCHED THEN INSERT *;


-- c · leitura: quantos status por método e causa
SELECT metodo, causa_bloqueio, COUNT(*) AS status, SUM(coalesce(dias_impacto, 0)) AS dias_de_impacto
FROM lakehouse_vertice.gold.status_estruturado
GROUP BY ALL
ORDER BY metodo, status DESC;
