#!/usr/bin/env python3
"""Gera resources/farol.geniespace.json, o Genie Agent "Farol · Diretoria", como código.

O JSON é o `serialized_space` (versão 2) que o recurso genie_farol do bundle
(resources/genie.genie_space.yml) publica. Mude AQUI, nunca no workspace: o próximo
`bundle deploy` recusaria ("modified remotely").

O score do modelo (gold.score_estouro_30d) só entra se a tabela existir no workspace:
sem ela, nenhuma instrução nem exemplo fala de score.

Uso:
  python scripts/gerar_genie.py --profile <perfil>
"""
import argparse
import json
import pathlib
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "resources" / "farol.geniespace.json"
G = "lakehouse_vertice.gold"
S = "lakehouse_vertice.silver"
TABELA_SCORE = f"{G}.score_estouro_30d"


def existe(tabela: str, profile: str) -> bool:
    r = subprocess.run(["databricks", "tables", "exists", tabela, "--profile", profile, "-o", "json"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"não consegui conferir {tabela}: {r.stderr.strip()}")
    return bool(json.loads(r.stdout).get("table_exists"))


def ids(prefixo: str):
    """ids de 32 hex, únicos (um prefixo por tipo) e crescentes: a API exige a lista ordenada."""
    n = 0
    while True:
        n += 1
        yield f"{prefixo}{n:031x}"


# ─── As 4 perguntas do dono ──────────────────────────────────────────────────────────
PERGUNTAS_DO_DONO = [
    "Quais projetos estão atrasados, e de quais clientes?",
    "Quanto esse atraso vai me custar?",
    "Tenho gente parada enquanto outro projeto pede gente?",
    "O que vai dar errado no próximo mês?",
]

SQL_ATRASADOS = f"""
SELECT projeto, nome_projeto, cliente, situacao, ROUND(spi, 2) AS spi, ROUND(cpi, 2) AS cpi,
       ROUND(estouro_previsto, 2) AS estouro_previsto, atraso_projetado_dias
FROM {G}.projeto_situacao_atual
WHERE status = 'em_andamento' AND situacao IN ('crítico', 'atenção')
ORDER BY CASE situacao WHEN 'crítico' THEN 0 ELSE 1 END, least(spi, cpi)
"""

SQL_CUSTO = f"""
SELECT ROUND(MEASURE(estouro_previsto), 2) AS estouro_previsto,
       ROUND(MEASURE(margem_projetada), 4) AS margem_projetada,
       ROUND(MEASURE(eac), 2)              AS eac,
       ROUND(MEASURE(carteira), 2)         AS carteira,
       MEASURE(projetos_em_risco)          AS projetos_em_risco
FROM {G}.mv_projetos
"""

SQL_GENTE_PARADA = f"""
WITH parados AS (
  SELECT colaborador_id, nome, papel, projeto_id,
         SUM(horas_apontadas) / SUM(horas_disponiveis) AS utilizacao,
         SUM(horas_ociosas) AS horas_paradas, SUM(custo_ocioso) AS custo_parado
  FROM {G}.utilizacao_pessoa_semana
  WHERE semana > DATE'2026-07-24'
  GROUP BY colaborador_id, nome, papel, projeto_id
  HAVING SUM(horas_apontadas) / SUM(horas_disponiveis) < 0.2
),
pedindo AS (
  SELECT projeto_id, causa_bloqueio, COUNT(*) AS semanas, SUM(coalesce(dias_impacto, 0)) AS dias_impacto
  FROM {G}.status_estruturado
  WHERE data_status >= DATE'2026-07-18' AND causa_bloqueio IN ('falta_sre', 'rotatividade')
  GROUP BY projeto_id, causa_bloqueio
)
SELECT 'pessoa parada' AS lado, colaborador_id AS quem, papel AS detalhe, projeto_id,
       ROUND(utilizacao, 3) AS utilizacao, ROUND(horas_paradas, 1) AS horas, ROUND(custo_parado, 2) AS reais
FROM parados
UNION ALL
SELECT 'projeto pedindo gente', causa_bloqueio, CONCAT(semanas, ' semanas no status'), projeto_id,
       NULL, dias_impacto, NULL
FROM pedindo
ORDER BY lado, utilizacao
"""

SQL_PROXIMO_MES = f"""
SELECT 'entrega de consultoria em atraso' AS risco, projeto_id, fornecedor AS quem,
       CONCAT(item, ': prometida para ', CAST(data_prometida AS STRING)) AS detalhe
FROM {S}.entregas_fornecedor
WHERE em_atraso
UNION ALL
SELECT 'change freeze de varejo (01/11/2026 a 10/01/2027)', projeto, cliente,
       CONCAT(tipo_projeto, ', situação ', situacao, ', SPI ', CAST(ROUND(spi, 2) AS STRING))
FROM {G}.projeto_situacao_atual
WHERE status = 'em_andamento'
  AND (lower(tipo_projeto) LIKE '%commerce%' OR lower(tipo_projeto) LIKE '%checkout%'
       OR lower(tipo_projeto) LIKE '%marketplace%')
"""

SQL_PROXIMO_MES_COM_SCORE = SQL_PROXIMO_MES + f"""
UNION ALL
SELECT CONCAT('modelo: risco ', s.faixa_risco, ' de estourar em 30 dias'), s.projeto_id, p.cliente,
       CONCAT(CAST(ROUND(s.prob_estouro_30d * 100) AS STRING), '% · ', s.principais_fatores)
FROM {TABELA_SCORE} s
JOIN {G}.projeto_situacao_atual p ON p.projeto_id = s.projeto_id
WHERE p.situacao = 'ok' AND s.faixa_risco IN ('alto', 'medio')
  AND s.data_referencia = (SELECT max(data_referencia) FROM {TABELA_SCORE})
"""

SQL_CHANCE_PRJ024 = f"""
SELECT projeto_id, ROUND(prob_estouro_30d, 2) AS prob_estouro_30d, faixa_risco, ranking, principais_fatores
FROM {TABELA_SCORE}
WHERE projeto_id = 'PRJ-024'
  AND data_referencia = (SELECT max(data_referencia) FROM {TABELA_SCORE})
"""


# ─── Instruções de negócio (a API aceita UM item de texto, com várias linhas) ───────────
def instrucoes(com_score: bool) -> list[str]:
    linhas = [
        "QUEM PERGUNTA: o dono e a diretoria da Vértice Tecnologia, que não escrevem SQL. Responda em português, "
        "direto, citando os números (R$ com 2 casas, índices com 2 casas) e o código do projeto (PRJ-xxx).\n",
        "HOJE é 2026-10-16 (sexta). Nunca use current_date() nem now(): escreva DATE'2026-10-16'. "
        "'Últimos 90 dias' = data_status >= DATE'2026-07-18'. 'Últimas 12 semanas' = semana > DATE'2026-07-24'. "
        "'Próximo mês' = de 2026-10-17 a 2026-11-16.\n",
        "FÓRMULAS: SPI = EV / PV (abaixo de 1 é atraso). CPI = EV / AC (abaixo de 1 é estouro de custo). "
        "EAC = orçamento / CPI. Estouro previsto = EAC - orçamento, só quando positivo. "
        "Margem projetada = (valor do contrato - EAC) / valor do contrato. "
        "Índice de grupo (carteira, cliente, segmento, ferramenta) é SEMPRE razão das somas: SUM(ev)/SUM(pv), "
        "nunca média dos índices dos projetos.\n",
        "REGRAS DE CORTE: SPI ou CPI < 0,8 = crítico. < 0,9 = atenção. Senão ok. "
        "'Atrasado' ou 'em risco' = situacao IN ('crítico', 'atenção'). Só projetos com status = 'em_andamento' "
        "contam para a carteira (concluídos têm situacao = 'concluído').\n",
        f"ONDE OLHAR: totais de hoje (SPI, CPI, estouro, margem, contagens da carteira ou por cliente, segmento, "
        f"ferramenta) vêm da metric view {G}.mv_projetos com MEASURE(...), que já filtra os em andamento. "
        f"Ranking, lista e valor de um projeto vêm de {G}.projeto_situacao_atual (uma linha por projeto, "
        "a coluna projeto é o código PRJ-xxx).\n",
        f"HISTÓRICO: {G}.fato_projeto_semana tem uma linha por projeto e sexta-feira. PV, EV e AC são ACUMULADOS "
        "até a semana: nunca some semanas diferentes do mesmo projeto. Para 'na semana de X' filtre semana = X.\n",
        "FAROL E MELANCIA: farol_do_gerente é o que o gerente reportou. farol_calculado é pela regra do manual "
        "(verde com SPI >= 0,95, amarelo >= 0,90, vermelho abaixo). Melancia (ou 'farol mentiroso', 'verde mas "
        "atrasado') = coluna melancia: farol do gerente verde e SPI < 0,9.\n",
        f"POR QUE O PROJETO X ATRASOU: use {G}.status_estruturado dos últimos 90 dias, sem 'sem_bloqueio' e "
        "'nao_reportado': a causa_bloqueio mais frequente (COUNT por causa), semanas e soma de dias_impacto, "
        "mais o SPI do projeto. Se a causa for falta_sre, mostre também as SREs ociosas (papel = 'sre', "
        "utilização < 20% nas últimas 12 semanas).\n",
        f"GENTE PARADA: {G}.utilizacao_pessoa_semana nas últimas 12 semanas, por pessoa: "
        "SUM(horas_apontadas) / SUM(horas_disponiveis) < 0,2. Projeto pedindo gente = causa falta_sre ou "
        "rotatividade no status dos últimos 90 dias.\n",
        f"FORNECEDOR: {S}.entregas_fornecedor. Quem mais atrasa = maior média de prazo_real_dias / "
        "prazo_prometido_dias por fornecedor (o nome já vem normalizado). Em atraso hoje = coluna em_atraso.\n",
        "O QUE VAI DAR ERRADO NO PRÓXIMO MÊS: junte (1) as entregas de consultoria em atraso hoje (em_atraso) e "
        "(2) o change freeze de varejo, de 01/11/2026 a 10/01/2027, nos projetos de e-commerce em andamento "
        "(tipo_projeto contém 'commerce', 'checkout' ou 'marketplace')"
        + (
            f", e (3) os projetos com situacao = 'ok' hoje e faixa_risco 'alto' ou 'medio' em {TABELA_SCORE} "
            "(com prob_estouro_30d e principais_fatores, na data_referencia mais recente). Quem já está em "
            "atenção ou crítico não é novidade do modelo.\n"
            if com_score else ".\n"
        ),
        "CHANGE FREEZE: todo projeto de e-commerce em andamento (tipo_projeto contém 'commerce', 'checkout' ou "
        "'marketplace') fica travado pelo freeze da Black Friday. Não filtre por data_inicio nem data_fim_baseline: "
        "o projeto está em andamento hoje, então atravessa o freeze.\n",
        "QUAIS CLIENTES: devolva cada cliente uma vez só (DISTINCT cliente).\n",
    ]
    if com_score:
        linhas.append(
            f"CHANCE DE ESTOURO: {TABELA_SCORE} (prob_estouro_30d de 0 a 1, faixa_risco alto >= 0,5, medio >= 0,2, "
            "baixo), sempre na data_referencia mais recente.\n"
        )
    return linhas


def espaco(com_score: bool) -> dict:
    tabelas = [f"{G}.fato_projeto_semana", f"{G}.projeto_situacao_atual", f"{G}.status_estruturado",
               f"{G}.utilizacao_pessoa_semana", f"{S}.entregas_fornecedor"]
    if com_score:
        tabelas.append(TABELA_SCORE)

    exemplos = [
        (PERGUNTAS_DO_DONO[0], SQL_ATRASADOS),
        (PERGUNTAS_DO_DONO[1], SQL_CUSTO),
        (PERGUNTAS_DO_DONO[2], SQL_GENTE_PARADA),
        (PERGUNTAS_DO_DONO[3], SQL_PROXIMO_MES_COM_SCORE if com_score else SQL_PROXIMO_MES),
    ]
    if com_score:
        exemplos.append(("Qual a chance de o PRJ-024 estourar?", SQL_CHANCE_PRJ024))

    id_pergunta, id_exemplo, id_texto = ids("1"), ids("2"), ids("3")
    return {
        "version": 2,
        "config": {
            "sample_questions": [{"id": next(id_pergunta), "question": [p]} for p in PERGUNTAS_DO_DONO],
        },
        "data_sources": {
            "tables": [{"identifier": t} for t in sorted(tabelas)],
            "metric_views": [{"identifier": f"{G}.mv_projetos"}],
        },
        "instructions": {
            "text_instructions": [{"id": next(id_texto), "content": instrucoes(com_score)}],
            "example_question_sqls": [
                {"id": next(id_exemplo), "question": [p],
                 "sql": [linha + "\n" for linha in sql.strip().splitlines()]}
                for p, sql in exemplos
            ],
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", required=True, help="profile do ~/.databrickscfg (sempre explícito)")
    a = ap.parse_args()
    com_score = existe(TABELA_SCORE, a.profile)
    dados = espaco(com_score)
    SAIDA.write_text(json.dumps(dados, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{SAIDA.relative_to(RAIZ)}: {len(dados['data_sources']['tables'])} tabelas + 1 metric view, "
          f"{len(dados['instructions']['example_question_sqls'])} exemplos de SQL, "
          f"score {'INCLUÍDO' if com_score else 'ausente (tabela não existe)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
