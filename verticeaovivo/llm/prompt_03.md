# Prompt 3 · O job completo: a Torre roda sozinha, e lê o texto do status

**Entrega:** o job `vertice_farol` inteiro, da ingestão aos testes, agendado para toda segunda às
6h, com a última camada da noite: `gold.status_estruturado`, a causa de cada atraso tirada do texto
livre do status semanal por IA. **Deploy nº 4** e a primeira execução de ponta a ponta.

---

## O que mostrar antes

O DAG do `vertice_farol` como está agora: ingestão → conferência → medalhão → testes. Pergunte:
*"isso responde as perguntas 1 e 2 do dono (quem atrasa e quanto custa). E a 3: tenho gente
parada enquanto outro projeto pede gente? Quem pede gente, e onde está escrito?"*

Um status de verdade:

```sql
SELECT data_status, farol, texto_status FROM lakehouse_vertice.silver.status_semanal
WHERE projeto_id = 'PRJ-011' ORDER BY data_status DESC LIMIT 5;
-- "Bloqueios: Sem SRE alocado: pipeline de deploy quebrado e ninguém para corrigir."
-- "Bloqueios: Ambiente de homologação fora do ar há 5 dias, sem responsável de infraestrutura."
```

*"A causa do atraso do PRJ-011 está escrita aqui, toda sexta, há doze semanas. Ninguém
cruzou isso com o timesheet, onde duas SREs estão paradas em outro projeto."*

E a IA, ao vivo, em duas linhas:

```sql
SELECT ai_classify('Sem SRE alocado: pipeline de deploy quebrado. Impacto estimado: 1 semana.',
         '["change_freeze","falta_sre","dependencia_fornecedor","rotatividade","mudanca_escopo","bug_retrabalho","aprovacao_cliente","sem_bloqueio"]',
         map('version','2.0')):response[0]::STRING;
-- falta_sre

SELECT ai_extract('Sem SRE alocado: pipeline de deploy quebrado. Impacto estimado: 1 semana.',
         '{"bloqueio":{"type":"string"},"quem_destrava":{"type":"string"},"dias_impacto":{"type":"number","description":"1 semana = 7"}}',
         map('version','2.0')):response;
-- {"bloqueio":"Sem SRE alocado e pipeline de deploy quebrado","quem_destrava":"Time SRE","dias_impacto":7}
```

**Enquanto ele trabalha, você explica:**

- **`ai_classify` escolhe; `ai_extract` tira.** A classificação põe o texto numa lista
  fechada (dá para agrupar). A extração tira campos, e com o **schema tipado** da versão
  2.0 o `dias_impacto` já sai como **número**: "1 semana" vira 7, e dá para somar.
- **IA custa, e custa por linha.** Medimos neste workspace: as duas funções juntas levam
  ~5 s por status. Os 3,9 mil levariam uma hora de warehouse. Então cada ferramenta onde
  ela é a certa:
  - **regra** para o que tem padrão fixo: a semana sem bloqueio (três em cada quatro
    status) e o status vazio. Custo zero, resposta exata.
  - **IA** para o texto com bloqueio dos últimos 90 dias (~160 status, ~2 minutos).
  - **palavra-chave** para o histórico antigo, onde a resposta não muda decisão.
- **`MERGE` incremental.** A tarefa só processa texto que ainda não está na tabela. Na
  semana que vem ela processa só os status da semana que vem. Não reprocesse o passado.
- **O DAG é a documentação.** Duas tarefas em paralelo (testes e IA) depois do medalhão: o
  job não espera uma terminar para começar a outra, porque uma não lê a outra.
- **Falhou no meio? Repair.** Se a IA falhar, o **Repair run** roda só ela e o que vem
  depois. A ingestão de 4 minutos não roda de novo.

---

## O prompt

```
Continue o bundle na raiz deste repositório. A gold e os testes estão
prontos. Agora a última camada da noite, e o job inteiro rodando sozinho.

1. O texto livre do status vira coluna. Use as funções de IA na versão 2.0
   (map('version','2.0')); o resultado é VARIANT, lido com ':response'.

   src/ia/status_estruturado.sql (sql_task, caminho completo das tabelas)
   a. CREATE TABLE IF NOT EXISTS lakehouse_vertice.gold.status_estruturado com
      COMMENT em cada coluna: projeto_id, data_status, farol, causa_bloqueio,
      bloqueio, quem_destrava, dias_impacto (DOUBLE), metodo ('regra', 'ia' ou
      'palavra_chave'), texto_status, _classificado_em.
      NÃO é CREATE OR REPLACE: a tabela acumula, e a IA não pode ser refeita
      a cada execução.
   b. MERGE INTO ... WHEN NOT MATCHED THEN INSERT, só com os status da
      silver.status_semanal que ainda não estão na tabela (LEFT ANTI JOIN por
      projeto_id e data_status). Para cada status:
      - metodo = 'regra' se status_vazio ou se o texto (minúsculas) diz
        'bloqueios: nenhum', 'sem bloqueios' ou 'nada relevante';
        'ia' se data_status >= DATE'2026-07-18' (últimos 90 dias);
        senão 'palavra_chave'.
      - causa_bloqueio: 'nao_reportado' se vazio; 'sem_bloqueio' na regra;
        na IA, ai_classify com a lista ["change_freeze","falta_sre",
        "dependencia_fornecedor","rotatividade","mudanca_escopo",
        "bug_retrabalho","aprovacao_cliente","sem_bloqueio"]; na
        palavra-chave, RLIKE: freeze|congelamento|janela de deploy →
        change_freeze; sre|infraestrutura|ambiente de homologação → falta_sre;
        forge|consultoria|fornecedor → dependencia_fornecedor; saída de|
        rotatividade|onboarding → rotatividade; escopo|change request|regra de
        negócio → mudanca_escopo; bugs|regressão|refazendo → bug_retrabalho;
        aprovação do cliente|homologação do cliente → aprovacao_cliente.
      - só na IA: ai_extract com JSON schema tipado: bloqueio (string),
        quem_destrava (string), dias_impacto (number, "1 semana = 7").
      - dias_impacto fora da IA: regex em 'impacto estimado de N dias' e
        'impacto estimado: 1 semana' (= 7).
   c. No fim, um SELECT de leitura: quantos status por metodo e causa.

   Acrescente ao job a tarefa status_com_ia, depois de medalhao (em paralelo
   com testes_de_qualidade).

2. O job inteiro
   - confira em resources/vertice.job.yml a ordem: ingestao_feriados e
     ingestao_data_lake em paralelo → conferencia_bronze → medalhao →
     testes_de_qualidade e status_com_ia em paralelo
   - agendamento toda segunda às 6h (America/Sao_Paulo); no dev ele fica
     pausado pelo preset, e está certo
   - max_concurrent_runs: 1 (duas execuções ao mesmo tempo apagariam a
     bronze uma da outra)
   - atualize o comentário do topo com as 6 tarefas e o que cada uma faz

Rode e me mostre a saída:
  databricks bundle validate --profile DEFAULT
  databricks bundle deploy --profile DEFAULT
  databricks bundle run vertice_farol --only medalhao+ --profile DEFAULT
(medalhao+ = o medalhão e tudo depois dele: testes e IA, em paralelo. A
ingestão já rodou; o job inteiro roda sozinho toda segunda às 6h.)
E no fim, numa tabela: cada tarefa, quanto tempo levou e o resultado.
```

---

## O que conferir

Abra o `vertice_farol` no workspace: o DAG com as **seis caixas**, e nesta execução o medalhão, os testes e a IA verdes, com o gráfico de tempo de cada tarefa
(a ingestão do data lake e o medalhão são as mais longas).

```sql
-- a pergunta "por que o PRJ-011 atrasou?" agora tem resposta em dado
SELECT causa_bloqueio, COUNT(*) AS semanas, SUM(coalesce(dias_impacto, 0)) AS dias_de_impacto
FROM lakehouse_vertice.gold.status_estruturado
WHERE projeto_id = 'PRJ-011' AND data_status >= DATE'2026-07-18'
  AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
GROUP BY 1 ORDER BY 2 DESC;
-- falta_sre · 12 semanas · 57 dias de impacto declarado

-- quanto cada método classificou
SELECT metodo, COUNT(*) FROM lakehouse_vertice.gold.status_estruturado GROUP BY 1;
-- ia 163 · regra 2.954 · palavra_chave 794
```

**Rode o job de novo:** a ingestão recarrega a bronze, o medalhão recalcula, e o `MERGE` da IA
insere **zero** linhas e termina em segundos. É o incremental funcionando, e a conta de IA que
não se paga duas vezes.

> *"O PRJ-011 pede SRE há doze semanas. As duas SREs da empresa estão a 5% no PRJ-007. Os dois
> fatos estavam no dado o tempo todo, em sistemas diferentes. Agora estão na mesma tabela, e toda
> segunda às 6h eles se atualizam sozinhos."*

---

## Se der errado

| Sintoma | Causa | Correção |
|---|---|---|
| A tarefa da IA leva mais de 10 minutos | IA rodando em todos os 3,9 mil status | Confira o `metodo`: só os últimos 90 dias **com bloqueio** vão para a IA |
| `dias_impacto` vem como texto `"7"` | `ai_extract` sem schema (versão 1) | JSON schema com `"type": "number"` e `map('version','2.0')`, lido com `::DOUBLE` |
| `causa_bloqueio` nulo nas linhas da IA | Leu o VARIANT sem `:response[0]` | `ai_classify(...):response[0]::STRING` |
| `TABLE_OR_VIEW_ALREADY_EXISTS` | Usou CREATE TABLE sem IF NOT EXISTS | `CREATE TABLE IF NOT EXISTS` (a tabela acumula) |
| Rodou de novo e inseriu tudo outra vez | Faltou o LEFT ANTI JOIN | O MERGE só recebe o que ainda não está na tabela |
| `testes_de_qualidade` falhou e a IA rodou mesmo assim | As duas dependem só do medalhão | É o desenho: os testes barram o que vem **depois** deles (na noite 4, o modelo) |
| Uma tarefa falhou no meio | Qualquer erro numa camada | **Repair run** no workspace: refaz só a que falhou e as seguintes |

**Tempo medido (21/10):** com `--only medalhao+`, ~5 min (medalhão ~2 min, IA ~2 min 40 s em paralelo com os testes). O job inteiro, sem `--only`, leva ~8 min: data lake 2 min 53 s (feriados 81 s, em paralelo) · conferência 30 s · medalhão 1 min 52 s · IA 2 min 38 s (163 textos) · testes 21 s, em paralelo com a IA. Com as tarefas do ML da noite 4, 9 min 55 s.
