# Issue: Parser não aceita `::` em expressões após fix da Issue #9

## Status
🔴 **BLOQUEANTE** - Regressão introduzida pelo fix da Issue #9

## Descrição

Após o fix da Issue #9 que permite `.` em tipos qualificados (e.g., `&operators.Sequence`), o parser agora rejeita `::` em expressões, causando erros de compilação em múltiplos arquivos.

### Erro Observado

```
Error: × Unexpected token ColonColon in expression
```

ou

```
Error: × Unexpected token Semi at start of item
```

### Contexto

O fix da Issue #9 adicionou `parse_type_path()` que aceita tanto `::` quanto `.` como separadores de path em **contextos de tipo**. No entanto, em **contextos de expressão**, o parser ainda usa `parse_path()` que só aceita `::`.

O problema é que o parser agora está rejeitando `::` em expressões, possivelmente devido a uma mudança na lógica de parsing.

### Arquivos Afetados

1. **`demetrios/src/ffi.d`** (linha 113)
   ```d
   let g = quaternion.DicyclicGroup::new(n);  // ❌ Falha
   // ou
   let g = quaternion::DicyclicGroup::new(n);  // ❌ Falha
   ```

2. **`demetrios/src/verify_knowledge.d`** (múltiplas linhas)
   ```d
   var out = String::new();  // ❌ Falha
   let ids = HashSet::new();  // ❌ Falha
   rule: ValidationRule::ProvenancePresent,  // ❌ Falha
   ```

3. **`demetrios/src/quaternion.d`** (múltiplas linhas)
   ```d
   Quaternion::new(1.0, 0.0, 0.0, 0.0)  // ❌ Falha
   ```

### Comportamento Esperado

O parser deve aceitar `::` em expressões (como antes do fix) e também aceitar `.` em tipos (novo comportamento da Issue #9):

```d
// Tipos - ambos devem funcionar
pub fn test(seq: &operators.Sequence) -> operators.Sequence  // ✅ . em tipos
pub fn test(seq: &operators::Sequence) -> operators::Sequence  // ✅ :: em tipos

// Expressões - :: deve funcionar
let g = quaternion::DicyclicGroup::new(n);  // ✅ :: em expressões
var out = String::new();  // ✅ :: em expressões
```

### Possível Causa Raiz

O fix da Issue #9 pode ter afetado inadvertidamente o parsing de expressões. Possíveis causas:

1. **Parser de expressões** pode estar usando `parse_type_path()` em vez de `parse_path()`
2. **Lógica de tokenização** pode estar confundindo `::` em expressões com `::` em tipos
3. **Precedência/associatividade** pode ter mudado, causando parsing incorreto

### Tentativas de Workaround

1. **Usar `.` em expressões** - Falhou:
   ```d
   let g = quaternion.DicyclicGroup.new(n);  // ❌ Unexpected token Semi
   ```

2. **Usar apenas `::` em tipos** - Funciona, mas quebra compatibilidade com Darwin Atlas:
   ```d
   pub fn test(seq: &operators::Sequence) -> operators::Sequence  // ✅ Funciona
   ```

### Impacto

- **BLOQUEANTE**: Impede compilação de múltiplos arquivos
- **Severidade**: Alta - regressão introduzida pelo fix anterior
- **Workaround**: Nenhum viável encontrado

### Ambiente

- **Compilador**: `dc 0.78.1`
- **Commit**: `25aa270` (fix da Issue #9)
- **Sistema**: Linux (Ubuntu)
- **LLVM**: 15 (via inkwell 0.5.0)

### Reprodução

```bash
cd darwin-atlas/demetrios
dc build src/ffi.d
# Error: × Unexpected token ColonColon in expression
```

### Relação com Outras Issues

- **Issue #9**: Fix que introduziu a regressão
- **Issue #7**: Arrays vazios com type aliases - ainda presente
- **Issue #8**: LLVM 15 API - já fixada

### Sugestão de Fix

1. **Verificar `parse_path()`**: Garantir que ainda aceita `::` em expressões
2. **Separar lógica**: `parse_type_path()` para tipos, `parse_path()` para expressões
3. **Testes de regressão**: Adicionar testes que verificam `::` em expressões após o fix

### Logs Completos

```
Building Demetrios kernels...
Using Demetrios compiler: dc 0.78.1
Error:   × Unexpected token ColonColon in expression

⚠️  Build failed - LLVM backend may not be enabled
```

---

**Issue relacionada**: https://github.com/sounio-lang/sounio/issues/9
**Criado em**: 2025-12-28
**Repositório**: https://github.com/sounio-lang/sounio
**Projeto afetado**: Darwin Operator Symmetry Atlas (https://github.com/Chiuratto-AI/darwin-atlas)

