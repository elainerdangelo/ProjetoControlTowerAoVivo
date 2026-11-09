# Prompt 2 · Gold — o produto de dados e as perguntas do dono

**Entrega:** a gold no mesmo pipeline, com três tabelas (`fato_projeto_semana`,
`projeto_situacao_atual` e `utilizacao_pessoa_semana`), e a tarefa `testes_de_qualidade`, que quebra o job se algo
estiver errado. **Deploy nº 3.**

---

## O que mostrar antes

A lógica da gold é de trás para frente. Escreva no quadro:

```
pergunta do dono → KPI → grão → tabela gold → silver que ela lê
"quais projetos estão atrasados?" → SPI, CPI → projeto hoje → projeto_situacao_atual
"está piorando?"                  → SPI, CPI → projeto × semana → fato_projeto_semana
```

E a pergunta que a turma tem que responder antes do prompt: **de onde vem o
histórico?** Excel, ClickUp e Project só guardam o % de hoje. O único lugar com o %
de cada semana é o **status semanal** que o gerente publica toda sexta. Por isso o
fato semanal usa o % do status, e a fotografia de hoje usa as tarefas.

**Enquanto ele trabalha, você explica:**

- **PV, EV e AC são acumulados.** O EV da semana 40 é tudo que ficou pronto até a
  semana 40. Por isso nunca se soma EV de semanas diferentes do mesmo projeto.
- **Projeto concluído para de publicar status.** O último % vale para as semanas
  seguintes: `last_value(pct, true) OVER (...)`.
- **O farol do gerente vira coluna, e o farol pelo número também.** Lado a lado, eles
  respondem o bônus do dono: *posso confiar no farol?*
- **Uma tabela por pergunta, nem uma a mais.** Fornecedor não ganha tabela gold: a
  `silver.entregas_fornecedor` já tem o nome normalizado e responde direto.
- **Teste que quebra o job.** `raise_error()` dentro de `CASE WHEN`. Melhor o
  dashboard ficar com o dado da semana passada do que com o dado errado de hoje.

---

## O prompt

```
Continue o bundle na raiz deste repositório. A silver está pronta.
Agora a gold, no MESMO pipeline vertice_medalhao: acrescente o glob
../src/gold/** em libraries. Os arquivos da gold escrevem com o nome completo
lakehouse_vertice.gold.<tabela>; leem a silver pelo nome curto. COMMENT em todas.
O "hoje" é DATE'2026-10-16'. Nunca current_date().

src/gold/01-fato-projeto-semana.sql → lakehouse_vertice.gold.fato_projeto_semana
Uma linha por projeto e semana (sexta-feira), da semana do início até
2026-10-16 (sequence(..., INTERVAL 1 WEEK) + explode). Colunas:
- pv: orçamento × Σ horas × fração do baseline decorrida até a semana ÷ Σ horas
  (greatest(0, least(1, datediff(semana, inicio)/datediff(fim, inicio))))
- ev: orçamento × pct_concluido do status_semanal daquela sexta ÷ 100. Projeto
  concluído não publica mais: use o último % (last_value(pct, true) OVER).
- ac: custo real acumulado (silver.custos por semana, soma acumulada)
- spi = ev/pv, cpi = ev/ac (try_divide, 4 casas), eac = orcamento / cpi
- farol_do_gerente (o último farol publicado)
- horas_disponiveis, horas_apontadas e horas_ociosas da semana (apontamentos)
- EXPECT pv >= 0 e ev <= orcamento, FAIL UPDATE.

src/gold/02-situacao-e-pessoas.sql
- projeto_situacao_atual: a fotografia de 2026-10-16 de cada projeto (60
  linhas). Traz o cadastro (projeto = projeto_id · nome, cliente, segmento,
  tipo_projeto, ferramenta, gerente_projeto, valor_contrato, orcamento,
  data_inicio, data_fim_baseline, duracao_baseline_dias, status) e os KPIs
  calculados sobre silver.tarefas (o % de hoje das ferramentas): pv, ev, ac, spi, cpi, eac, estouro_previsto = greatest(eac - orcamento, 0),
  margem_projetada, atraso_projetado_dias, termino_projetado, situacao
  ('concluído' se status <> em_andamento; 'crítico' se SPI ou CPI < 0,8;
  'atenção' se < 0,9; senão 'ok'), farol_do_gerente (status de hoje),
  farol_calculado (regra do manual: verde >= 0,95; amarelo >= 0,90) e
  melancia (em andamento, farol do gerente verde e SPI < 0,9).
- utilizacao_pessoa_semana: pessoa × projeto × semana com nome, papel,
  senioridade, horas disponíveis, apontadas, ociosas, utilizacao,
  custo_ocioso (horas ociosas × custo_hora) e o spi_do_projeto naquela semana.
Não crie dim_projeto nem tabela gold de fornecedor: o cadastro já está na
projeto_situacao_atual, e fornecedor é lido direto da silver.entregas_fornecedor.

src/testes/testes.sql (sql_task) — cada teste com raise_error se falhar:
 1 os 60 projetos têm cronograma na silver.tarefas
 2 cada projeto veio de UMA ferramenta, a do cadastro do PMO
 3 as horas do Excel na silver = a soma das linhas de TOTAL das planilhas
 4 uma linha por pessoa na silver
 5 a CodeForge virou um fornecedor só
 6 a limpeza não mudou o custo total (bronze com replace = silver)
 7 os 60 projetos têm fotografia de hoje
 8 todo projeto em andamento tem SPI e CPI
 9 o EV de hoje do status semanal bate com o das ferramentas (diferença < 1%)
10 AC de hoje no fato = soma dos lançamentos até hoje

Acrescente ao job a tarefa testes_de_qualidade, depois de medalhao.

Trabalhe direto: o EXPECT e os testes são a conferência. Nunca dispare um
run com outro ainda ativo (limite de compute do Free Edition).

Rode e me mostre a saída (só o medalhão e os testes; a bronze não muda):
  databricks bundle deploy --profile DEFAULT
  databricks bundle run vertice_farol --only medalhao,testes_de_qualidade --profile DEFAULT
```

---

## O que conferir

```sql
SELECT situacao, COUNT(*) AS projetos, ROUND(SUM(estouro_previsto) / 1e6, 2) AS estouro_mi,
       COUNT_IF(melancia) AS melancias
FROM lakehouse_vertice.gold.projeto_situacao_atual GROUP BY situacao;
-- crítico 7 · atenção 10 (4 melancias) · ok 24 · concluído 19

SELECT ROUND(SUM(estouro_previsto) / 1e6, 2) FROM lakehouse_vertice.gold.projeto_situacao_atual
WHERE status = 'em_andamento';
-- 6,47. O mesmo número do rascunho da noite 1: a gold confirma o rascunho, agora com contrato e teste.
```

```sql
-- a pergunta 3 do dono: gente parada
SELECT colaborador_id, nome, papel, projeto_id,
       ROUND(SUM(horas_apontadas) / SUM(horas_disponiveis), 3) AS utilizacao, SUM(horas_ociosas) AS horas_paradas
FROM lakehouse_vertice.gold.utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY ALL ORDER BY utilizacao LIMIT 5;
-- COL0018 e COL0017: duas SREs seniores a 5% no PRJ-007, que ainda está no desenho
```

> *"O dono perguntou se tem gente parada. Tem: duas SREs seniores, mais de 450 horas
> paradas cada uma em 12 semanas. E no próximo prompt a IA vai mostrar quem está pedindo SRE."*

---

## Se der errado

| Sintoma | Causa | Correção |
|---|---|---|
| `window function inside an aggregate function` | `SUM(... last_value() ...)` no mesmo SELECT | CTE com a janela, depois a conta |
| `Failed to read dataset ... could not be resolved` | Erro numa tabela anterior do grafo | Leia o primeiro ERROR do evento, não o último |
| Teste 3 falha | A linha de TOTAL entrou, ou alguma linha com 'h' não converteu | `WHERE tarefa <> 'TOTAL'` e `replace(horas, 'h', '')` |
| Teste 9 falha | O fato somou semanas ou o % do status não foi preenchido para frente | `last_value(pct, true)` por projeto, ordenado por semana |
| 61 linhas em projeto_situacao_atual | Join duplicando o farol | O farol vem do status com `data_status = DATE'2026-10-16'` (um por projeto) |

**Tempo medido:** pipeline com silver + gold ~2 min; job completo até os testes ~3 min.
