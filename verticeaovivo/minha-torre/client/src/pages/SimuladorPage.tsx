import {
  useAnalyticsQuery,
  Alert,
  AlertDescription,
  AlertTitle,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
  Input,
  Label,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Skeleton,
} from '@databricks/appkit-ui/react';
import { useMemo, useState } from 'react';
import { fmt, num, rotuloCausa } from '../lib/dados';

const SEMANAS_NO_MES = 4;
const DIAS_JANELA = 90;
const DIAS_NO_MES = 30;

function Linha({ rotulo, valor, destaque }: { rotulo: string; valor: string; destaque?: 'bom' | 'ruim' }) {
  const cor = destaque === 'bom' ? 'text-success' : destaque === 'ruim' ? 'text-destructive' : 'text-foreground';
  return (
    <div className="flex items-baseline justify-between gap-4 py-2 border-b last:border-b-0">
      <span className="text-sm text-muted-foreground">{rotulo}</span>
      <span className={`text-lg font-semibold tabular-nums ${cor}`}>{valor}</span>
    </div>
  );
}

export function SimuladorPage() {
  const pessoas = useAnalyticsQuery('pessoas_ociosas', {});
  const projetos = useAnalyticsQuery('projetos_risco', {});

  const [pessoaId, setPessoaId] = useState<string>('');
  const [projetoId, setProjetoId] = useState<string>('');
  const [onboardingHoras, setOnboardingHoras] = useState<number>(40);

  const listaPessoas = useMemo(
    () => (pessoas.data ?? []).map((p) => ({ ...p, chave: `${p.colaborador_id}|${p.projeto_origem}` })),
    [pessoas.data],
  );
  const pessoa = listaPessoas.find((p) => p.chave === pessoaId) ?? listaPessoas[0];
  const ehSre = pessoa?.papel === 'sre';
  const causaRelevante = ehSre ? 'falta_sre' : 'rotatividade';

  // Destino: só projetos em atenção ou crítico. Para SRE, quem mais declarou falta de SRE vem primeiro.
  const destinos = useMemo(() => {
    const emRisco = (projetos.data ?? []).filter((p) => p.situacao === 'crítico' || p.situacao === 'atenção');
    return ehSre ? [...emRisco].sort((a, b) => num(b.dias_falta_sre) - num(a.dias_falta_sre)) : emRisco;
  }, [projetos.data, ehSre]);
  const destino = destinos.find((p) => p.projeto_id === projetoId) ?? destinos[0];

  const carregando = pessoas.loading || projetos.loading;
  const erro = pessoas.error ?? projetos.error;

  // ─── A conta (tudo em número: o warehouse devolve string) ───────────────────────
  const custoHora = num(pessoa?.custo_hora);
  const horasMes = num(pessoa?.horas_paradas_semana) * SEMANAS_NO_MES;
  const ociosidadeEvitada = horasMes * custoHora;
  const diasCausa = destino ? num(ehSre ? destino.dias_falta_sre : destino.dias_rotatividade) : 0;
  const diasRecuperados = (diasCausa / DIAS_JANELA) * DIAS_NO_MES;
  const mobilizacao = num(onboardingHoras) * custoHora;
  const saldo = ociosidadeEvitada - mobilizacao;

  return (
    <div className="space-y-6 w-full max-w-5xl mx-auto">
      <div>
        <h2 className="text-2xl font-semibold text-foreground">Simulador de realocação</h2>
        <p className="text-sm text-muted-foreground">
          Tenho gente parada enquanto outro projeto pede gente? Escolha uma pessoa com uso abaixo de 20% nas últimas 12
          semanas e um projeto em risco, e veja quanto custa e quanto devolve mover essa pessoa por um mês.
        </p>
      </div>

      {erro && (
        <Alert variant="destructive">
          <AlertTitle>Não foi possível ler a gold</AlertTitle>
          <AlertDescription>{erro}</AlertDescription>
        </Alert>
      )}

      {carregando && <Skeleton className="h-64 w-full" />}

      {!carregando && !erro && listaPessoas.length === 0 && (
        <Empty>
          <EmptyHeader>
            <EmptyTitle>Ninguém parado</EmptyTitle>
            <EmptyDescription>Nenhuma pessoa com utilização abaixo de 20% nas últimas 12 semanas.</EmptyDescription>
          </EmptyHeader>
        </Empty>
      )}

      {!carregando && pessoa && destino && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <Card>
            <CardHeader>
              <CardTitle>Quem e para onde</CardTitle>
              <CardDescription>Projeto destino: só atenção ou crítico.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-5">
              <div className="space-y-2">
                <Label htmlFor="pessoa">Pessoa ociosa</Label>
                <Select value={pessoa.chave} onValueChange={(v) => { setPessoaId(v); setProjetoId(''); }}>
                  <SelectTrigger id="pessoa">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {listaPessoas.map((p) => (
                      <SelectItem key={p.chave} value={p.chave}>
                        {p.colaborador_id} · {p.nome} ({p.papel} {p.senioridade}, {p.projeto_origem}, uso de{' '}
                        {fmt.pct(p.utilizacao)})
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label htmlFor="destino">Projeto destino</Label>
                <Select value={destino.projeto_id} onValueChange={setProjetoId}>
                  <SelectTrigger id="destino">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {destinos.map((p) => (
                      <SelectItem key={p.projeto_id} value={p.projeto_id}>
                        {p.projeto_id} · {p.situacao} · {rotuloCausa(p.causa_principal)}
                        {ehSre ? ` · ${fmt.inteiro(p.dias_falta_sre)} dias de falta de SRE` : ''}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <p className="text-xs text-muted-foreground">
                  {destino.nome_projeto} · SPI {fmt.indice(destino.spi)} · CPI {fmt.indice(destino.cpi)}
                </p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="onboarding">Horas de onboarding</Label>
                <Input
                  id="onboarding"
                  type="number"
                  min={0}
                  value={onboardingHoras}
                  onChange={(e) => setOnboardingHoras(Math.max(0, num(e.target.value)))}
                />
                <p className="text-xs text-muted-foreground">Uma semana para a pessoa entrar no projeto (padrão 40 h).</p>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>O mês da realocação</CardTitle>
              <CardDescription>
                {pessoa.colaborador_id} ({pessoa.projeto_origem}) → {destino.projeto_id}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Linha rotulo="Horas no mês" valor={`${fmt.inteiro(horasMes)} h`} />
              <Linha rotulo="Ociosidade que deixa de ser paga" valor={fmt.brl(ociosidadeEvitada)} destaque="bom" />
              <Linha rotulo="Mobilização (onboarding)" valor={`− ${fmt.brl(mobilizacao)}`} destaque="ruim" />
              <Linha
                rotulo="Saldo no mês"
                valor={fmt.brl(saldo)}
                destaque={saldo >= 0 ? 'bom' : 'ruim'}
              />
              <Linha
                rotulo={`Dias de cronograma recuperados (${rotuloCausa(causaRelevante)})`}
                valor={`${fmt.decimal1(diasRecuperados)} dias`}
              />

              <details className="mt-4 text-sm text-muted-foreground">
                <summary className="cursor-pointer text-foreground">De onde vem cada número</summary>
                <ul className="mt-2 space-y-2 list-disc pl-5">
                  <li>
                    <strong>Horas no mês</strong> = horas paradas médias por semana nas últimas 12 semanas (
                    {fmt.decimal1(pessoa.horas_paradas_semana)} h) × {SEMANAS_NO_MES} semanas.
                  </li>
                  <li>
                    <strong>Ociosidade evitada</strong> = horas no mês × custo/hora ({fmt.brl(custoHora)}). Essas horas já
                    são pagas hoje sem trabalho; no projeto destino viram entrega.
                  </li>
                  <li>
                    <strong>Mobilização</strong> = horas de onboarding ({fmt.inteiro(onboardingHoras)} h) × custo/hora.
                  </li>
                  <li>
                    <strong>Saldo</strong> = ociosidade evitada − mobilização.
                  </li>
                  <li>
                    <strong>Dias recuperados</strong> = dias de impacto declarados no status semanal de{' '}
                    {destino.projeto_id} por {rotuloCausa(causaRelevante)} nos últimos {DIAS_JANELA} dias (
                    {fmt.inteiro(diasCausa)}) ÷ {DIAS_JANELA} × {DIAS_NO_MES}. Fica fora da conta em R$: transformar dia
                    de cronograma em dinheiro exige uma premissa (multa, receita adiada) que o dado não tem.
                  </li>
                </ul>
              </details>
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}
