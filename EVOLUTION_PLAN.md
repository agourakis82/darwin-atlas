# Darwin Atlas — Plano de Evolução

**Versão Atual**: 2.0.0-alpha  
**Data**: 2025-12-19  
**Autor**: Demetrios Chiuratto Agourakis

---

## 📊 Estado Atual

### ✅ Componentes Funcionais

1. **Pipeline Completo**
   - Download NCBI: ✅ Funcional (200 genomas testados)
   - Validação Técnica: ✅ Passando
   - Geração de Tabelas: ✅ Completa
   - Dataset Atlas v2: ✅ Parquet + CSV + DuckDB

2. **Métricas Biológicas (PR2)**
   - k-mer inversion symmetry: ✅ Implementado
   - GC skew / ori-ter estimation: ✅ Implementado
   - Inverted repeats: ✅ Implementado
   - Replichore metrics: ✅ Implementado

3. **Epistemic Knowledge Layer**
   - Export Knowledge: ✅ Funcional (32k+ registros)
   - Validação: ✅ Funcional (via Julia fallback)
   - Schema: ✅ Completo

4. **Infraestrutura**
   - Storage Parquet: ✅ Particionado
   - Query Layer DuckDB: ✅ Funcional
   - Snapshot Builder: ✅ Preparado para Zenodo

### ⚠️ Limitações Conhecidas

1. **Demetrios FFI**
   - Símbolos `extern "C" fn` não exportados corretamente
   - Cross-validation falha (usa Julia puro)
   - Impacto: Não demonstra capacidades únicas do Demetrios

2. **Demetrios Knowledge Validator**
   - Erros de tipo no `verify_knowledge.d`
   - Fallback Julia funciona, mas perde showcase do Demetrios
   - Impacto: Epistemic computing não demonstrado

3. **Escala**
   - Testado até 200 genomas (~445 replicons)
   - Target: 10k-100k replicons
   - Necessita otimizações de performance

4. **Documentação**
   - Paper Scientific Data: ⚠️ Rascunho
   - Data Dictionary: ⚠️ Parcial
   - API Documentation: ⚠️ Básica

---

## 🎯 Objetivos de Evolução

### Curto Prazo (1-2 meses)

1. **Resolver FFI Demetrios** (Crítico)
   - Fix exportação de símbolos `extern "C" fn`
   - Habilitar cross-validation real
   - Demonstrar capacidades únicas do Demetrios

2. **Completar Knowledge Validator Demetrios**
   - Corrigir erros de tipo
   - Habilitar validação epistêmica nativa
   - Showcase epistemic computing

3. **Otimização de Performance**
   - Profiling do pipeline completo
   - Otimização de hotspots
   - Suporte a processamento paralelo

4. **Documentação Científica**
   - Completar paper Scientific Data
   - Data Dictionary completo
   - Métodos e validação técnica

### Médio Prazo (3-6 meses)

1. **Escala 10k+ Replicons**
   - Otimização de memória
   - Processamento incremental
   - Checkpoint/resume do pipeline

2. **Métricas Avançadas**
   - Análise de simetria em janelas deslizantes
   - Correlações entre métricas
   - Análise comparativa entre espécies

3. **Interface de Consulta Avançada**
   - Query builder interativo
   - Visualizações de dados
   - Export customizado

4. **Reprodutibilidade Aprimorada**
   - Containers Docker
   - CI/CD completo
   - Testes de regressão

### Longo Prazo (6-12 meses)

1. **Atlas v3.0**
   - Suporte a genomas eucarióticos
   - Análise de simetria em múltiplas escalas
   - Integração com bancos externos

2. **Plataforma Web**
   - Interface web para consultas
   - Visualizações interativas
   - API REST

3. **Extensibilidade**
   - Plugin system para novas métricas
   - Integração com ferramentas externas
   - Formatos de export adicionais

---

## 🚀 Roadmap Detalhado

### Fase 1: Estabilização (Sprint 1-2)

**Objetivo**: Resolver bloqueadores críticos

#### Sprint 1: FFI Demetrios
- [ ] Investigar causa raiz da não-exportação de símbolos
- [ ] Fix no compilador Demetrios ou workaround
- [ ] Testes de cross-validation passando
- [ ] Documentar solução

**Critérios de Aceitação**:
- `make cross-validate` passa 100%
- Símbolos visíveis em `nm -D libdarwin_kernels.so`
- Julia consegue chamar funções Demetrios via FFI

#### Sprint 2: Knowledge Validator Demetrios
- [ ] Corrigir erros de tipo em `verify_knowledge.d`
- [ ] Testar validação completa
- [ ] Comparar resultados Julia vs Demetrios
- [ ] Documentar epistemic computing

**Critérios de Aceitação**:
- `dc run verify_knowledge.d` funciona sem erros
- Validação passa para dataset completo
- Report gerado corretamente

**Estimativa**: 2-3 semanas

---

### Fase 2: Otimização (Sprint 3-4)

**Objetivo**: Preparar para escala 10k+

#### Sprint 3: Profiling e Otimização
- [ ] Profile pipeline completo (200 genomas)
- [ ] Identificar hotspots de performance
- [ ] Otimizar operações críticas
- [ ] Benchmark antes/depois

**Focos**:
- Parsing FASTA
- Cálculo de métricas
- Escrita Parquet
- Queries DuckDB

#### Sprint 4: Processamento Paralelo
- [ ] Paralelizar download NCBI
- [ ] Paralelizar cálculo de métricas
- [ ] Gerenciamento de memória
- [ ] Testes de carga

**Critérios de Aceitação**:
- Pipeline 10x mais rápido
- Memória estável em 10k replicons
- Processamento paralelo funcional

**Estimativa**: 3-4 semanas

---

### Fase 3: Escala (Sprint 5-6)

**Objetivo**: Suportar 10k-100k replicons

#### Sprint 5: Processamento Incremental
- [ ] Checkpoint/resume do pipeline
- [ ] Processamento em batches
- [ ] Validação incremental
- [ ] Recuperação de erros

#### Sprint 6: Testes de Escala
- [ ] Teste com 1k replicons
- [ ] Teste com 10k replicons
- [ ] Teste com 50k replicons
- [ ] Otimizações adicionais

**Critérios de Aceitação**:
- Pipeline completa 10k replicons em < 24h
- Memória < 64GB
- Sem perda de dados

**Estimativa**: 4-5 semanas

---

### Fase 4: Documentação e Publicação (Sprint 7-8)

**Objetivo**: Preparar para publicação Scientific Data

#### Sprint 7: Paper Scientific Data
- [ ] Completar seção Methods
- [ ] Completar seção Data Records
- [ ] Completar seção Technical Validation
- [ ] Figuras e tabelas
- [ ] Revisão interna

#### Sprint 8: Documentação Técnica
- [ ] Data Dictionary completo
- [ ] API Documentation
- [ ] Guias de uso
- [ ] Exemplos de queries

**Critérios de Aceitação**:
- Paper submetido
- Documentação completa
- Exemplos funcionais

**Estimativa**: 4-6 semanas

---

## 🔧 Melhorias Técnicas Prioritárias

### 1. Arquitetura FFI

**Problema**: Símbolos não exportados

**Soluções Possíveis**:
1. **Fix no Compilador Demetrios** (preferencial)
   - Investigar `module_loader` e codegen
   - Garantir que `extern "C" fn` sejam incluídos no HIR/HLIR
   - Fix linkage no LLVM

2. **Workaround: Wrapper C**
   - Criar wrapper C que chama funções Demetrios
   - Exportar wrapper via FFI tradicional
   - Menos elegante, mas funcional

3. **Alternativa: JIT Demetrios**
   - Se Demetrios suportar JIT, usar diretamente
   - Evitar FFI completamente
   - Requer suporte no runtime

**Prioridade**: 🔴 Crítica

---

### 2. Performance

**Bottlenecks Identificados**:
- Parsing FASTA: O(n) por arquivo
- Cálculo de métricas: O(n²) para IR detection
- Escrita Parquet: I/O bound

**Otimizações Propostas**:
- Streaming FASTA parser
- Algoritmo O(n log n) para IR detection
- Escrita Parquet paralela
- Cache de resultados intermediários

**Prioridade**: 🟡 Alta

---

### 3. Testes e Validação

**Cobertura Atual**: ~60%

**Melhorias**:
- Testes unitários para todas as métricas
- Testes de integração end-to-end
- Testes de regressão
- Testes de performance

**Prioridade**: 🟡 Alta

---

### 4. CI/CD

**Estado Atual**: Básico

**Melhorias**:
- Testes automatizados em PR
- Build e teste em múltiplas plataformas
- Validação de dados
- Deploy automático de snapshots

**Prioridade**: 🟢 Média

---

## 📈 Métricas de Sucesso

### Técnicas
- [ ] Cross-validation: 100% match Julia/Demetrios
- [ ] Performance: 10k replicons em < 24h
- [ ] Memória: < 64GB para 10k replicons
- [ ] Cobertura de testes: > 80%

### Científicas
- [ ] Paper submetido a Scientific Data
- [ ] Dataset publicado no Zenodo
- [ ] DOI atribuído
- [ ] Citações iniciais

### Comunidade
- [ ] Documentação completa
- [ ] Exemplos funcionais
- [ ] Issues respondidas
- [ ] Contribuições externas

---

## 🎓 Áreas de Pesquisa Futura

### 1. Simetria em Múltiplas Escalas
- Análise de simetria em diferentes resoluções
- Correlação entre simetria local e global
- Padrões evolutivos

### 2. Simetria e Função
- Correlação entre simetria e elementos funcionais
- Simetria em regiões codificantes vs não-codificantes
- Impacto evolutivo

### 3. Simetria Comparativa
- Comparação entre espécies
- Padrões filogenéticos
- Convergência evolutiva

### 4. Aplicações Clínicas
- Simetria em patógenos
- Marcadores de virulência
- Resistência antimicrobiana

---

## 📝 Próximos Passos Imediatos

### Esta Semana
1. [ ] Criar issue para FFI Demetrios
2. [ ] Investigar causa raiz da não-exportação
3. [ ] Testar workarounds possíveis
4. [ ] Documentar findings

### Próximas 2 Semanas
1. [ ] Implementar fix ou workaround FFI
2. [ ] Corrigir Knowledge Validator Demetrios
3. [ ] Executar cross-validation completa
4. [ ] Profile pipeline atual

### Próximo Mês
1. [ ] Otimizações de performance
2. [ ] Testes de escala (1k replicons)
3. [ ] Início da documentação do paper
4. [ ] Planejamento Sprint 3-4

---

## 🤝 Contribuições Bem-Vindas

### Áreas Prioritárias
- Fix FFI Demetrios
- Otimizações de performance
- Testes e validação
- Documentação
- Visualizações

### Como Contribuir
1. Fork do repositório
2. Criar branch para feature
3. Implementar e testar
4. Submeter PR com descrição clara
5. Revisão e merge

---

## 📚 Referências

- [CLAUDE.md](./CLAUDE.md) — Especificação completa do projeto
- [docs/IMPLEMENTATION_PLAN_V2.md](./docs/IMPLEMENTATION_PLAN_V2.md) — Plano de implementação v2
- [DEMETRIOS_MISSING_FEATURES.md](./DEMETRIOS_MISSING_FEATURES.md) — Limitações do Demetrios
- [PR2_SUMMARY.md](./PR2_SUMMARY.md) — Resumo PR2 (Biology Metrics)

---

**Última Atualização**: 2025-12-19  
**Versão do Plano**: 1.0.0

