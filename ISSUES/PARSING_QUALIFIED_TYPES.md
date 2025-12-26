# Issue: Parser não aceita tipos qualificados com referências (`&module.Type`)

## Status
🔴 **BLOQUEANTE** - Impede compilação dos kernels Darwin Atlas

## Descrição

O parser do Demetrios está falhando ao processar tipos qualificados com referências (`&`) em assinaturas de função, especificamente quando o tipo é importado de outro módulo.

### Erro Observado

```
Error: × Expected Comma, found Dot at position 1140
```

### Contexto

No arquivo `demetrios/src/exact_symmetry.d`, linha 31:

```d
import operators;

pub fn compute_orbit(seq: &operators.Sequence) -> Vec<operators.Sequence> {
    // ...
}
```

O parser falha ao encontrar `&operators.Sequence`, interpretando incorretamente o ponto (`.`) como um operador em vez de parte do path qualificado.

### Arquivos Afetados

1. **`demetrios/src/exact_symmetry.d`** (linha 31)
   ```d
   pub fn compute_orbit(seq: &operators.Sequence) -> Vec<operators.Sequence>
   pub fn orbit_size(seq: &operators.Sequence) -> usize
   pub fn orbit_ratio(seq: &operators.Sequence) -> f64
   pub fn is_palindrome(seq: &operators.Sequence) -> bool
   pub fn is_rc_fixed(seq: &operators.Sequence) -> bool
   pub fn rotational_period(seq: &operators.Sequence) -> usize
   pub fn compute_symmetry_stats(seq: &operators.Sequence) -> SymmetryStats
   ```

2. **`demetrios/src/approx_metric.d`** (linhas 34, 95, 111)
   ```d
   pub fn dmin(seq: &operators.Sequence, include_rc: bool) -> usize
   pub fn dmin_normalized(seq: &operators.Sequence, include_rc: bool) -> f64
   pub fn nearest_transform(seq: &operators.Sequence, include_rc: bool) -> (usize, NearestTransform)
   ```

### Observações

- O mesmo padrão funciona em `demetrios/src/operators.d` quando o tipo não é qualificado:
  ```d
  pub fn shift(seq: &Sequence, k: usize) -> Sequence  // ✅ Funciona
  ```

- O mesmo padrão funciona em `demetrios/src/ffi.d` quando usado sem `&`:
  ```d
  fn ptr_to_sequence(ptr: *const c_uchar, len: usize) -> operators.Sequence  // ✅ Funciona
  ```

- O problema parece ser específico da combinação `&` + path qualificado (`module.Type`)

### Tentativas de Workaround

1. **Alias de tipo local** - Falhou:
   ```d
   type Sequence = operators.Sequence;  // Error: Expected Semi, found Dot
   ```

2. **Usar tipo não qualificado** - Não é viável pois quebra a modularidade

3. **Usar `&[u8]` diretamente** - Perde type safety e quebra a API

### Impacto

- **BLOQUEANTE**: Impede compilação completa dos kernels Darwin Atlas
- **Severidade**: Alta - afeta múltiplos arquivos e funções públicas
- **Workaround**: Nenhum viável encontrado

### Ambiente

- **Compilador**: `dc 0.78.1`
- **Branch**: `feat/module-resolution-imports`
- **Sistema**: Linux (Ubuntu)
- **LLVM**: 15 (via inkwell 0.5.0)

### Reprodução

```bash
cd darwin-atlas/demetrios
dc build src/lib.d
```

Ou:

```bash
cd darwin-atlas
make demetrios
```

### Comportamento Esperado

O parser deve aceitar tipos qualificados com referências em assinaturas de função:

```d
import operators;

pub fn compute_orbit(seq: &operators.Sequence) -> Vec<operators.Sequence> {
    // Deve compilar sem erros
}
```

### Possível Causa Raiz

O parser pode estar interpretando `&operators.Sequence` como:
- `&operators` (referência a um módulo) seguido de `.Sequence` (acesso a membro)
- Em vez de `&(operators.Sequence)` (referência a um tipo qualificado)

### Sugestão de Fix

1. **Parser**: Ajustar a precedência/associatividade para que `&module.Type` seja parseado como `&(module.Type)`
2. **AST**: Garantir que tipos qualificados sejam tratados como unidades atômicas antes da aplicação de `&`
3. **Type Checker**: Verificar se o type checker já suporta isso (pode ser apenas um problema de parsing)

### Relação com Outras Issues

- **Issue #7**: Arrays vazios com type aliases - pode estar relacionado se o problema for no type checker
- **Issue #6**: Module resolution - já fixada, imports funcionam
- **Issue #8**: LLVM 15 API - já fixada, compilador compila

### Logs Completos

```
Building Demetrios kernels...
Using Demetrios compiler: dc 0.78.1
Error:   × Expected Comma, found Dot at position 1140

⚠️  Build failed - LLVM backend may not be enabled
   To fix: cd /home/maria/demetrios/compiler && cargo build --release --features llvm
   Then retry: make demetrios
   Note: Darwin Atlas works without Demetrios (Julia-only mode)
```

### Arquivos de Teste Mínimos

Para reproduzir o problema:

**`test_qualified_ref.d`**:
```d
import operators;

pub fn test(seq: &operators.Sequence) -> operators.Sequence {
    return *seq
}
```

Compilar com:
```bash
dc build test_qualified_ref.d
```

---

**Issue GitHub**: https://github.com/sounio-lang/sounio/issues/9
**Criado em**: 2025-12-28
**Repositório**: https://github.com/sounio-lang/sounio
**Projeto afetado**: Darwin Operator Symmetry Atlas (https://github.com/Chiuratto-AI/darwin-atlas)

