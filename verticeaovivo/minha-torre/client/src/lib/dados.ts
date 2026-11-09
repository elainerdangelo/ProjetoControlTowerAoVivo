import { useEffect, useState } from 'react';

// O warehouse devolve TODO número como string (DECIMAL, BIGINT, DOUBLE...).
// num() antes de qualquer conta ou formatação.
export function num(valor: unknown): number {
  const n = Number(valor);
  return Number.isFinite(n) ? n : 0;
}

const brl = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
const brlCompacto = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
  notation: 'compact',
  maximumFractionDigits: 1,
});
const indice = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const decimal1 = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const pct = new Intl.NumberFormat('pt-BR', { style: 'percent', maximumFractionDigits: 0 });

export const fmt = {
  brl: (v: unknown) => brl.format(num(v)),
  brlCompacto: (v: unknown) => brlCompacto.format(num(v)),
  indice: (v: unknown) => indice.format(num(v)),
  decimal1: (v: unknown) => decimal1.format(num(v)),
  inteiro: (v: unknown) => inteiro.format(num(v)),
  pct: (v: unknown) => pct.format(num(v)),
};

// O "hoje" do dataset. Nunca new Date().
export const DATA_REFERENCIA = '16/10/2026';

export const CAUSAS: Record<string, string> = {
  change_freeze: 'change freeze',
  falta_sre: 'falta de SRE',
  dependencia_fornecedor: 'dependência de fornecedor',
  rotatividade: 'rotatividade',
  mudanca_escopo: 'mudança de escopo',
  bug_retrabalho: 'bug e retrabalho',
  aprovacao_cliente: 'aprovação do cliente',
  outro: 'outro',
};

export const rotuloCausa = (causa: string | null | undefined) => (causa ? (CAUSAS[causa] ?? causa) : '—');

// ─── Score do modelo (opcional): vem da rota do servidor, nunca de config/queries ──────
export interface LinhaScore {
  projeto_id: string;
  prob_estouro_30d: number;
  ranking: number | null;
  faixa_risco: string;
  principais_fatores: string | null;
}

export interface Score {
  carregando: boolean;
  disponivel: boolean;
  porProjeto: Map<string, LinhaScore>;
  altoRisco: number;
}

function ehRespostaScore(x: unknown): x is { disponivel: boolean; linhas: LinhaScore[] } {
  return typeof x === 'object' && x !== null && 'disponivel' in x && 'linhas' in x && Array.isArray(x.linhas);
}

export function useScoreEstouro(): Score {
  const [score, setScore] = useState<Score>({
    carregando: true,
    disponivel: false,
    porProjeto: new Map(),
    altoRisco: 0,
  });

  useEffect(() => {
    let ativo = true;
    fetch('/api/score-estouro')
      .then((r) => r.json())
      .then((corpo: unknown) => {
        if (!ativo) return;
        const resposta = ehRespostaScore(corpo) ? corpo : { disponivel: false, linhas: [] };
        const porProjeto = new Map(
          resposta.linhas.map((l) => [l.projeto_id, { ...l, prob_estouro_30d: num(l.prob_estouro_30d) }]),
        );
        setScore({
          carregando: false,
          disponivel: resposta.disponivel,
          porProjeto,
          altoRisco: resposta.linhas.filter((l) => l.faixa_risco === 'alto').length,
        });
      })
      .catch(() => {
        if (ativo) setScore({ carregando: false, disponivel: false, porProjeto: new Map(), altoRisco: 0 });
      });
    return () => {
      ativo = false;
    };
  }, []);

  return score;
}
