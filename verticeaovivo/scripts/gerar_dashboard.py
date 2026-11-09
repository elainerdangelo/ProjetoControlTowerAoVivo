#!/usr/bin/env python3
"""Gera resources/dashboard-portfolio.lvdash.json, o dashboard "Projeto Farol · Portfólio".

Dashboard como código: o JSON é gerado por este script (escrever o JSON à mão é pedir para
errar uma vírgula) e vai para o Git dentro do bundle. NÃO edite o dashboard no workspace:
o próximo `bundle deploy` recusa ("modified remotely"). A mudança vem para cá.

As queries da gold usam o nome PURO da tabela: quem completa catálogo e schema é o recurso
do bundle (dataset_catalog / dataset_schema em resources/dashboard.dashboard.yml).
A silver.entregas_fornecedor vai com o nome completo (é de outro schema).

Uso:
  python scripts/gerar_dashboard.py                       # grava o JSON
  python scripts/gerar_dashboard.py --testar --profile P  # roda cada query no warehouse e mostra o resultado
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "resources" / "dashboard-portfolio.lvdash.json"
WAREHOUSE = "287b54bcf4b0ebe0"
TABELAS_GOLD = ["projeto_situacao_atual", "fato_projeto_semana", "utilizacao_pessoa_semana", "status_estruturado"]

# Cores semânticas da situação (fixas, fora da paleta)
COR_SITUACAO = [
    {"value": "crítico", "color": "#FF5F46"},
    {"value": "atenção", "color": "#F6C344"},
    {"value": "ok", "color": "#22C2F4"},
]
BRL = {"type": "number-currency", "currencyCode": "BRL", "abbreviation": "compact",
       "decimalPlaces": {"type": "max", "places": 2}}
INDICE = {"type": "number", "decimalPlaces": {"type": "exact", "places": 2}}
PCT = {"type": "number-percent", "decimalPlaces": {"type": "max", "places": 1}}
HORAS = {"type": "number", "decimalPlaces": {"type": "max", "places": 0}}


# ─── Datasets: toda regra de negócio mora aqui. Razão é SUM/SUM, nunca média de razão. ───
DATASETS = {
    "ds_kpis": ("KPIs da carteira em andamento", """
SELECT
  SUM(valor_contrato)                                    AS carteira,
  SUM(ev) / SUM(pv)                                      AS spi,
  SUM(ev) / SUM(ac)                                      AS cpi,
  SUM(estouro_previsto)                                  AS estouro_previsto,
  COUNT_IF(situacao IN ('atenção', 'crítico'))           AS em_risco,
  COUNT_IF(situacao = 'crítico')                         AS criticos,
  COUNT_IF(melancia)                                     AS melancias
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
"""),
    "ds_projetos": ("Projetos em andamento", """
SELECT
  projeto_id, nome_projeto, cliente, segmento, gerente_projeto, ferramenta, situacao,
  spi, cpi, estouro_previsto, margem_projetada, atraso_projetado_dias, termino_projetado,
  farol_do_gerente, farol_calculado,
  CASE WHEN melancia THEN 'melancia' ELSE '' END         AS melancia
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
ORDER BY estouro_previsto DESC
"""),
    "ds_tendencia": ("SPI e CPI semanais da carteira", """
SELECT
  semana,
  SUM(ev) / SUM(pv)                                      AS spi,
  SUM(ev) / SUM(ac)                                      AS cpi
FROM fato_projeto_semana
WHERE semana >= DATE'2025-03-07'
GROUP BY semana
ORDER BY semana
"""),
    "ds_top_parados": ("Top 15 custo da hora parada (12 semanas)", """
SELECT
  concat(colaborador_id, ' · ', nome, ' (', projeto_id, ')') AS pessoa,
  colaborador_id, nome, papel, projeto_id,
  SUM(horas_ociosas)                                     AS horas_paradas,
  SUM(custo_ocioso)                                      AS custo_parado
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY ALL
ORDER BY custo_parado DESC
LIMIT 15
"""),
    "ds_utilizacao": ("Utilização por pessoa e projeto (12 semanas)", """
SELECT
  colaborador_id, nome, papel, senioridade, projeto_id,
  SUM(horas_disponiveis)                                 AS horas_disponiveis,
  SUM(horas_apontadas)                                   AS horas_apontadas,
  SUM(horas_ociosas)                                     AS horas_paradas,
  SUM(horas_apontadas) / SUM(horas_disponiveis)          AS utilizacao,
  SUM(custo_ocioso)                                      AS custo_parado
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY ALL
ORDER BY utilizacao, custo_parado DESC
"""),
    "ds_causas": ("Causas de bloqueio (90 dias)", """
SELECT
  projeto_id,
  causa_bloqueio,
  COUNT(*)                                               AS semanas,
  SUM(coalesce(dias_impacto, 0))                         AS dias_de_impacto
FROM status_estruturado
WHERE data_status >= DATE'2026-07-18'
  AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
GROUP BY ALL
ORDER BY projeto_id
"""),
    "ds_fornecedores": ("Fornecedores", """
SELECT
  fornecedor,
  COUNT(DISTINCT fornecedor_como_veio)                                       AS grafias_no_cadastro,
  COUNT(*)                                                                   AS entregas,
  SUM(prazo_real_dias) / SUM(CASE WHEN NOT em_aberto THEN prazo_prometido_dias END) AS prazo_real_sobre_prometido,
  COUNT_IF(NOT em_aberto AND data_entrega <= data_prometida) / COUNT_IF(NOT em_aberto) AS pct_no_prazo,
  COUNT_IF(em_atraso)                                                        AS em_atraso_hoje
FROM lakehouse_vertice.silver.entregas_fornecedor
GROUP BY fornecedor
ORDER BY prazo_real_sobre_prometido DESC
"""),
    "ds_atrasos": ("Entregas em atraso hoje", """
SELECT
  entrega_id, fornecedor, projeto_id, item, data_pedido, data_prometida,
  datediff(DATE'2026-10-16', data_prometida)             AS dias_em_atraso,
  valor
FROM lakehouse_vertice.silver.entregas_fornecedor
WHERE em_atraso
ORDER BY dias_em_atraso DESC
"""),
}


# ─── Construtores de widget (fields[].name = encodings.fieldName, sempre) ────────────
def campos(*nomes):
    return [{"name": n, "expression": f"`{n}`"} for n in nomes]


def consulta(dataset, *nomes):
    return [{"name": "main_query",
             "query": {"datasetName": dataset, "fields": campos(*nomes), "disaggregated": True}}]


def texto(nome, linhas, x, y, w, h):
    return {"widget": {"name": nome, "multilineTextboxSpec": {"lines": linhas}},
            "position": {"x": x, "y": y, "width": w, "height": h}}


def kpi(nome, campo, titulo, fmt, x, y, w, descricao=None):
    frame = {"showTitle": True, "title": titulo}
    if descricao:
        frame.update({"showDescription": True, "description": descricao})
    valor = {"fieldName": campo, "displayName": titulo}
    if fmt:
        valor["format"] = fmt
    return {"widget": {"name": nome, "queries": consulta("ds_kpis", campo),
                       "spec": {"version": 2, "widgetType": "counter",
                                "encodings": {"value": valor}, "frame": frame}},
            "position": {"x": x, "y": y, "width": w, "height": 3}}


def tabela(nome, dataset, titulo, colunas, x, y, w, h):
    """colunas = [(campo, rótulo, formato ou None)]"""
    cols = []
    for campo, rotulo, fmt in colunas:
        c = {"fieldName": campo, "displayName": rotulo}
        if fmt:
            c["format"] = fmt
        cols.append(c)
    return {"widget": {"name": nome, "queries": consulta(dataset, *[c[0] for c in colunas]),
                       "spec": {"version": 2, "widgetType": "table",
                                "encodings": {"columns": cols},
                                "frame": {"showTitle": True, "title": titulo}}},
            "position": {"x": x, "y": y, "width": w, "height": h}}


def grafico(nome, dataset, tipo, titulo, encodings, nomes, x, y, w, h, descricao=None):
    frame = {"showTitle": True, "title": titulo}
    if descricao:
        frame.update({"showDescription": True, "description": descricao})
    return {"widget": {"name": nome, "queries": consulta(dataset, *nomes),
                       "spec": {"version": 3, "widgetType": tipo, "encodings": encodings, "frame": frame}},
            "position": {"x": x, "y": y, "width": w, "height": h}}


# ─── Páginas ─────────────────────────────────────────────────────────────────────────
def pagina_portfolio():
    return [
        texto("titulo_portfolio", ["## Quais projetos estão atrasados, e quanto isso vai custar?\n", "\n",
              "Carteira em andamento em 16/10/2026. SPI e CPI são razão das somas (EV ÷ PV, EV ÷ AC), "
              "não média dos projetos. Crítico: SPI ou CPI < 0,8 · atenção: < 0,9."], 0, 0, 12, 2),
        kpi("kpi_carteira", "carteira", "Carteira em andamento", BRL, 0, 2, 3),
        kpi("kpi_spi", "spi", "SPI da carteira", INDICE, 3, 2, 3, "EV ÷ PV · abaixo de 1 é atraso"),
        kpi("kpi_cpi", "cpi", "CPI da carteira", INDICE, 6, 2, 3, "EV ÷ AC · abaixo de 1 é estouro"),
        kpi("kpi_estouro", "estouro_previsto", "Estouro previsto", BRL, 9, 2, 3, "EAC − orçamento"),
        kpi("kpi_em_risco", "em_risco", "Projetos em risco", None, 0, 5, 4, "atenção + crítico"),
        kpi("kpi_criticos", "criticos", "Críticos", None, 4, 5, 4, "SPI ou CPI < 0,8"),
        kpi("kpi_melancias", "melancias", "Melancias", None, 8, 5, 4, "farol do gerente verde e SPI < 0,9"),
        grafico("barra_estouro", "ds_projetos", "bar", "Estouro previsto por projeto", {
            "x": {"fieldName": "projeto_id", "scale": {"type": "categorical"}, "displayName": "Projeto"},
            "y": {"fieldName": "estouro_previsto", "scale": {"type": "quantitative"},
                  "displayName": "Estouro previsto", "format": BRL},
            "color": {"fieldName": "situacao", "scale": {"type": "categorical", "mappings": COR_SITUACAO},
                      "displayName": "Situação"},
        }, ["projeto_id", "estouro_previsto", "situacao"], 0, 8, 6, 6),
        grafico("dispersao_spi_cpi", "ds_projetos", "scatter", "SPI × CPI por projeto", {
            "x": {"fieldName": "spi", "scale": {"type": "quantitative"}, "displayName": "SPI", "format": INDICE},
            "y": {"fieldName": "cpi", "scale": {"type": "quantitative"}, "displayName": "CPI", "format": INDICE},
            "color": {"fieldName": "situacao", "scale": {"type": "categorical", "mappings": COR_SITUACAO},
                      "displayName": "Situação"},
            "extra": [{"fieldName": "projeto_id", "displayName": "Projeto"}, {"fieldName": "nome_projeto", "displayName": "Nome"}],
        }, ["spi", "cpi", "situacao", "projeto_id", "nome_projeto"], 6, 8, 6, 6, "um ponto por projeto em andamento"),
        grafico("linha_spi_cpi", "ds_tendencia", "line", "SPI e CPI semanais da carteira", {
            "x": {"fieldName": "semana", "scale": {"type": "temporal"}, "displayName": "Semana"},
            "y": {"scale": {"type": "quantitative"}, "format": INDICE, "fields": [
                {"fieldName": "spi", "displayName": "SPI"},
                {"fieldName": "cpi", "displayName": "CPI"}]},
        }, ["semana", "spi", "cpi"], 0, 14, 12, 5, "pelo % do status semanal do gerente, desde 07/03/2025"),
        tabela("tabela_farol", "ds_projetos", "Posso confiar no farol? O farol do gerente ao lado do farol pelo número", [
            ("projeto_id", "Projeto", None), ("nome_projeto", "Nome", None), ("cliente", "Cliente", None), ("gerente_projeto", "Gerente", None),
            ("situacao", "Situação", None), ("farol_do_gerente", "Farol do gerente", None),
            ("farol_calculado", "Farol pelo número", None), ("melancia", "Melancia", None),
            ("spi", "SPI", INDICE), ("cpi", "CPI", INDICE), ("estouro_previsto", "Estouro previsto", BRL),
            ("margem_projetada", "Margem projetada", PCT), ("atraso_projetado_dias", "Atraso projetado (dias)", None),
            ("termino_projetado", "Término projetado", None),
        ], 0, 19, 12, 8),
    ]


def pagina_pessoas():
    return [
        texto("titulo_pessoas", ["## Tenho gente parada enquanto outro projeto pede gente?\n", "\n",
              "Últimas 12 semanas (depois de 24/07/2026). Hora parada = disponível − apontada. "
              "As causas vêm do texto do status semanal, lido por regra, IA ou palavra-chave."], 0, 0, 12, 2),
        grafico("top_parados", "ds_top_parados", "bar", "Top 15 · custo da hora parada", {
            "x": {"fieldName": "custo_parado", "scale": {"type": "quantitative"},
                  "displayName": "Custo parado", "format": BRL},
            "y": {"fieldName": "pessoa", "scale": {"type": "categorical"},
                  "displayName": "Pessoa"},
            "color": {"fieldName": "papel", "scale": {"type": "categorical"}, "displayName": "Papel"},
        }, ["custo_parado", "pessoa", "papel"], 0, 2, 6, 7),
        grafico("causas_por_projeto", "ds_causas", "bar", "Causas de bloqueio por projeto (90 dias)", {
            "x": {"fieldName": "projeto_id", "scale": {"type": "categorical"}, "displayName": "Projeto"},
            "y": {"fieldName": "semanas", "scale": {"type": "quantitative"}, "displayName": "Semanas com bloqueio"},
            "color": {"fieldName": "causa_bloqueio", "scale": {"type": "categorical"}, "displayName": "Causa"},
        }, ["projeto_id", "semanas", "causa_bloqueio"], 6, 2, 6, 7, "sem 'sem_bloqueio' e 'nao_reportado'"),
        tabela("tabela_utilizacao", "ds_utilizacao", "Utilização por pessoa e projeto · da mais parada à mais ocupada", [
            ("colaborador_id", "ID", None), ("nome", "Nome", None), ("papel", "Papel", None),
            ("senioridade", "Senioridade", None), ("projeto_id", "Projeto", None),
            ("utilizacao", "Utilização", PCT), ("horas_disponiveis", "Horas disponíveis", HORAS),
            ("horas_apontadas", "Horas apontadas", HORAS), ("horas_paradas", "Horas paradas", HORAS),
            ("custo_parado", "Custo parado", BRL),
        ], 0, 9, 12, 8),
    ]


def pagina_fornecedores():
    return [
        texto("titulo_fornecedores", ["## Qual fornecedor não cumpre prazo?\n", "\n",
              "Entregas das consultorias, com o nome do fornecedor normalizado. "
              "Prazo real ÷ prometido acima de 1 é atraso. Em atraso hoje: em aberto com a data prometida vencida."],
              0, 0, 12, 2),
        tabela("tabela_fornecedores", "ds_fornecedores", "Por fornecedor", [
            ("fornecedor", "Fornecedor", None), ("grafias_no_cadastro", "Grafias no cadastro", None),
            ("entregas", "Entregas", None),
            ("prazo_real_sobre_prometido", "Prazo real ÷ prometido", INDICE),
            ("pct_no_prazo", "% no prazo", PCT), ("em_atraso_hoje", "Em atraso hoje", None),
        ], 0, 2, 12, 6),
        tabela("tabela_atrasos", "ds_atrasos", "Entregas em atraso hoje (16/10/2026)", [
            ("entrega_id", "Entrega", None), ("fornecedor", "Fornecedor", None), ("projeto_id", "Projeto", None),
            ("item", "Item", None), ("data_pedido", "Pedido em", None), ("data_prometida", "Prometida para", None),
            ("dias_em_atraso", "Dias em atraso", None), ("valor", "Valor", BRL),
        ], 0, 8, 12, 6),
    ]


def dashboard():
    def query_lines(sql):
        # cada linha termina com \n: o Databricks concatena os elementos sem separador
        return [linha + "\n" for linha in sql.strip().splitlines()]

    return {
        "datasets": [{"name": nome, "displayName": titulo, "queryLines": query_lines(sql)}
                     for nome, (titulo, sql) in DATASETS.items()],
        "pages": [
            {"name": "portfolio", "displayName": "Portfólio", "pageType": "PAGE_TYPE_CANVAS",
             "layoutVersion": "GRID_V1", "layout": pagina_portfolio()},
            {"name": "pessoas", "displayName": "Pessoas", "pageType": "PAGE_TYPE_CANVAS",
             "layoutVersion": "GRID_V1", "layout": pagina_pessoas()},
            {"name": "fornecedores", "displayName": "Fornecedores", "pageType": "PAGE_TYPE_CANVAS",
             "layoutVersion": "GRID_V1", "layout": pagina_fornecedores()},
        ],
        "uiSettings": {"theme": {
            # cores da Jornada: azul #0059DB e ciano #22C2F4, fundo #14141A no escuro
            "canvasBackgroundColor": {"light": "#F5F7FB", "dark": "#14141A"},
            "widgetBackgroundColor": {"light": "#FFFFFF", "dark": "#1C1C24"},
            "widgetBorderColor":     {"light": "#FFFFFF", "dark": "#1C1C24"},
            "fontColor":             {"light": "#14141A", "dark": "#EDEFF5"},
            "selectionColor":        {"light": "#0059DB", "dark": "#22C2F4"},
            "visualizationColors": ["#0059DB", "#22C2F4", "#7A5CFA", "#F6C344",
                                    "#FF5F46", "#2BB673", "#FF9F43", "#8B95A7"],
            "widgetHeaderAlignment": "LEFT",
        }},
    }


# ─── Teste das queries antes do deploy ───────────────────────────────────────────────
def sql_com_nome_completo(sql):
    padrao = r"\b(FROM|JOIN)\s+(" + "|".join(TABELAS_GOLD) + r")\b"
    return re.sub(padrao, r"\1 lakehouse_vertice.gold.\2", sql)


def testar(profile):
    sqls = [sql_com_nome_completo(sql) for _, sql in DATASETS.values()]
    r = subprocess.run(["databricks", "experimental", "aitools", "tools", "query", "--output", "json",
                        "--profile", profile, *sqls],
                       capture_output=True, text=True, encoding="utf-8",
                       env={**__import__("os").environ, "DATABRICKS_WAREHOUSE_ID": WAREHOUSE})
    if r.returncode != 0 and not r.stdout.strip():
        sys.exit(r.stderr)
    resultados = json.loads(r.stdout)
    falhas = 0
    for nome, res in zip(DATASETS, resultados):
        if res.get("state") != "SUCCEEDED":
            falhas += 1
            print(f"{nome:16} FALHOU: {res.get('error')}")
            continue
        linhas = res.get("rows") or []
        print(f"{nome:16} {len(linhas):>4} linhas")
        if nome == "ds_kpis":
            for k, v in zip(res["columns"], linhas[0]):
                print(f"{'':16}   {k} = {v}")
    return 1 if falhas else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--testar", action="store_true", help="roda as queries no warehouse em vez de gravar o JSON")
    ap.add_argument("--profile", help="profile do ~/.databrickscfg (obrigatório com --testar)")
    args = ap.parse_args()
    if args.testar:
        if not args.profile:
            sys.exit("--testar precisa de --profile")
        return testar(args.profile)
    SAIDA.write_text(json.dumps(dashboard(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    d = dashboard()
    widgets = sum(len(p["layout"]) for p in d["pages"])
    print(f"{SAIDA.relative_to(RAIZ)}: {len(d['datasets'])} datasets, {len(d['pages'])} páginas, {widgets} widgets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
