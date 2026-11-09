-- gold.mv_projetos · a fórmula de cada KPI num lugar só (metric view, YAML 1.1)
-- A metric view guarda a FÓRMULA, não o número: MEASURE(cpi) é sempre SUM(ev) / SUM(ac),
-- recalculado no grão que a pergunta pedir (projeto, cliente, segmento, ferramenta, carteira).
-- Razão não se soma: o CPI da carteira é soma do EV ÷ soma do AC, nunca a média dos CPIs.
-- O Genie, o SQL e o app usam esta mesma definição.
--
-- ARMADILHAS: o YAML precisa da indentação intacta (rode com scripts/run_sql.py ou sql_task,
-- nunca pelo aitools tools query) e NÃO pode ter ponto e vírgula, nem num comment:
-- a sql_task do job corta o arquivo em todo ponto e vírgula.

CREATE OR REPLACE VIEW lakehouse_vertice.gold.mv_projetos
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1
comment: "KPIs da carteira de projetos EM ANDAMENTO da Vértice na fotografia de 16/10/2026. Fonte: gold.projeto_situacao_atual. Índices são razão das somas (SUM/SUM), nunca média de razões."
source: lakehouse_vertice.gold.projeto_situacao_atual
filter: status = 'em_andamento'

dimensions:
  - name: projeto_id
    expr: projeto_id
    comment: "Código do projeto, no formato PRJ-xxx"
    synonyms: ["projeto", "código do projeto", "id do projeto"]
  - name: projeto
    expr: nome_projeto
    comment: "Nome do projeto (tipo de sistema e cliente)"
    synonyms: ["nome do projeto"]
  - name: cliente
    expr: cliente
    synonyms: ["empresa cliente", "conta"]
  - name: segmento
    expr: segmento
    comment: "Segmento do cliente: varejo, financeiro, saude, logistica ou industria"
    synonyms: ["setor", "vertical", "mercado"]
  - name: ferramenta
    expr: ferramenta
    comment: "Onde o gerente controla o cronograma: excel, clickup ou msproject"
    synonyms: ["ferramenta de gestão", "sistema do cronograma"]
  - name: situacao
    expr: situacao
    comment: "Situação calculada: crítico (SPI ou CPI abaixo de 0,8), atenção (abaixo de 0,9) ou ok"
    synonyms: ["status do projeto", "risco", "classificação"]
  - name: farol_do_gerente
    expr: farol_do_gerente
    comment: "Farol informado pelo gerente no status de 16/10/2026: verde, amarelo ou vermelho"
    synonyms: ["farol informado", "farol reportado", "semáforo do gerente"]
  - name: farol_calculado
    expr: farol_calculado
    comment: "Farol pela regra do manual da Vértice: verde com SPI a partir de 0,95, amarelo a partir de 0,90, vermelho abaixo"
    synonyms: ["farol pelo número", "farol real", "semáforo calculado"]
  - name: gerente_projeto
    expr: gerente_projeto
    synonyms: ["gerente", "gestor do projeto", "GP"]

measures:
  - name: projetos
    expr: COUNT(1)
    comment: "Quantidade de projetos em andamento"
    synonyms: ["quantidade de projetos", "número de projetos", "total de projetos"]
  - name: carteira
    expr: SUM(valor_contrato)
    comment: "Valor dos contratos em reais"
    synonyms: ["valor da carteira", "valor dos contratos", "receita contratada"]
  - name: spi
    expr: SUM(ev) / SUM(pv)
    comment: "Índice de desempenho de prazo: valor agregado dividido pelo valor planejado. Abaixo de 1 é atraso"
    synonyms: ["índice de prazo", "desempenho de prazo", "schedule performance index"]
  - name: cpi
    expr: SUM(ev) / SUM(ac)
    comment: "Índice de desempenho de custo: valor agregado dividido pelo custo real. Abaixo de 1 é estouro de custo"
    synonyms: ["índice de custo", "desempenho de custo", "cost performance index"]
  - name: eac
    expr: SUM(eac)
    comment: "Estimativa no término em reais: orçamento dividido pelo CPI de cada projeto"
    synonyms: ["estimativa no término", "custo final previsto", "estimate at completion"]
  - name: estouro_previsto
    expr: SUM(estouro_previsto)
    comment: "Quanto o custo final deve passar do orçamento, em reais (EAC menos orçamento, só quando positivo)"
    synonyms: ["estouro", "custo do atraso", "quanto vai custar", "prejuízo previsto", "sobrecusto"]
  - name: margem_projetada
    expr: (SUM(valor_contrato) - SUM(eac)) / SUM(valor_contrato)
    comment: "Margem projetada: valor do contrato menos EAC, dividido pelo valor do contrato (fração de 0 a 1)"
    synonyms: ["margem", "margem prevista", "rentabilidade"]
  - name: atraso_projetado_medio_dias
    expr: AVG(atraso_projetado_dias)
    comment: "Atraso projetado médio em dias corridos: duração baseline dividida pelo SPI menos a duração baseline"
    synonyms: ["atraso médio", "dias de atraso", "atraso projetado"]
  - name: projetos_em_risco
    expr: COUNT(1) FILTER (WHERE situacao IN ('atenção', 'crítico'))
    comment: "Projetos em atenção ou crítico"
    synonyms: ["em risco", "projetos atrasados", "projetos com problema"]
  - name: projetos_criticos
    expr: COUNT(1) FILTER (WHERE situacao = 'crítico')
    comment: "Projetos com SPI ou CPI abaixo de 0,8"
    synonyms: ["críticos", "projetos em situação crítica"]
  - name: projetos_melancia
    expr: COUNT(1) FILTER (WHERE melancia)
    comment: "Melancias: o gerente diz farol verde mas o SPI está abaixo de 0,9 (verde por fora, vermelho por dentro)"
    synonyms: ["melancias", "farol mentiroso", "farol verde atrasado", "verde por fora"]
$$
