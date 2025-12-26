# Próximos Passos - Darwin Atlas v2

**Status Atual**: ✅ Kernels Demetrios compilam com sucesso  
**Data**: 2025-12-20

---

## 🎯 Prioridades Imediatas

### 1. **Testar FFI e Cross-Validation** (Alta Prioridade)

**Status**: ✅ Biblioteca disponível, símbolos exportados  
**Próximo**: Executar cross-validation completo

```bash
# Testar cross-validation
julia --project=julia julia/scripts/cross_validation.jl --verbose

# Ou via Makefile
make cross-validate
```

**Objetivos**:
- ✅ Verificar que todos os símbolos FFI estão exportados
- ⏳ Validar que Julia e Demetrios produzem resultados idênticos
- ⏳ Identificar qualquer divergência (tolerância: 0 para discretos, 1e-12 para float)

**Funções a testar**:
- `darwin_orbit_size`
- `darwin_orbit_ratio`
- `darwin_is_palindrome`
- `darwin_is_rc_fixed`
- `darwin_dmin`
- `darwin_dmin_normalized`
- `darwin_hamming_distance`

---

### 2. **Integrar no Pipeline** (Alta Prioridade)

**Status**: ⏳ Pendente  
**Próximo**: Garantir fallback automático Julia → Demetrios

**Arquivos a modificar**:
- `julia/src/ExactSymmetry.jl` - Usar `DemetriosFFI` quando disponível
- `julia/src/ApproxMetric.jl` - Usar `DemetriosFFI` quando disponível
- `julia/src/Operators.jl` - Usar `DemetriosFFI` quando disponível

**Estratégia**:
```julia
function orbit_size(seq::LongDNA{4})
    if DarwinAtlas.HAS_DEMETRIOS[]
        return DarwinAtlas.demetrios_orbit_size(seq)
    else
        return orbit_size_julia(seq)  # Fallback
    end
end
```

**Teste**:
```bash
# Teste rápido
make atlas MAX=10 SEED=42

# Verificar logs para confirmar uso de Demetrios
```

---

### 3. **Métricas Biológicas** (Média Prioridade)

**Status**: ⚠️ Parcial - `KmerInversion.jl` e `GCSkew.jl` existem, mas precisam verificação

**Módulos a implementar/verificar**:

#### 3.1. K-mer Inversion Symmetry
- **Arquivo**: `julia/src/KmerInversion.jl` ✅ (existe)
- **Verificar**: Implementação completa, testes, integração no pipeline
- **Tabelas**: `kmer_inversion`, `kmer_inversion_summary`

#### 3.2. GC Skew / Ori-Ter Estimation
- **Arquivo**: `julia/src/GCSkew.jl` ✅ (existe)
- **Verificar**: Implementação completa, testes, integração no pipeline
- **Tabelas**: `gc_skew_ori_ter`, `replichore_metrics`

#### 3.3. Inverted Repeats Enrichment
- **Arquivo**: `julia/src/InvertedRepeats.jl` ❌ (não encontrado)
- **Criar**: Módulo completo com detecção e baseline
- **Tabelas**: `inverted_repeats`, `inverted_repeats_summary`

**Integração no Pipeline**:
- Adicionar chamadas em `julia/scripts/run_atlas.jl`
- Escrever tabelas em Parquet partitions
- Exportar CSV views

---

### 4. **Epistemic Knowledge Layer** (Média Prioridade)

**Status**: ⚠️ Parcial - Export existe, mas precisa expansão

**Tarefas**:

#### 4.1. Expandir Schema de Knowledge
- Adicionar tipos: `kmer_metric`, `skew_metric`, `ir_metric`, `replichore_metric`
- Definir validity predicates para novas métricas
- Documentar regras de epsilon/confidence

#### 4.2. Extender Export Script
- **Arquivo**: `julia/scripts/export_knowledge.jl`
- Adicionar export para k-mer, skew, IR metrics
- Garantir provenance tracking

#### 4.3. Melhorar Validator Demetrios
- **Arquivo**: `demetrios/src/verify_knowledge.d`
- Adicionar join integrity checks
- Implementar "no-miracles" rule
- Testar com novos tipos de métricas

#### 4.4. Julia Fallback Validator
- **Arquivo**: `julia/scripts/verify_knowledge.jl`
- Mesmas validações do Demetrios
- Usado quando Demetrios não disponível

**Teste**:
```bash
make epistemic MAX=50 SEED=42
```

---

### 5. **Performance e Otimização** (Baixa Prioridade)

**Status**: ⏳ Pendente

**Tarefas**:
- Profile Julia puro vs Demetrios FFI
- Identificar bottlenecks
- Otimizar se necessário

**Ferramentas**:
- Julia: `Profile.jl`, `BenchmarkTools.jl`
- Demetrios: `perf`, `valgrind`

---

## 📋 Checklist de Execução

### Fase 1: Validação FFI (1-2 dias)
- [ ] Executar cross-validation completo
- [ ] Corrigir divergências se houver
- [ ] Documentar resultados

### Fase 2: Integração Pipeline (1 dia)
- [ ] Modificar `ExactSymmetry.jl` para usar Demetrios
- [ ] Modificar `ApproxMetric.jl` para usar Demetrios
- [ ] Modificar `Operators.jl` para usar Demetrios
- [ ] Testar com MAX=10, MAX=50

### Fase 3: Métricas Biológicas (5-7 dias)
- [ ] Verificar `KmerInversion.jl` completo
- [ ] Verificar `GCSkew.jl` completo
- [ ] Implementar `InvertedRepeats.jl`
- [ ] Integrar no pipeline
- [ ] Testes unitários

### Fase 4: Epistemic Layer (3-4 dias)
- [ ] Expandir schema
- [ ] Extender export
- [ ] Melhorar validator
- [ ] Julia fallback
- [ ] Teste end-to-end

### Fase 5: Performance (1-2 dias)
- [ ] Profile completo
- [ ] Otimizações se necessário
- [ ] Documentação

---

## 🚀 Comandos Rápidos

```bash
# Testar FFI
julia --project=julia julia/scripts/cross_validation.jl --verbose

# Pipeline rápido
make atlas MAX=10 SEED=42

# Pipeline médio
make atlas MAX=50 SEED=42

# Epistemic
make epistemic MAX=50 SEED=42

# Query
make query QUERY="SELECT * FROM atlas_replicons LIMIT 10"

# Snapshot
make snapshot MAX=200 SEED=42
```

---

## 📊 Métricas de Sucesso

### Cross-Validation
- ✅ 100% de funções testadas
- ✅ 0 divergências (tolerância: 0 para discretos, 1e-12 para float)
- ✅ Performance: Demetrios ≥ Julia (ou documentar trade-offs)

### Pipeline
- ✅ MAX=50 completa em < 10 min
- ✅ MAX=200 completa em < 1h
- ✅ Todas as tabelas geradas corretamente

### Métricas Biológicas
- ✅ Todas as 3 métricas implementadas
- ✅ Testes unitários passando
- ✅ Integração no pipeline funcionando

### Epistemic Layer
- ✅ Todos os tipos de métricas exportados
- ✅ Validator passa sem erros
- ✅ Join integrity verificada

---

**Última atualização**: 2025-12-20

