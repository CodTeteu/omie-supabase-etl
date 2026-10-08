# ETL Omie → Supabase

Extrai os dados financeiros de 24 empresas do grupo pela API do Omie e grava num
banco Supabase, que alimenta os painéis do Power BI. Roda sozinho no GitHub Actions.

```
API Omie ──► GitHub Actions (todo dia, meio-dia) ──► Supabase ──► Power BI
```

Este repositório é **a fonte completa**: com ele dá para recriar o banco inteiro
do zero — estrutura, chaves, views e dados — sem depender de nenhuma máquina ou
pessoa. Veja [Recriar tudo do zero](#recriar-tudo-do-zero).

## Agendamento

Uma rotina só, **toda noite às 22h** (horário de Brasília), atualiza tudo:

| Ordem | Etapa | Tabela |
|---|---|---|
| 1 | Categorias | `categorias_omie` |
| 2 | Departamentos | `departamentos_omie` |
| 3 | Clientes | `clientes_grupo` |
| 4 | Contas a Receber | `contas_receber_grupo` |
| 5 | Conta Corrente | `conta_corrente` |
| 6 | Movimentos Financeiros | `movimentos_financeiros` |
| 7 | Contas a Pagar | `contas_pagar` |

Os cadastros (1 a 3) vêm primeiro porque as views cruzam os títulos com eles.

**Toda tabela é gravada do zero, empresa por empresa** (`substituir_dados_empresa`, em
[`gravacao.py`](gravacao.py)). Para cada empresa, a rotina baixa tudo do Omie, confere se
veio a quantidade que o próprio Omie informa (`total_de_registros`) e só então apaga os
dados daquela empresa e grava de novo. Assim, o que foi excluído no Omie também sai do
banco. As travas:

- extração com falha ou chave suspensa: a empresa não é tocada (os dados da véspera ficam);
- veio menos do que o Omie informa (página que não veio, registro que o zoom progressivo
  não recuperou): nada é apagado, só os registros que vieram são atualizados, com aviso;
- a limpeza falhou: nada é gravado por cima;
- cada chamada ao Supabase é repetida até 3 vezes em erro de rede ou HTTP 5xx.

Até 07/10/2026, contas a pagar, clientes e departamentos só eram atualizados, nunca
apagados: título excluído no Omie ficava no banco para sempre, congelado na última
situação — em contas a pagar, 29 títulos (R$ 1,36 milhão) acumulados em 3 dias.

**Quem dispara às 22h é o Supabase, não o GitHub.** O agendamento do GitHub é
"melhor esforço": ele **atrasa horas** e, sob carga, pode **descartar disparos sem
aviso** — em 05 e 06/10/2026 o disparo das 00:07 só chegou às 07:17 e às 07:05; em
setembro, o das 12:00 chegava entre 14:43 e 18:10. Já um disparo pela API do GitHub
começa em segundos. Por isso o `pg_cron` do Supabase da Audit chama a API às 22:00,
com uma segunda tentativa às 22:30 ([`agendador_supabase.sql`](agendador_supabase.sql)).
O token que ele usa (fine-grained, só este repositório, *Actions: Read and write*) fica
no Vault do Supabase com o nome `github_token_rotina`, nunca no código. A carga leva
cerca de 2h15: **conte com os dados atualizados por volta da meia-noite e meia**.

O agendamento do próprio GitHub fica de **reserva**: 22:07, 02:07 e 06:07 (no arquivo,
em UTC: 01:07, 05:07 e 09:07). Cada disparo começa checando, pela data de gravação no
banco, se a carga **desta noite** (desde as 20:00) já foi feita e se não há outra
execução rodando ([`decidir_execucao.py`](decidir_execucao.py)). Se já foi feita ou está
rodando, encerra em segundos; se o agendador do Supabase falhou, a reserva faz a carga,
atrasada, e deixa um aviso.

Para acompanhar o agendador, no SQL Editor do projeto da Audit:
`select * from agendador.disparos order by id desc limit 20;`

Os workflows "Sincronizar Clientes Isolado", "Sincronizar Departamentos Isolado" e
"Rotina Rapida - Categorias" continuam disponíveis para rodar manualmente.

**A rotina se mantém ativa sozinha.** Em repositório público, o GitHub desativa
rotinas agendadas após 60 dias sem commits — e esta automação roda sem ninguém mexer
no código, então pararia em silêncio. Para evitar isso, quando o último commit passa
de 45 dias, a própria rotina faz um commit vazio de manutenção. Para testar, dispare a
rotina manualmente marcando *"Só testar o commit de manutenção"*.

## Quando algo dá errado, você fica sabendo

Qualquer gravação que falhe deixa a execução **vermelha**, e o GitHub manda email.
A rotina diária também confere, antes de começar, se o banco responde — se não
responder, para em segundos — e, no fim, se as tabelas têm dados. O resumo com as
contagens aparece na página de cada execução.

Isso não existia antes: de 16/09 a 04/10/2026 o projeto Supabase deixou de existir
e as 19 execuções desse período ficaram verdes, sem gravar nada.

Uma empresa que deixa de carregar — chave do Omie suspensa, por exemplo — também
deixa a execução **vermelha**, a não ser que esteja marcada com `suspensa_desde` em
[`empresas.py`](empresas.py). Essas ausências já conhecidas aparecem só como
**aviso** amarelo; quando a chave for reativada no Omie, apague a marcação. Em todos
os casos os dados antigos da empresa são preservados.

A regra existe porque a STUDIO GROWTH ficou fora de 22/09 a 04/10/2026 sem ninguém
perceber: aviso amarelo no GitHub não gera email.

As chamadas ao Omie seguem os [limites oficiais de consumo](https://ajuda.omie.com.br/pt-BR/articles/8112984-limites-de-consumo-da-api-do-omie)
(regras centralizadas em [`omie_api.py`](omie_api.py)): 10 erros seguidos no mesmo
método bloqueiam a chave por 30 minutos, então os scripts **não insistem** em erro
permanente (chave suspensa, bloqueio 425), esperam o tempo que o Omie pede quando ele
manda aguardar, e repetem instabilidades com espera crescente (5, 10, 20, 40 s).

## Secrets

Em *Settings → Secrets and variables → Actions*:

| Secret | O que é |
|---|---|
| `SUPABASE_URL` | URL do projeto, `https://<ref>.supabase.co` |
| `SUPABASE_KEY` | chave `service_role` (ou `sb_secret_...`), em *Project Settings → API Keys* |
| `OMIE_CREDENCIAIS` | JSON com `app_key`/`app_secret` de cada empresa, indexado por CNPJ (formato em `empresas.py`) |
| `DATABASE_URL` | connection string do **Session pooler** — só para o workflow de provisionamento |
| `SUPABASE_URL_ESPELHO` | URL do banco espelho da Audit, `https://<ref>.supabase.co` (opcional, ver abaixo) |
| `SUPABASE_KEY_ESPELHO` | chave `sb_secret_...` (ou `service_role`) do banco espelho (opcional) |
| `APROVACOES_URL` | URL do projeto das aprovações do BI de Repasse, `https://<ref>.supabase.co` (opcional): a conferência final faz uma consulta por noite para o plano gratuito não pausar o projeto |
| `APROVACOES_KEY` | chave pública (`sb_publishable_...`) desse projeto, a mesma que o relatório usa (opcional) |

Secrets do GitHub são cifrados e **não podem ser lidos de volta**. Guarde uma cópia
do JSON de `OMIE_CREDENCIAIS` em lugar seguro, fora do repositório.

## Espelho no banco da Audit

Desde 05/10/2026 a rotina grava os mesmos dados em dois bancos: o principal
(`SUPABASE_URL`) e o espelho da Audit, projeto `omie-supabase-etl` da organização
audit.tec (`SUPABASE_URL_ESPELHO`). O Omie é lido uma vez só.

- `espelho.py`, ligado por `gravacao.py`: cada gravação (POST, PATCH, PUT, DELETE) que um
  script faz na API REST do principal é repetida logo depois no espelho, com a chave do
  espelho. Vale para o `requests` e para o cliente `supabase-py` (httpx). Leituras não são
  repetidas. Falha no espelho deixa a execução vermelha, mas não muda o que é gravado no
  principal; depois de 5 falhas seguidas o espelho para naquela etapa.
- `checar_saude.py`: no início avisa se o espelho não responde (a carga do principal roda
  mesmo assim); no fim compara a contagem de cada tabela nos dois bancos.
- `sincronizar_espelho.py` (workflow **Sincronizar Espelho**, manual): copia o principal
  inteiro para o espelho, tabela por tabela. Use na primeira carga e quando a checagem do fim
  apontar diferença.
- Sem os dois secrets do espelho, nada disso roda: a rotina volta a ser só o principal.

O banco espelho foi criado com o mesmo `provisionar_banco_completo.sql` (estrutura idêntica:
tabelas, chaves, índices, views e RLS).

## Recriar tudo do zero

Se o projeto Supabase for perdido, pausado sem volta ou precisar mudar de conta:

1. **Crie um projeto** no Supabase (região *South America – São Paulo*).
2. **Atualize os secrets** `SUPABASE_URL`, `SUPABASE_KEY` e `DATABASE_URL` com os
   dados do projeto novo. Em `DATABASE_URL`, use a string do *Session pooler*
   (botão *Connect*): a conexão direta usa só IPv6, que o GitHub Actions não suporta.
3. **Rode o workflow "Provisionar Banco (schema completo)"**. Ele cria as 8 tabelas,
   as 8 chaves, as 8 views e as regras de seguranca, e confere os 41 itens.
4. **Rode a Rotina Noturna Omie ETL** manualmente. Ela já inclui os cadastros;
   a carga completa leva cerca de 2h30.
5. Confira o resumo de contagens na página da última execução.

Pelo terminal, os mesmos passos:

```bash
gh secret set DATABASE_URL --repo CodTeteu/omie-supabase-etl
gh workflow run "Provisionar Banco (schema completo)" --repo CodTeteu/omie-supabase-etl
gh workflow run "Rotina Noturna Omie ETL" --repo CodTeteu/omie-supabase-etl
```

## Estrutura do banco

Definida em [`provisionar_banco_completo.sql`](provisionar_banco_completo.sql) —
idempotente, pode rodar mais de uma vez. Cada view traz um comentário com sua origem.

**Segurança:** RLS ligado em todas as tabelas, sem políticas, e views com
`security_invoker`. As chaves públicas (`anon`, `publishable`) não acessam nada;
a automação (`service_role`) e o Power BI (usuário `postgres`) não são afetados.

- **Tabelas:** `contas_receber_grupo`, `conta_corrente`, `movimentos_financeiros`,
  `contas_pagar`, `clientes_grupo`, `categorias_omie`, `departamentos_omie`, `extrato_bancario`
- **Views:** `metas`, `metas_bruto`, `painel_contas_pagar`, `view_contas_pagar`,
  `view_contas_receber`, `view_faturamento_rateado`, `view_inadimplencia`,
  `vw_contas_receber_detalhada`

As views `view_extrato`, `view_movimentos_gerencial`, `painel_faturamento`,
`painel_contas_pagar_rateado` e `contas_pagar_new` existiam no banco antigo, mas sua
definição nunca foi versionada e se perdeu com ele. Nenhum painel Power BI as usa.

## Rodar localmente

```bash
pip install -r requirements.txt
export SUPABASE_URL=... SUPABASE_KEY=...
export OMIE_CREDENCIAIS="$(cat caminho/para/credenciais.json)"
python contas_receber_etl.py
python -m unittest discover -s tests -v     # testes, sem banco nem rede
```

## Pendências conhecidas

- **STUDIO FACTORING** (desde jul/2026) e **STUDIO GROWTH** (desde 22/09/2026) estão
  com a chave suspensa no Omie (HTTP 403). Estão marcadas como suspensas conhecidas
  em `empresas.py`, então geram só aviso. Ficam sem dados no banco até as chaves
  serem reativadas no painel do Omie.
- **`extrato_etl.py`** existe, mas nenhum workflow o executa — por isso
  `extrato_bancario` fica vazia.
- **`bandeira_id`** em `contas_pagar` é sempre `0`: a API do Omie não devolve esse
  campo. Não causa colisão, porque os códigos de título do Omie são únicos em toda a
  plataforma.
- **Plano Free do Supabase** tem limite de 500 MB; depois da carga completa de
  04/10/2026 a base ocupava 257 MB (51%), quase metade disso em `contas_pagar`. O
  provisionamento mostra o espaço usado e avisa acima de 80%.
