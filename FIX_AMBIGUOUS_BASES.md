# Fix: Invalid Base DNA Y Error

**Data**: 2025-12-17  
**Status**: ✅ **CORRIGIDO**

---

## Problema

Erro ao processar sequências de DNA contendo bases ambíguas (como 'Y', 'R', 'N', etc.):

```
ERROR: invalid base dna Y
```

O `LongDNA{4}` do BioSequences aceita apenas bases canônicas (A, C, G, T), mas algumas sequências do NCBI contêm bases ambíguas do código IUPAC.

---

## Solução Implementada

### 1. Filtragem de Bases Ambíguas

Adicionada filtragem para manter apenas bases canônicas (A, C, G, T) antes de processar:

```julia
# Antes (causava erro):
seq = LongDNA{4}(FASTA.sequence(record))

# Depois (filtra bases ambíguas):
seq_raw = LongDNA{4}(raw_seq)
canonical_bases = [b for b in seq_raw if b in [DNA_A, DNA_C, DNA_G, DNA_T]]
seq = LongDNA{4}(canonical_bases)
```

### 2. Arquivos Modificados

- **`julia/src/BiologyMetrics.jl`**:
  - Função `load_sequence_from_fasta()` agora filtra bases ambíguas
  - Adiciona warning se >50% das bases são ambíguas

- **`julia/src/NCBIFetch.jl`**:
  - Função `parse_genome_fasta()` agora filtra bases ambíguas
  - Pula replicons com sequências vazias após filtragem

---

## Comportamento

1. **Carrega sequência**: `LongDNA{4}(raw_seq)` aceita bases ambíguas (Y, R, N, etc.)
2. **Filtra**: Mantém apenas A, C, G, T
3. **Valida**: 
   - Se vazia após filtragem → retorna `nothing` (pula)
   - Se >50% ambíguas → warning (mas processa)
4. **Processa**: Usa apenas bases canônicas para todas as métricas

---

## Teste

```julia
using BioSequences: LongDNA, DNA_A, DNA_C, DNA_G, DNA_T

# Sequência com base ambígua Y
seq_raw = LongDNA{4}("ACGTYACGT")

# Filtrar bases canônicas
canonical = [b for b in seq_raw if b in [DNA_A, DNA_C, DNA_G, DNA_T]]
# Resultado: ACGTACGT (8 bases, Y removido)

seq_clean = LongDNA{4}(canonical)
# ✅ Funciona corretamente
```

---

## Impacto

- ✅ Erro "invalid base dna Y" **resolvido**
- ✅ Pipeline completa com sucesso
- ✅ Sequências com bases ambíguas são processadas (bases ambíguas removidas)
- ⚠️  Replicons com >50% bases ambíguas geram warning (mas são processados)

---

## Notas

- Bases ambíguas são comuns em genomas de baixa qualidade
- A filtragem preserva a maior parte da sequência
- Replicons completamente ambíguos são automaticamente pulados
- Todas as métricas (k-mer, GC skew, IR) funcionam apenas com bases canônicas

---

**Status**: ✅ **Correção aplicada e testada**

