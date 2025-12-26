# Resultados - Pipeline Escala 500

**Data**: 2025-12-20  
**Configuração**: MAX=500, SEED=42  
**Status**: ✅ COMPLETO

---

## 📊 Resumo Executivo

- **Genomas processados**: 500
- **Replicons analisados**: 1,119
- **Tempo total**: ~11 minutos
- **Records epistemic**: 80,659
- **Tamanho do dataset**: 62 MB

---

## 📈 Estatísticas por Tabela

### Tabelas Principais

| Tabela | Linhas | Descrição |
|--------|--------|-----------|
| `atlas_replicons.csv` | 1,119 | Metadados dos replicons |
| `kmer_inversion.csv` | 11,190 | Métricas k-mer (k=1..10) |
| `gc_skew_ori_ter.csv` | 1,119 | Estimativas ori/ter |
| `replichore_metrics.csv` | 2,238 | Métricas por replichore |
| `inverted_repeats_summary.csv` | 1,119 | Resumo de inverted repeats |
| `quaternion_results.csv` | 15 | Resultados quaternion |
| `dicyclic_lifts.csv` | 4 | Lifts dicyclic |

### Partições Parquet

- `kmer_inversion`: 10 partições
- `atlas_replicons`: 5 partições
- Outras tabelas: 1 partição cada

---

## 🧬 Métricas Biológicas

### K-mer Inversion Symmetry
- **Tabela**: `kmer_inversion.csv`
- **Linhas**: 11,190 (10 k-values × 1,119 replicons)
- **Métricas**: X_k, K_L(tau)

### GC Skew / Ori-Ter
- **Tabela**: `gc_skew_ori_ter.csv`
- **Linhas**: 1,119
- **Métricas**: ori_position, ter_position, confidence, gc_skew_amplitude

### Replichore Metrics
- **Tabela**: `replichore_metrics.csv`
- **Linhas**: 2,238 (2 replichores × 1,119 replicons)
- **Métricas**: length_bp, gc_fraction, x_k_6

### Inverted Repeats
- **Tabela**: `inverted_repeats_summary.csv`
- **Linhas**: 1,119
- **Métricas**: ir_count, ir_density, enrichment_ratio, p_value

---

## 📚 Epistemic Knowledge Layer

- **Records exportados**: 80,659
- **Arquivo**: `atlas_knowledge.jsonl`
- **Provenance**: `atlas_provenance.json`
- **Cobertura**: Todas as métricas incluídas

---

## ⚠️ Problemas Conhecidos

1. **Validator Demetrios**: Erro de parsing (não bloqueia)
   - Erro: `Expected Semi, found Dot at position 1790`
   - Impacto: Validator não executa, mas export funciona

2. **Makefile Demetrios**: Argumento `--release` não suportado
   - Impacto: Build do Demetrios falha no Makefile
   - Solução: Kernels já compilados, não bloqueia pipeline

---

## ✅ Validação

- ✅ Pipeline completo executado
- ✅ Todas as tabelas geradas
- ✅ Epistemic layer exportado
- ✅ Parquet partitions criadas
- ✅ CSV views disponíveis
- ✅ Provenance tracking completo

---

## 🚀 Próximos Passos

1. **Validar dados**: Verificar correção dos resultados
2. **Profile performance**: Identificar bottlenecks
3. **Escalar mais**: Testar com MAX=1000 ou MAX=5000
4. **Preparar snapshot**: Para depósito no Zenodo
5. **Documentação**: Preparar manuscrito Scientific Data

---

**Última atualização**: 2025-12-20 23:55 UTC

