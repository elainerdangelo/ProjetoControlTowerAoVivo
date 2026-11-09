import { createApp, analytics, genie, server, getWarehouseId, ServiceContext } from '@databricks/appkit';

// Tabela opcional: o score do modelo de estouro (bônus da noite 4) pode não existir.
// Por isso ela NÃO fica em config/queries (o typegen do build quebraria): é lida aqui,
// e a rota responde { disponivel: false } quando a tabela não existe.
const TABELA_SCORE = 'lakehouse_vertice.gold.score_estouro_30d';

interface LinhaScore {
  projeto_id: string;
  prob_estouro_30d: number;
  ranking: number | null;
  faixa_risco: string;
  principais_fatores: string | null;
}

function paraNumero(valor: string | null | undefined): number | null {
  if (valor === null || valor === undefined || valor === '') return null;
  const n = Number(valor);
  return Number.isFinite(n) ? n : null;
}

async function lerScore(): Promise<{ disponivel: boolean; linhas: LinhaScore[]; motivo?: string }> {
  const { client } = ServiceContext.get();
  const warehouseId = await getWarehouseId();
  const resposta = await client.statementExecution.executeStatement({
    warehouse_id: warehouseId,
    statement: `SELECT projeto_id, prob_estouro_30d, ranking, faixa_risco, principais_fatores
                FROM ${TABELA_SCORE}
                WHERE data_referencia = (SELECT max(data_referencia) FROM ${TABELA_SCORE})`,
    wait_timeout: '30s',
  });

  if (resposta.status?.state !== 'SUCCEEDED') {
    // TABLE_OR_VIEW_NOT_FOUND (o modelo ainda não rodou) ou qualquer outra falha:
    // a tela mostra "—" em vez de quebrar.
    return { disponivel: false, linhas: [], motivo: resposta.status?.error?.message ?? resposta.status?.state };
  }

  const colunas = (resposta.manifest?.schema?.columns ?? []).map((c) => c.name ?? '');
  const linhas = (resposta.result?.data_array ?? []).map((valores) => {
    const linha: Record<string, string | null> = {};
    colunas.forEach((nome, i) => {
      linha[nome] = (valores[i] as string | null | undefined) ?? null;
    });
    return {
      projeto_id: linha.projeto_id ?? '',
      prob_estouro_30d: paraNumero(linha.prob_estouro_30d) ?? 0,
      ranking: paraNumero(linha.ranking),
      faixa_risco: linha.faixa_risco ?? '',
      principais_fatores: linha.principais_fatores,
    };
  });
  return { disponivel: true, linhas };
}

createApp({
  plugins: [
    analytics(),
    // O Genie "Farol · Diretoria", no apelido "default" (o <GenieChat alias="default" /> da tela Perguntar).
    // O id vem do recurso genie-space do app (app.yaml → DATABRICKS_GENIE_SPACE_ID).
    genie({ spaces: { default: process.env.DATABRICKS_GENIE_SPACE_ID ?? '' } }),
    server(),
  ],
  onPluginsReady(appkit) {
    appkit.server.extend((app) => {
      // Quem está logado: a tela Perguntar mostra em nome de quem o Genie responde.
      app.get('/api/whoami', (req, res) => {
        res.json({
          email: req.header('x-forwarded-email') ?? null,
          usuario: req.header('x-forwarded-preferred-username') ?? req.header('x-forwarded-user') ?? null,
        });
      });

      app.get('/api/score-estouro', async (_req, res) => {
        try {
          res.json(await lerScore());
        } catch (erro) {
          res.json({ disponivel: false, linhas: [], motivo: erro instanceof Error ? erro.message : String(erro) });
        }
      });
    });
  },
}).catch(console.error);
