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

Uma rotina só, **todo dia à meia-noite** (horário de Brasília), atualiza tudo:

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

O cron é `7 3 * * *`: o GitHub usa sempre UTC, e 03:07 UTC = 00:07 em Brasília. O
minuto 07 é de propósito — o GitHub atrasa mais o que é marcado na hora cheia. Mesmo
assim, execuções agendadas costumam atrasar algumas horas: na prática a rotina começa
de madrugada e leva cerca de 2h30.

Os workflows "Sincronizar Clientes Isolado", "Sincronizar Departamentos Isolado" e
"Rotina Rapida - Categorias" continuam disponíveis para rodar manualmente.

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

## Secrets

Em *Settings → Secrets and variables → Actions*:

| Secret | O que é |
|---|---|
| `SUPABASE_URL` | URL do projeto, `https://<ref>.supabase.co` |
| `SUPABASE_KEY` | chave `service_role` (ou `sb_secret_...`), em *Project Settings → API Keys* |
| `OMIE_CREDENCIAIS` | JSON com `app_key`/`app_secret` de cada empresa, indexado por CNPJ (formato em `empresas.py`) |
| `DATABASE_URL` | connection string do **Session pooler** — só para o workflow de provisionamento |

Secrets do GitHub são cifrados e **não podem ser lidos de volta**. Guarde uma cópia
do JSON de `OMIE_CREDENCIAIS` em lugar seguro, fora do repositório.

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
