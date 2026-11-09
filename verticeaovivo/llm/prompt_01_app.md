# Prompt 1 · O app da Torre: o projeto ganha uma URL

**Entrega:** um Databricks App (AppKit, React + TypeScript) com o login do workspace e duas telas:
**Projetos em risco** (com a chance de estouro do modelo, se existir) e **Simulador de realocação**.
A terceira, **Perguntar**, chega no prompt 2, quando o agente nasce. **Deploy nº 1 da noite** =
`databricks apps deploy`.

> Quatro noites de trabalho estão atrás de um SQL Editor. Um dado que só o time de dados consegue
> abrir é um dado que não existe para a empresa. O dono não abre SQL Editor. Hoje o Farol ganha uma URL.

---

## Antes da aula (instrutor): o plano B

É o prompt com mais peças móveis (limite de apps, permissões, consentimento OAuth, build). Deixe o
gabarito **publicado e testado antes de entrar ao vivo**:

```bash
bash aulas/aula-04-produtos-de-dados-ia/torre-app/scripts/subir-tudo.sh <perfil>
```

Se o deploy ao vivo travar, abra a URL do `farol-torre` e siga a aula por ele. O que importa mostrar
é o app funcionando, as telas e a conta do simulador.

---

## O que mostrar antes

`databricks apps list --profile <perfil>`: o Free Edition aceita **no máximo 3 apps**. Se já houver
três, apague um que você não usa mais (`databricks apps delete <nome>`).

`databricks apps init` monta um projeto React em menos de 10 segundos. Mostre a árvore:
`config/queries/*.sql` (leitura), `server/server.ts` (rotas), `client/src/pages/` (telas).

**Enquanto o Claude Code trabalha, você explica:**

- **Leitura é arquivo `.sql`.** O `typegen` lê o Unity Catalog e escreve os tipos TypeScript: o
  `COMMENT` que a noite 3 exigiu em toda tabela vira documentação dentro do editor.
- **O app é um usuário.** Ele roda como um *service principal* (um "usuário robô") que nasce sem
  acesso a nada. `CAN_USE` no warehouse dá o computador, não o dado: sem os `GRANT`, o build falha
  (`INSUFFICIENT_PERMISSIONS`). **É esperado**, e é a melhor aula de governança da semana.
- **O simulador mostra a conta.** O dono não aprova caixa-preta: a tela diz de onde vem cada número
  (horas paradas × 4 semanas, dias de impacto do status ÷ 90 × 30, uma semana de onboarding). E o que
  não vira dinheiro sem premissa (dias de cronograma) fica fora da conta em R$.
- **O número vem como string** do warehouse. `Number()` antes de qualquer conta.
- **O app cresce por plugins.** Hoje só o `analytics` (ler a gold). No prompt 2 entra o `genie`, e o
  app passa a perguntar ao agente **em nome de quem está logado**.

---

## O prompt

```
Leia o CLAUDE.md da raiz e aulas/aula-04-produtos-de-dados-ia/prd/CLAUDE.md.
Use as skills databricks-apps e databricks-app-design. A gold já existe. O score do modelo (gold.score_estouro_30d)
pode NÃO existir: nenhuma query de config/queries pode depender dele.

1. Confira `databricks apps list --profile <perfil>` (limite de 3 apps no
   Free Edition) e crie o app numa pasta minha-torre/ na raiz deste
   repositório, só com o plugin analytics (o Genie entra no prompt 2):
   databricks apps init --name minha-torre \
     --features analytics \
     --set analytics.sql-warehouse.id=<warehouse> \
     --run none --profile <perfil>
   O app é um bundle próprio, dentro da pasta do bundle vertice. Acrescente
   ao databricks.yml da RAIZ (o do vertice) sync: { exclude: ["minha-torre/**"] },
   senão o deploy do vertice sobe o node_modules do app inteiro.

2. config/queries (apague os exemplos do template):
   - kpis.sql: projetos em andamento, em risco (atenção + crítico),
     críticos, melancias, estouro previsto e carteira
     (projeto_situacao_atual). Nada do score aqui.
   - projetos_risco.sql: projetos em andamento do pior para o melhor, com
     SPI, CPI, estouro, atraso projetado, farol do gerente × calculado,
     melancia, a causa mais frequente no status_estruturado dos últimos 90
     dias e os dias de impacto por falta_sre e por rotatividade.
   - pessoas_ociosas.sql: pessoas com utilização < 20% nas últimas 12
     semanas (utilizacao_pessoa_semana), com horas paradas e custo ocioso
     MÉDIOS por semana e custo_hora.
   A probabilidade por projeto (gold.score_estouro_30d) vem de uma rota
   GET /api/score-estouro no servidor que responde {disponivel, linhas}:
   se a tabela não existir, a tela mostra "—" em vez de quebrar o build.
   O KPI "alto risco em 30 dias" (faixa_risco = 'alto') sai dessa rota.

3. Telas (português, R$, índices com 2 casas, Number() em tudo que vem do
   warehouse):
   - Projetos em risco: 4 KPIs (em risco, estouro previsto, carteira, alto
     risco em 30 dias) + tabela (situação com cor: crítico vermelho, atenção
     âmbar; farol do gerente com 🍉 quando é melancia; coluna P(estouro)).
   - Simulador: escolher uma pessoa ociosa e um projeto destino (só atenção
     ou crítico; para SRE, ordene pelos dias de falta_sre); mostrar horas no
     mês (× 4 semanas), ociosidade que deixa de ser paga, dias de cronograma
     recuperados (dias de impacto da causa nos últimos 90 dias ÷ 90 × 30),
     mobilização = horas de onboarding (editável, 40) × custo_hora, e saldo.
     Explique a conta num <details>.
   Menu com as duas telas (a terceira, Perguntar, entra no prompt 2).
   Sem cache no createApp. Título "Projeto Farol".

4. npm run typecheck, npm run lint, databricks apps validate.
   Depois: databricks bundle deploy --profile <perfil> (cria o app e o
   service principal). Crie scripts/conceder-acesso.sh (lê o
   service_principal_client_id com apps get e dá USE CATALOG em
   lakehouse_vertice e USE SCHEMA + SELECT na gold e na silver), rode e
   faça databricks apps deploy --profile <perfil>. Me mostre a URL.
```

---

## O que conferir

- `apps validate`: typegen, lint, typecheck e build ✅.
- Sem os `GRANT`, o `apps deploy` falha com `INSUFFICIENT_PERMISSIONS` no typegen do build: **é esperado**.
- Na URL: **17 de 41** projetos em risco (7 críticos, 4 com farol
  verde), **R$ 6,5 mi** de estouro, **18** em alto risco em 30 dias ("—" sem o modelo); PRJ-016 e PRJ-030 no topo,
  PRJ-011 com causa "falta de SRE", **PRJ-024** com 46% na coluna P(estouro) ("—" sem o modelo).
- Simulador: **COL0017** (SRE sênior, PRJ-007, uso de 6%) → **PRJ-011** dá **151 h** no mês,
  **R$ 30,1 mil** de ociosidade evitada, **19,0 dias** de cronograma recuperados, R$ 8,0 mil de
  onboarding e **saldo de R$ 22,1 mil** no mês.

> *"O dono abre isso no celular, com o login da empresa. Vê quem está em risco, quem vai entrar em
> risco no mês que vem, e simula mover uma SRE parada para o projeto que pede SRE há doze semanas.
> Ninguém escreveu SQL para ele."*

---

## Se der errado

| Sintoma | Causa | Correção |
|---|---|---|
| `reached the maximum limit of 3 apps` | o Free Edition aceita 3 apps | apague um app que não usa mais |
| `Error building app` + `INSUFFICIENT_PERMISSIONS` nos logs | o service principal não tem `USE CATALOG` | `bash scripts/conceder-acesso.sh <perfil> minha-torre` e `apps deploy` de novo |
| `TABLE_OR_VIEW_NOT_FOUND` no `apps validate` | query de `config/queries` aponta para tabela que não existe | tabela opcional (o score) vai numa rota do servidor, nunca em `config/queries` |
| typegen marca tudo `OFFLINE` em 0 s | o `.env` não foi carregado / warehouse parado | `set -a; . ./.env; set +a` e `npm run typegen -- --wait` |
| Valores como `6465127.22` sem formatação | número veio como string | `Number()` (ou `num()` do `lib/dados.ts`) |
| `name must be ≤ 26 characters` | nome do app longo | `minha-torre` |
| Deploy cria o app mas ele fica parado | usou só `bundle deploy` | `databricks apps deploy` |
| `Requested node type [UNKNOWN] is not supported` | arquivo `*.geniespace.json` dentro da pasta do app | nenhum `*.geniespace.json` no app (o do Genie mora no bundle `vertice`) |

**Tempo medido (edição anterior, mesmo app):** `apps init` ~10 s; `apps validate` ~9 s; redeploy com
permissão ~45 s a 1 min.
