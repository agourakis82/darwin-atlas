# Issue: FFI Demetrios - Símbolos não exportados

**Status**: 🔴 Crítico  
**Prioridade**: Alta  
**Criado**: 2025-12-19  
**Atribuído**: Em investigação

---

## Problema

As funções `extern "C" fn` definidas em `demetrios/src/ffi.d` não estão sendo exportadas na biblioteca compartilhada `libdarwin_kernels.so`, impedindo que Julia as chame via `ccall`.

### Sintomas

```bash
$ nm -D demetrios/target/release/libdarwin_kernels.so | grep darwin_
# Nenhum símbolo encontrado

$ julia --project=julia -e 'using DarwinAtlas; DarwinAtlas.demetrios_orbit_size(LongDNA{4}("ATCG"))'
ERROR: could not load symbol "darwin_orbit_size": undefined symbol: darwin_orbit_size
```

### Impacto

- ❌ Cross-validation não funciona (sempre usa Julia puro)
- ❌ Não demonstra capacidades únicas do Demetrios
- ❌ FFI completamente inoperante

---

## Investigação

### Estado Atual

1. **Compilação**: ✅ Sucesso
   - `dc build --cdylib src/lib.d` compila sem erros
   - Biblioteca `.so` é gerada (15KB)

2. **Module Loader**: ✅ Funcional
   - `module_loader` resolve imports corretamente
   - Módulos são mesclados no AST

3. **Type Checker**: ✅ Funcional
   - `check_function` preserva `extern_abi`
   - Funções aparecem no HIR

4. **HLIR Lowering**: ✅ Funcional
   - `lower_module` inclui todas as funções
   - `lower_function` preserva `extern_abi`

5. **LLVM Codegen**: ⚠️ Suspeito
   - `declare_function` usa `Linkage::External` para `extern "C" fn`
   - Mas símbolos não aparecem na biblioteca final

6. **Linker**: ⚠️ Suspeito
   - Flags `--export-dynamic` adicionadas
   - Mas pode não ser suficiente

### Hipóteses

1. **Funções não estão no HLIR**
   - Verificar se `ffi.d` está sendo incluído
   - Verificar se funções aparecem em `hlir.functions`

2. **Codegen não está gerando símbolos**
   - Verificar se funções são declaradas no LLVM IR
   - Verificar linkage no LLVM

3. **Linker está removendo símbolos**
   - Verificar flags do linker
   - Verificar se símbolos estão no objeto antes do link

4. **Mangling de nomes**
   - Verificar se nomes estão corretos
   - Verificar se `no_mangle` está sendo aplicado

---

## Plano de Ação

### Fase 1: Diagnóstico (Hoje)

- [ ] Verificar se funções estão no AST após `module_loader`
- [ ] Verificar se funções estão no HIR após type checker
- [ ] Verificar se funções estão no HLIR antes do codegen
- [ ] Verificar LLVM IR gerado
- [ ] Verificar objeto `.o` antes do link
- [ ] Verificar flags do linker

### Fase 2: Fix (Amanhã)

- [ ] Implementar correção baseada em diagnóstico
- [ ] Testar compilação
- [ ] Verificar símbolos exportados
- [ ] Testar chamada via Julia

### Fase 3: Validação (Depois de amanhã)

- [ ] Cross-validation completa
- [ ] Testes de todas as funções FFI
- [ ] Documentar solução

---

## Logs de Investigação

### 2025-12-19 14:15

**Observação**: Compilador mostra `Compiled 5 items, 0 functions`

Isso sugere que as funções não estão sendo incluídas no processo de compilação, mesmo com `module_loader` funcionando.

**Análise**:
- `module_loader` mescla módulos no AST (linha 124: `items.append(&mut module.ast.items)`)
- Type checker processa items do AST (linha 1127: `check_item`)
- Mas `hlir.functions.len()` retorna 0

**Hipótese Principal**: As funções de `ffi.d` estão no AST, mas não estão sendo processadas pelo type checker porque:
1. O type checker pode estar ignorando funções de módulos importados
2. As funções podem estar sendo filtradas em algum ponto
3. O `check_item` pode não estar sendo chamado para todas as funções

**Descobertas**:
1. ✅ Parser: `parse_extern_c_fn` existe e cria `Item::Function` corretamente
2. ✅ Module Loader: Mescla módulos no AST (linha 124: `items.append(&mut module.ast.items)`)
3. ❌ Type Checker: Funções não chegam ao HIR (0 functions no output)
4. ❌ HLIR: Vazio porque HIR está vazio

**Hipótese Principal**: 
O type checker pode estar ignorando funções de módulos importados, ou há um filtro que remove funções não referenciadas.

**Descoberta Crítica** 🎯:
- ✅ `test_ffi_parse.d` (arquivo simples): **FUNCIONA** - "Compiled 1 items, 1 functions", símbolo exportado
- ❌ `lib.d` (com imports): "Compiled 5 items, 0 functions", nenhum símbolo

**Conclusão**: O problema NÃO está no parser ou type checker, mas sim em como o `module_loader` processa funções de módulos importados.

**Hipótese Refinada**:
O `module_loader` mescla os módulos no AST (linha 124: `items.append(&mut module.ast.items)`), mas as funções de `ffi.d` podem estar sendo:
1. Filtradas antes de chegar ao type checker
2. Não processadas pelo type checker porque são de módulo importado
3. Removidas por dead code elimination

**Descobertas Finais**:

1. ✅ **Parser funciona**: `parse_extern_c_fn` cria `Item::Function` corretamente
2. ✅ **Teste isolado funciona**: `test_ffi_parse.d` compila e exporta símbolo
3. ❌ **Problema com imports**: `lib.d` com `pub import ffi;` não inclui funções
4. ❌ **ffi.d não compila sozinho**: Depende de outros módulos (esperado)

**Causa Raiz Identificada** 🔍:

O `module_loader` mescla módulos no AST (linha 124), mas há uma verificação de duplicatas (linha 130-136) que pode estar causando problemas. Além disso, o type checker pode não estar processando funções de módulos importados que não são referenciadas.

**Solução Proposta**:

1. **Workaround Imediato**: Incluir funções `extern "C" fn` diretamente em `lib.d` (sem import)
2. **Fix Permanente**: Modificar `module_loader` ou type checker para garantir que funções `extern "C" fn` sejam sempre incluídas, mesmo se não referenciadas

**Status Final**:

1. ✅ **Investigação completa**: Causa raiz identificada
2. ❌ **Workaround falhou**: Incluir funções diretamente em `lib.d` causa erros de tipo
   - Problema: Compilador Demetrios não infere corretamente `operators.Sequence` a partir de `[]`
   - Erro: `Type mismatch: expected operators::Sequence, found [?T0; 0]`
3. ⏳ **Fix permanente necessário**: Modificar compilador Demetrios

**Solução Permanente Proposta**:

Modificar `module_loader.rs` ou `check/mod.rs` para garantir que funções `extern "C" fn` sejam sempre incluídas no HIR, mesmo se não referenciadas. Isso pode ser feito:

1. **Opção A**: Modificar `into_ast` em `module_loader.rs` para incluir explicitamente funções `extern "C" fn`
2. **Opção B**: Modificar type checker para não filtrar funções `extern "C" fn` durante dead code elimination
3. **Opção C**: Adicionar flag especial para funções `extern "C" fn` que as marca como "always include"

**Próximos passos**:
1. ✅ Investigação completa
2. ❌ Workaround (falhou)
3. ⏳ Implementar fix permanente no compilador Demetrios
4. ⏳ Testar fix

---

## Soluções Alternativas

### Workaround 1: Wrapper C

Criar wrapper C que chama funções Demetrios internamente:

```c
// wrapper.c
#include "demetrios_kernels.h"

extern size_t darwin_orbit_size_internal(const uint8_t* seq, size_t len);

size_t darwin_orbit_size(const uint8_t* seq, size_t len) {
    return darwin_orbit_size_internal(seq, len);
}
```

**Prós**: Funciona imediatamente  
**Contras**: Menos elegante, não demonstra FFI direto

### Workaround 2: Biblioteca Estática

Compilar como biblioteca estática e linkar com Julia:

**Prós**: Símbolos garantidos  
**Contras**: Requer rebuild do Julia package

---

## Referências

- [CLAUDE.md](../CLAUDE.md) - Arquitetura do projeto
- [EVOLUTION_PLAN.md](../EVOLUTION_PLAN.md) - Plano de evolução
- Compilador Demetrios: `/home/maria/demetrios/compiler`

---

**Última Atualização**: 2025-12-19 14:15

