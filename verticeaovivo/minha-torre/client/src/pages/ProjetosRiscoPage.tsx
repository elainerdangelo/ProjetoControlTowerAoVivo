import {
  useAnalyticsQuery,
  Alert,
  AlertDescription,
  AlertTitle,
  Badge,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
  Skeleton,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@databricks/appkit-ui/react';
import type { ReactNode } from 'react';
import { DATA_REFERENCIA, fmt, num, rotuloCausa, useScoreEstouro } from '../lib/dados';

function Kpi({ titulo, valor, detalhe, carregando }: { titulo: string; valor: ReactNode; detalhe: string; carregando: boolean }) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardDescription>{titulo}</CardDescription>
        {carregando ? <Skeleton className="h-8 w-28" /> : <CardTitle className="text-3xl tabular-nums">{valor}</CardTitle>}
      </CardHeader>
      <CardContent className="text-xs text-muted-foreground">{detalhe}</CardContent>
    </Card>
  );
}

function BadgeSituacao({ situacao }: { situacao: string }) {
  if (situacao === 'crítico') return <Badge className="bg-destructive text-destructive-foreground">crítico</Badge>;
  if (situacao === 'atenção') return <Badge className="bg-warning text-warning-foreground">atenção</Badge>;
  return <Badge variant="outline">{situacao}</Badge>;
}

function Erro({ mensagem }: { mensagem: string }) {
  return (
    <Alert variant="destructive">
      <AlertTitle>Não foi possível ler a gold</AlertTitle>
      <AlertDescription>{mensagem}</AlertDescription>
    </Alert>
  );
}

export function ProjetosRiscoPage() {
  const kpis = useAnalyticsQuery('kpis', {});
  const projetos = useAnalyticsQuery('projetos_risco', {});
  const score = useScoreEstouro();

  const k = kpis.data?.[0];
  const semModelo = !score.carregando && !score.disponivel;

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <div>
        <h2 className="text-2xl font-semibold text-foreground">Projetos em risco</h2>
        <p className="text-sm text-muted-foreground">
          Quais projetos estão atrasados, quanto isso vai custar, e quem vai entrar em risco no mês que vem?
          Fotografia de {DATA_REFERENCIA} · fonte: gold.projeto_situacao_atual (recalculada toda segunda às 6h).
        </p>
      </div>

      {kpis.error && <Erro mensagem={kpis.error} />}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <Kpi
          titulo="Projetos em risco"
          carregando={kpis.loading}
          valor={k ? `${fmt.inteiro(k.em_risco)} de ${fmt.inteiro(k.em_andamento)}` : '—'}
          detalhe={k ? `atenção + crítico · ${fmt.inteiro(k.criticos)} críticos · ${fmt.inteiro(k.melancias)} melancias 🍉` : ''}
        />
        <Kpi
          titulo="Estouro previsto"
          carregando={kpis.loading}
          valor={k ? fmt.brlCompacto(k.estouro_previsto) : '—'}
          detalhe="EAC − orçamento dos projetos em andamento"
        />
        <Kpi
          titulo="Carteira em andamento"
          carregando={kpis.loading}
          valor={k ? fmt.brlCompacto(k.carteira) : '—'}
          detalhe="soma do valor dos contratos"
        />
        <Kpi
          titulo="Alto risco em 30 dias"
          carregando={score.carregando}
          valor={score.disponivel ? fmt.inteiro(score.altoRisco) : '—'}
          detalhe={semModelo ? 'modelo de estouro ainda não publicado' : 'P(estouro) ≥ 50% · gold.score_estouro_30d'}
        />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Do pior para o melhor</CardTitle>
          <CardDescription>
            Crítico: SPI ou CPI &lt; 0,8 · atenção: &lt; 0,9. 🍉 = melancia: o gerente diz verde, o número diz atraso.
            Causa: a mais frequente no status semanal dos últimos 90 dias.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {projetos.error && <Erro mensagem={projetos.error} />}
          {projetos.loading && (
            <div className="space-y-2">
              {Array.from({ length: 6 }, (_, i) => (
                <Skeleton key={i} className="h-8 w-full" />
              ))}
            </div>
          )}
          {projetos.data && projetos.data.length === 0 && (
            <Empty>
              <EmptyHeader>
                <EmptyTitle>Nenhum projeto em andamento</EmptyTitle>
                <EmptyDescription>Rode o job vertice_farol para recalcular a gold.</EmptyDescription>
              </EmptyHeader>
            </Empty>
          )}
          {projetos.data && projetos.data.length > 0 && (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Projeto</TableHead>
                    <TableHead>Situação</TableHead>
                    <TableHead className="text-right">SPI</TableHead>
                    <TableHead className="text-right">CPI</TableHead>
                    <TableHead className="text-right">Estouro previsto</TableHead>
                    <TableHead className="text-right">Atraso projetado</TableHead>
                    <TableHead>Farol do gerente × número</TableHead>
                    <TableHead>Causa (90 dias)</TableHead>
                    <TableHead className="text-right">P(estouro)</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {projetos.data.map((p) => {
                    const prob = score.porProjeto.get(p.projeto_id)?.prob_estouro_30d;
                    return (
                      <TableRow key={p.projeto_id}>
                        <TableCell>
                          <div className="font-medium">{p.projeto_id}</div>
                          <div className="text-xs text-muted-foreground">{p.cliente}</div>
                        </TableCell>
                        <TableCell>
                          <BadgeSituacao situacao={p.situacao} />
                        </TableCell>
                        <TableCell className="text-right tabular-nums">{fmt.indice(p.spi)}</TableCell>
                        <TableCell className="text-right tabular-nums">{fmt.indice(p.cpi)}</TableCell>
                        <TableCell className="text-right tabular-nums">{fmt.brl(p.estouro_previsto)}</TableCell>
                        <TableCell className="text-right tabular-nums">{fmt.inteiro(p.atraso_projetado_dias)} dias</TableCell>
                        <TableCell>
                          {String(p.melancia) === 'true' ? '🍉 ' : ''}
                          {p.farol_do_gerente ?? '—'} × {p.farol_calculado}
                        </TableCell>
                        <TableCell>{rotuloCausa(p.causa_principal)}</TableCell>
                        <TableCell className="text-right tabular-nums">
                          {prob === undefined ? '—' : fmt.pct(num(prob))}
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </div>
          )}
          {semModelo && (
            <p className="mt-3 text-xs text-muted-foreground">
              P(estouro) aparece quando o modelo da noite 4 gravar gold.score_estouro_30d. Sem ele, a coluna mostra —.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
