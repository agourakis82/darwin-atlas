# ADR-0002: Pilot parameter decisions (proposed)

- **Status:** proposed
- **Date:** 2026-07-31
- **Decision owners:** Darwin Atlas project
- **Specification:** `docs/SCIENTIFIC_SPEC.md` 0.1.0

## Context

Fases A–C da terceira rodada tornaram o pipeline de janelas Sounio
parametrizado: os parâmetros são um artefato JSON canônico, versionado e
hasheado (`schemas/pipeline_parameters.schema.json`), renderizado pelo runner
num formato flat estrito e revalidado pelo executável (rejeição com
`PARAM_INVALID`, exit 11). Os fixtures executáveis correm com
`window_size=stride=4, k_max=4` (regressão 0.1.0→0.2.0) e
`window_size=stride=16, k_max=8` (faixa piloto k=1..8). Nenhum dos valores
abaixo altera definições normativas da especificação; eles fixam, antes da
aquisição do coorte (Fases D–J), as escolhas que hoje estão abertas. Este ADR
está **proposed**: vira *accepted* quando o manifesto definitivo do coorte for
anexado na Fase D.

## Decision (proposta)

1. **Janela e stride do piloto:** `window_size = stride = 16` (não sobrepostas,
   coordenadas zero-based half-open, sem wraparound), conforme já exercitado
   pelo fixture 16/16. Janelas parciais terminais são emitidas e excluídas com
   `PARTIAL_WINDOW`.
2. **Faixa k-mer:** `k_min = 1`, `k_max = 8`, com campos para `k > k_max`
   reportados como `K_OUT_OF_CONFIGURED_RANGE` (nunca computados, nunca
   zero-filled).
3. **Contagem efetiva mínima por k:** o piloto usa
   `min_kmer_effective_count >= 8` por janela (uma órbita não-trivial exige ao
   menos um k-mer observado e a fração mascarada deve permanecer minoritária);
   o valor exato é fixado no manifesto do coorte. Os fixtures executáveis
   permanecem em `1` (parâmetro de fixture, não threshold científico).
4. **Replicates do null model:** número de réplicas nulas por janela proposto
   em `n = 1000`; o valor definitivo é fixado antes da Fase F e registrado no
   recibo de execução.
5. **Null primário:** permutação de dinucleotídeos preservando composição de
   dinucleotídeos da janela (primary), com null de embaralhamento mononucleotídeo
   como sensibilidade. Implementação somente após os fixtures diferenciais de
   null passarem (Fase F).
6. **Derivação de seed:** `seed = SHA-256(parameters_sha256 || ":" ||
   accession_version || ":" || window_start)` reduzida a 64 bits, tornando cada
   réplica nula determinística, independente de ordem de execução e
   reproduzível pelo validador Julia a partir dos artefatos persistidos.
7. **Famílias de hipóteses:** duas famílias pré-declaradas para controle de
   multiplicidade: (a) `delta_R`/`delta_RC` posicionais; (b) imbalances k-mer
   `k=1..8` (reverse e RC). Correção por família (Benjamini–Hochberg), não
   global.
8. **Manifesto do coorte:** a lista definitiva de replicons (acessions,
   classes, topologias declaradas, escopo) é congelada na Fase D com
   checksums de pacote NCBI Datasets registrados; nenhum replicon entra ou sai
   depois do congelamento sem novo ADR.

## Consequences

- O schema de parâmetros (`pipeline_parameters.schema.json`) admite os valores
  acima sem alteração estrutural; o artefato canônico do piloto será um novo
  `parameters_pilot.json` referenciado pelo manifesto do coorte.
- `window_operator_profile.schema.json` 0.2.0 já cobre a faixa k=1..8 e os
  reason codes; campos de null model exigirão uma revisão 0.3.0 (adição de
  campos, sem reinterpretar os existentes).
- A derivação de seed proposta torna os nulls auditáveis byte a byte pelo
  validador independente.
- Enquanto este ADR estiver *proposed*, nenhum artefato com estes parâmetros é
  evidência de release; os fixtures executáveis continuam sendo a fronteira de
  evidência.

## Alternatives rejected

- **Janelas sobrepostas (stride < window_size):** infla contagens efetivas por
  janela, mas acopla janelas vizinhas e complica o modelo nulo e a correção de
  multiplicidade; a especificação já fixa janelas não sobrepostas.
- **Seed global única por execução:** quebra a independência de ordem e impede
  recomputação por janela pelo validador.
- **Null mononucleotídeo como primário:** não preserva estrutura de
  dinucleotídeos, que é o primeiro confundidor composicional esperado em
  escala genômica.
