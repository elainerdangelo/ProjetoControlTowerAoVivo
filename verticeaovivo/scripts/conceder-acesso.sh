#!/usr/bin/env bash
# Dá ao app (um service principal: um "usuário robô" que nasce sem acesso a nada) a leitura
# da gold e da silver. CAN_USE no warehouse dá o computador; o dado vem destes GRANTs.
# Sem eles, o build do app falha no typegen com INSUFFICIENT_PERMISSIONS.
#
# Uso: bash scripts/conceder-acesso.sh <perfil> [nome-do-app]
#      (rode depois do `bundle deploy` do app, que cria o service principal)
set -euo pipefail

PERFIL="${1:?uso: bash scripts/conceder-acesso.sh <perfil> [nome-do-app]}"
APP="${2:-minha-torre}"
CATALOGO="lakehouse_vertice"
WAREHOUSE="${DATABRICKS_WAREHOUSE_ID:-287b54bcf4b0ebe0}"

SP=$(databricks apps get "$APP" --profile "$PERFIL" -o json \
  | python -c "import sys, json; print(json.load(sys.stdin)['service_principal_client_id'])")
echo "app ${APP} · service principal ${SP}"

DATABRICKS_WAREHOUSE_ID="$WAREHOUSE" databricks experimental aitools tools query --output json --profile "$PERFIL" \
  "GRANT USE CATALOG ON CATALOG ${CATALOGO} TO \`${SP}\`" \
  "GRANT USE SCHEMA, SELECT ON SCHEMA ${CATALOGO}.gold TO \`${SP}\`" \
  "GRANT USE SCHEMA, SELECT ON SCHEMA ${CATALOGO}.silver TO \`${SP}\`" \
  | python -c "
import sys, json
falhas = 0
for r in json.load(sys.stdin):
    ok = r.get('state') == 'SUCCEEDED'
    falhas += not ok
    print(('ok    ' if ok else 'FALHOU') + '  ' + r['sql'] + ('' if ok else '  -> ' + str(r.get('error'))))
sys.exit(1 if falhas else 0)
"
echo "Pronto. Agora: cd ${APP} && databricks apps deploy --profile ${PERFIL}"
