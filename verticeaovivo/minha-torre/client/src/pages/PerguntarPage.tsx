import { Badge, GenieChat } from '@databricks/appkit-ui/react';
import { useEffect, useState } from 'react';

interface QuemSou {
  email: string | null;
  usuario: string | null;
}

function ehQuemSou(x: unknown): x is QuemSou {
  return typeof x === 'object' && x !== null && 'email' in x;
}

const SUGESTOES = [
  'Quais projetos estão atrasados, e de quais clientes?',
  'Quanto esse atraso vai me custar?',
  'Tenho gente parada enquanto outro projeto pede gente?',
  'O que vai dar errado no próximo mês?',
  'Por que o PRJ-011 atrasou?',
];

export function PerguntarPage() {
  const [quem, setQuem] = useState<QuemSou | null>(null);

  useEffect(() => {
    fetch('/api/whoami')
      .then((r) => r.json())
      .then((corpo: unknown) => setQuem(ehQuemSou(corpo) ? corpo : null))
      .catch(() => setQuem(null));
  }, []);

  const identidade = quem?.email ?? quem?.usuario;

  return (
    <div className="space-y-4 w-full max-w-5xl mx-auto">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-2xl font-semibold text-foreground">Perguntar</h2>
          <p className="text-sm text-muted-foreground">
            O agente Farol · Diretoria (Genie) escreve o SQL, roda na gold e responde citando os números. Os KPIs vêm
            da metric view mv_projetos, a mesma fórmula do dashboard. Dados de 16/10/2026.
          </p>
        </div>
        <Badge variant="outline">
          {identidade ? `respondendo em nome de ${identidade}` : 'respondendo em nome de quem está logado'}
        </Badge>
      </div>

      <div className="text-xs text-muted-foreground">
        Experimente: {SUGESTOES.map((s, i) => (
          <span key={s}>
            “{s}”{i < SUGESTOES.length - 1 ? ' · ' : ''}
          </span>
        ))}
      </div>

      <div className="h-[65vh] min-h-[420px] rounded-md border">
        <GenieChat alias="default" />
      </div>

      <p className="text-xs text-muted-foreground">
        Resposta gerada por IA: confira o SQL que o agente mostra junto de cada resposta antes de decidir. O Genie só
        enxerga as tabelas que o Unity Catalog libera para você.
      </p>
    </div>
  );
}
