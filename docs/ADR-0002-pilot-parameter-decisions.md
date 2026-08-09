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
- `window_operator_profile.schema.json` 0.3.0 já cobre a faixa k=1..8, os
  reason codes e o bloco aditivo de null model. Os fixtures mononucleotídeo e
  dinucleotídeo exercitam esse contrato sem decidir qual será o null primário
  do piloto nem reinterpretar os campos 0.2.0.
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

## Evidence annex (Fase N–O1, 2026-08-06; Fase P1, 2026-08-07)

Este anexo registra evidência de engenharia; o ADR permanece **proposed** e
nenhum item acima vira decisão por este anexo.

### N1. Gate de qualidade dos geradores (uniformidade estatística)

Suíte nova (`sounio/src/null_quality_fixture.sio`, réplica exata dos dois
motores; `julia/scripts/validate_null_quality.jl`, validador independente
stdlib-only; `data/fixtures/null_quality/`). Para cada caso o validador
re-enumera o suporte nulo exato (permutações distintas do multiset; trilhas
de Euler com arestas paralelas distintas — ambos uniformes por construção,
com multiplicidade constante `prod n_c!` / `prod m_vw!`), exige contenção e
cobertura total, e aplica qui-quadrado com α = 1e-3 pré-declarado (p-valores
via gama incompleta regularizada Base-only com self-tests de forma fechada).
Execução dupla byte-idêntica (determinismo ✓) no Sounio pinado `37de2c9`.

| caso | motor | draws | suporte | χ² (df) | p | veredito |
|---|---|---|---|---|---|---|
| `dinuc_parallel` (ACAGTGCATC) | dinuc | 72.000 | 18/18 | 18,27 (17) | 0,372 | PASS |
| `dinuc_distinct` (AGCATCGTAC) | dinuc | 72.000 | 36/36 | 37,35 (35) | 0,362 | PASS |
| `mono_blocks` (AAAACCCC) | mono | 140.000 | **55/70** | 111.045 (69) | ≈0 | **FAIL** |

O motor mono (`lcg31_sha8_fixture_v1`) falha de forma estrutural: a família de
seeds aritmética (`+1009·r`) composta com o LCG glibc e o Fisher-Yates com
`state mod (i+1)` alcança apenas **2.520 de 40.320 permutações de posição
(6,25%)** — defeito de reticulado (Marsaglia). Verificado com réplica Python
byte-exata contra o artefato Sounio; o suporte alcançável é 55/70 para
**qualquer** seed_base/window_start/record_index/metric_index (6
configurações testadas), com razões de frequência de 0,17× a 5,33×, e o
defeito persiste na geometria piloto 16 bp (9.711/12.870 sequências
alcançáveis em 200.000 réplicas consecutivas).

**Consequência para o item 5:** o null primário dinucleotídeo (ADR-0003) é
estatisticamente validado nos dois casos do gate; o null mononucleotídeo,
como engenhado, **não pode servir de sensibilidade** — ou é re-engenhado
(derivação de seed por réplica via SHA-256, como o dinuc, ou gerador mais
forte; novo engine versionado com re-gate completo) ou o papel de
sensibilidade é removido deste ADR. Nenhum artefato anterior é invalidado:
os gates anteriores provavam byte-exatidão/determinismo/invariantes, não
uniformidade, e nenhum carrega afirmação científica.

### N2. Runtime dos motores e projeção para o item 4

Sonda (`scripts/run_null_runtime_probe.sh`) sobre o replicon de smoke
NC_002127.1 (207 janelas, 16/16, 18 métricas), Sounio pinado, ELF canônico
`f0595e60...`, VM Lima x86_64 single-thread, mesma sessão:

| motor | r=8 | r=16 | r=32 | r=64 | ajuste linear |
|---|---|---|---|---|---|
| mono | 56,2 s | 101,5 s | 198,7 s | 387,9 s | 7,9 s + 5,94 s/réplica (R²=0,99995) |
| dinuc | 63,2 s | 126,3 s | 231,7 s | 430,2 s | 18,3 s + 6,48 s/réplica (R²=0,99856) |

Custos unitários: ~1,6 ms (mono) e ~1,7 ms (dinuc) por janela/métrica/
réplica. Projeção para o cromossomo NC_000913.3 (290.104 janelas × 18
métricas): n=64 → ~6–7 dias; **n=1000 → ~97 dias (mono) e ~106 dias (dinuc,
subestimado)**. O dinuc ainda agrava em n grande: o seeding por réplica é
O(r) — Σ(r−1) ≈ n²/2 jumps por janela/métrica (~500k em n=1000; ~7 dias
adicionais na taxa medida de ~4,4M jumps/s) — e o mesmo shuffle é
recomputado 18× (uma por métrica). **Consequência para o item 4:** n=1000 em
escala cromossômica é inviável no engine CPU atual; antes da Fase F é
preciso jump-ahead O(log r) via exponenciação modular, compartilhamento do
shuffle entre métricas, e/ou o caminho U250. O teto `null_replicates=64` do
schema também precisará de revisão para n=1000.

### O1. Correção do crash de arena na resolução de seeds dinuc

A sonda revelou que a integração dinuc do pipeline morria deterministicamente
com rc=181 após 20.448 shuffles (janela 142/207, r=8): `resolve_dinucleotide_seed`
alocava ~2 strings por linha varrida por janela (varredura linear por janela
→ vazamento quadrático na arena de strings, que o backend nativo não reclama
em loops). Fixtures anteriores nunca excederam 12.096 shuffles por processo,
então o defeito era latente. A correção reescreve a resolução com aritmética
de índices pura (zero alocação, mesma semântica first-match). Fonte nova
`06b8890e...`, ELF `f0595e60...`. Re-bateria completa **byte-idêntica**:
mini-pipeline 6/6 artefatos (`e5564ea3`, `f87bd3f6`, `4997efed`, `d53de8b3`,
`839fa985`, `086f585b`) com tripla de kernels equivalente, null-metamórfico
(`c37d56ad`, `33135ce3`), cohort smoke (207 janelas, Julia byte-exato), e a
sonda 8/8 configs completa 207/207 linhas (dinuc r=64 incluído).

### P1. Throughput medido do kernel U250 (sonda, hardware real)

Sonda `fpga/u250-dinucleotide-null/src/host_throughput.cpp` executada em
2026-08-07 no node `dl380-proxmox` (BDF `0000:d8:00.1`, shell
`xdma_4_1`, XRT 2.23.0), reusando o xclbin da Fase L byte-idêntico
(`b123ea0c...`; a interface aceita `case_count`/`replicates` em runtime, sem
rebuild Vitis). Âncora de corretude no fixture congelado 8×8 com tolerância 0
(bit-exata) e varredura de integridade 131.072/131.072 slots (sentinela, faixa,
endpoints). Receipt completo em
`receipts/u250-throughput-probe-20260807T223500Z/`.

Sweep em 1.024 janelas sintéticas (4 famílias de grafos) por instância:

| replicates | draws | wall | draws/s |
|---|---|---|---|
| 8 | 8.192 | 75 ms | **108.038** |
| 64 | 65.536 | 1.019 ms | 64.287 |
| 256 | 262.144 | 9.780 ms | 26.802 |
| 1.024 | 1.048.576 | 130.390 ms | 8.041 |

Leituras para os itens 4 e 6:

1. **O envelope pré-hardware (~0,5–2M draws/s/instância) superestimou 1–2
   ordens de grandeza.** No regime do piloto (n≈1000 réplicas por janela), a
   instância única entrega ~8k draws/s; o melhor ponto medido (batches curtos,
   R=8) é ~108k draws/s.
2. **O custo por draw é superlinear em R** (~13,6× além do linear entre R=8 e
   R=1024): o kernel repete trabalho por réplica (re-stream da janela e
   derivação sequencial de seeds por réplica, sem jump-ahead). Batching
   host-side com R pequeno mitiga parcialmente, a custo de overhead por
   launch.
3. **P2 (redesign do kernel) vira pré-requisito, não opção:** shuffle
   compartilhado entre as 18 métricas, jump-ahead por tabela ROM
   host-precomputada, sumários in-kernel (devolver estatísticas, não draws
   brutos) e N instâncias. Mesmo escalando a estratégia R=8 (108k draws/s),
   o piloto dinuc n=1000 cromossômico (~290M draws × 18 métricas se nada
   mudar) ficaria na casa de dias; com sumário in-kernel e shuffle
   compartilhado, o alvo de minutos/horas volta a ser plausível.
4. Nota de execução: a sonda rodou via container `ctr` direto no host porque o
   caminho kubelet→systemd do node estava temporariamente degradado; o
   contrato do device plugin (`sounio.dev/u250`) e o pod manifest seguem o
   caminho nominal para corridas futuras.

### P2 (implementação em andamento). Kernel `dinucleotide_summaries` + núcleo compartilhado

O redesign seguiu a arquitetura do item 3 acima, com um núcleo de semântica
único `fpga/u250-dinucleotide-null/src/null_core.hpp` (C++17 puro, sem
alocação dinâmica, sem ponto flutuante) compilado por três backends: Vitis
HLS (kernel U250), HIP (benchmark R9700) e g++ host (csim/âncoras).

1. **Jump-ahead ROM.** `kJumpRom{1,2}[i] = kJump{1,2}^(2^i) mod m{1,2}`
   (i=0..10), derivada por tabela de potências e provada equivalente à derivação
   sequencial para toda réplica 1..1024; a derivação por réplica cai de O(R)
   para O(log R). Âncora csim: os 1.024 slots do fixture Fase L (8×8) saem
   bit-idênticos (`P2_CSIM_ANCHOR ... mismatches=0`).
2. **Shuffle compartilhado.** Um único draw alimenta as 18 métricas no kernel
   (0–1 posicionais; 2k/2k+1 = reverse/rc k-mer imbalance, k=1..8), espelhando
   `window_pipeline_core.jl` — incluindo a política de indisponibilidade
   (`min_effective`, denominador de órbita vazio, draw rejeitado fail-closed).
3. **Sumários in-kernel.** Cinco campos inteiros exatos por (caso, métrica) —
   count, mean piso, MAD exato da média racional, q025/q975 nearest-rank —
   com ordenação bitônica on-chip; saída 18×5 int32 por caso (180× menor que
   os draws brutos em R=1024). Âncora csim contra referência Python
   independente (`scripts/null_summaries_reference.py`, reimplementação da
   semântica Julia): 144/144 campos em `min_effective=1` e `=4`
   (`P2_CSIM_DIFF checked=144 mismatches=0`).
4. **N instâncias:** adiado para após a validação do xclbin v2 (medir primeiro
   o teto de 1 CU com o novo formato de saída).

### B3. Benchmark comparativo Radeon AI PRO R9700 (gfx1201, ROCm 7.2.4)

O mesmo `null_core.hpp` compilado via HIP e executado no pod
`beagle/rocm-r9700-compute` (dl380-proxmox, BDF `0000:88:00.0`, PCIe 32 GT/s
x16, 34,2 GB VRAM). Âncoras no hardware: draws 1.024/1.024 bit-exatos e
720/720 campos de sumário idênticos à recomputação host. Sweep nas mesmas
1.024 janelas sintéticas da sonda P1 — **pipeline completo por draw** (draw +
18 métricas + sumários), contra draws crus no U250:

| replicates | U250 P1 (draws/s, só draws) | R9700 (draws/s, pipeline completo) |
|---|---|---|
| 8 | 108.038 | 198.351 |
| 64 | 64.287 | 1.762.387 |
| 256 | 26.802 | 7.352.308 |
| 1.024 | 8.041 | **28.003.204** |

Em R=1024 a R9700 entrega ~3.483× a vazão do U250 Fase L executando ~20× mais
trabalho por draw; kernel1 isolado atinge ~166M draws/s. O gargalo medido é o
kernel2 (sumários bitônicos single-thread por bloco, ~31–41 ms constantes no
sweep) — headroom documentado no receipt
`receipts/r9700-dinucleotide-benchmark-20260808T184342Z/`, não limite de
semântica. Leitura para o piloto n=1000: ~290M draws com pipeline completo na
faixa de dezenas de segundos por cromossomo nesta escala de janela (medida de
engenharia no fixture L=16; janelas reais maiores movem a constante, não a
ordem).

### P2 hardware. Sonda U250 do kernel `dinucleotide_summaries`

xclbin v2 compilado com Vitis 2025.1 na VM `vitis-u250-builder` (alvo
`xilinx_u250_gen3x16_xdma_4_1_202210_1`, link em 1h 47m 29s) e executado no
U250 do dl380-proxmox (BDF `0000:d8:00.1`, shell
`xilinx_u250_gen3x16_xdma_shell_4_1`, XRT 2.23.0). Âncora no hardware:
720/720 campos de sumário do fixture 8×8 idênticos à referência com
tolerância 0; integridade 18.432/18.432 blocos. Sweep nas mesmas 1.024
janelas sintéticas da sonda P1, agora com **pipeline completo por draw**
(draw + 18 métricas + sumários in-kernel):

| replicates | U250 P1 (draws/s, só draws) | U250 P2 (draws/s, pipeline completo) | R9700 (draws/s, pipeline completo) |
|---|---|---|---|
| 8 | 108.038 | 576 | 198.351 |
| 64 | 64.287 | 4.033 | 1.762.387 |
| 256 | 26.802 | 11.278 | 7.352.308 |
| 1.024 | 8.041 | **20.447** | **28.003.204** |

P2 em cases/s e wall: 72 cases/s (14,2 s), 63 (16,2 s), 44 (23,2 s) e 19
(51,3 s) para R=8/64/256/1.024. Leituras:

1. **O custo superlinear em R inverteu-se.** Na Fase L a vazão caía com R
   (re-stream da janela e derivação O(R) de seeds por réplica); com
   jump-ahead ROM e shuffle compartilhado, draws/s *cresce* com R
   (576 → 20.447) conforme o overhead por launch amortiza — o melhor ponto
   passa a ser R=1.024, não R=8.
2. **2,5× a Fase L em R=1.024 executando ~20× mais trabalho por draw.**
   20.447 draws/s com pipeline completo contra 8.041 draws/s só de draws;
   em vazão de casos (19 cases/s em R=1.024), o piloto n=1000 (~290M draws
   × 18 métricas) sai da casa de dias para ~4 h por cromossomo nesta escala
   de janela — a meta do redesign (minutos/horas) é atingida no hardware.
3. **A R9700 segue ~1.370× à frente em R=1.024** (28,0M vs 20,4k draws/s no
   mesmo pipeline completo; ~344× em R=8) — o U250 fecha a correção semântica
   e a viabilidade, a GPU detém a vazão bruta nesta escala.

Evidência completa em `receipts/u250-summaries-probe-20260808T204714Z/`
(receipt.json, stdout da sonda, SHA256SUMS e logs do build Vitis).

### P3. Teto `null_replicates` 64 → 1000 (schema, Sounio, Julia, contrato)

O teto `null_replicates=64` apontado na seção N2 como pendente de revisão
foi elevado a **1000** em quatro pontos coordenados, sem nenhuma mudança de
semântica em r≤64:

1. `schemas/pipeline_parameters.schema.json` — `null_replicates.maximum`
   64 → 1000;
2. `sounio/src/fasta_stream_fixture.sio` — `NULL_MAX_REPLICATES: i64 = 1000`
   e buffer `NULL_VALS` `[i64; 1152]` → `[i64; 18000]` (18 métricas × 1000);
3. `julia/scripts/window_pipeline_core.jl` — `NULL_MAX_REPLICATES = 1000` no
   validador independente (a constante Julia também pinnava o teto — detectado
   no dry run do validador n=1000);
4. `Makefile` (contrato) — guarda de drift do máximo do schema atualizada
   para 1000 e duas guardas novas pinnando as constantes Julia e Sounio.

Evidência (receipt `receipts/null-replicates-n1000-20260809T013016Z/`):

- **Re-bateria byte-idêntica**: o binário re-compilado (fonte `d89a7066`,
  ELF `b3b1ac08`, Madaros souc v0.80.0) reproduz os 6/6 hashes congelados da
  bateria mini-pipeline (`e5564ea3`, `f87bd3f6`, `4997efed`, `d53de8b3`,
  `839fa985`, `086f585b`), opt==reference em todos os casos — prova de que a
  mudança é só de teto/buffer, não de semântica.
- **Corrida end-to-end n=1000**: caso null_k4 (12 janelas,
  `mononucleotide_shuffle`) com `null_replicates=1000`; opt1==opt2==reference
  byte-exato, artefato `b6f0d561` (83.775 bytes), wall otimizado 11min39s.
- **Validação Julia independente**: `julia/scripts/validate_null_n1000.jl`
  (Base-only, novo — o validador congelado não foi tocado) re-computa as 12
  janelas × 18 métricas × 1000 réplicas e exige igualdade byte a byte:
  `DOSA_JULIA_NULL_N1000_DIFFERENTIAL_OK`, tolerância 0 (~2 s).
- `make contract` verde após todas as edições, incluindo as duas guardas
  novas de teto.

Com P2+B3, o custo de n=1000 deixou de ser o limitante (R9700 executa o
pipeline completo a 28,0M draws/s); o que permanece em aberto para o null
mono é a decisão de provenance (seed LCG de engenharia vs derivação SHA-256
por réplica do dinuc) — item C vs D a registrar neste ADR após decisão.
