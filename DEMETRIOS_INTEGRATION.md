# Integração Demetrios com Darwin Atlas

**Status**: ⚠️ **Parcial** - Compilador disponível, mas requer LLVM para compilar kernels

---

## Situação Atual

### ✅ Compilador Demetrios
- **Instalado**: `/home/maria/demetrios/compiler/target/release/dc`
- **Versão**: 0.69.0
- **PATH**: Configurado em `~/.bashrc`
- **Status**: Funcional (mas sem LLVM backend)

### ⚠️ Compilação de Kernels
- **Problema**: Compilador precisa ser recompilado com `--features llvm` para gerar bibliotecas compartilhadas
- **Erro**: `LLVM backend not enabled. Rebuild with: cargo build --features llvm`
- **Dependência faltando**: Biblioteca `Polly` do LLVM
- **Solução**: Instalar dependências LLVM e recompilar

---

## Solução: Recompilar Demetrios com LLVM

### Passo 1: Instalar dependências LLVM (se necessário)

```bash
# Ubuntu/Debian
sudo apt-get install libllvm-dev llvm-dev

# Ou instalar Polly especificamente (se disponível)
sudo apt-get install libpolly-dev
```

### Passo 2: Recompilar compilador Demetrios

```bash
cd /home/maria/demetrios/compiler
cargo build --release --features llvm

# Verificar se compilou
which dc
dc --version
```

### Passo 3: Compilar kernels

```bash
cd /home/maria/darwin-atlas
make demetrios
```

### Passo 4: Verificar integração

```bash
julia --project=julia -e 'using DarwinAtlas; println(DarwinAtlas.HAS_DEMETRIOS[])'
# Deve imprimir: true
```

---

## Arquitetura de Integração

### Layer 0: Julia Pura (Referência)
- ✅ Implementação completa em Julia
- ✅ Funciona independentemente
- ✅ Usado para validação cruzada

### Layer 1: Julia + Orquestração
- ✅ Pipeline principal em Julia
- ✅ NCBI fetch, validação, storage
- ✅ Funciona sem Demetrios

### Layer 2: Demetrios Kernels (Opcional)
- ⚠️ Requer compilador com LLVM
- ⚠️ Gera `libdarwin_kernels.so`
- ✅ FFI já implementado em `DemetriosFFI.jl`
- ✅ Carregamento automático quando biblioteca disponível

---

## Estrutura de Arquivos

```
darwin-atlas/
├── demetrios/                    # Layer 2: Demetrios Kernels
│   ├── demetrios.toml           # Configuração do projeto
│   ├── src/
│   │   ├── lib.d                # Módulo raiz
│   │   ├── operators.d          # Operadores S/R/K/RC
│   │   ├── exact_symmetry.d     # Simetria exata
│   │   ├── approx_metric.d      # Métrica aproximada
│   │   ├── quaternion.d         # Lift quaternionic
│   │   └── ffi.d                # Exports FFI para Julia
│   └── target/release/          # Output (gerado)
│       └── libdarwin_kernels.so # Biblioteca compartilhada
│
└── julia/
    └── src/
        ├── DarwinAtlas.jl        # Carrega FFI se disponível
        ├── DemetriosFFI.jl       # Wrappers ccall
        └── CrossValidation.jl    # Validação cruzada
```

---

## Makefile Targets

### `make demetrios`
Compila os kernels Demetrios (requer compilador com LLVM)

### `make setup-demetrios`
Verifica se o compilador está disponível

### `make cross-validate`
Executa validação cruzada entre Julia e Demetrios (requer ambos)

---

## Status de Integração

| Componente | Status | Notas |
|------------|--------|-------|
| Compilador `dc` | ✅ Funcional | Versão 0.69.0 |
| Compilador com LLVM | ⚠️ Precisa recompilar | Requer biblioteca Polly |
| Kernels Demetrios | ⚠️ Não compilados | Requer compilador com LLVM |
| FFI Julia | ✅ Implementado | Carrega automaticamente se `.so` disponível |
| Cross-validation | ⚠️ Pendente | Requer kernels compilados |
| Pipeline Atlas | ✅ Funcional | Usa apenas Julia (Layer 0-1) |

---

## Próximos Passos

1. **Instalar dependências LLVM** (se necessário):
   ```bash
   sudo apt-get install libllvm-dev llvm-dev
   ```

2. **Recompilar Demetrios com LLVM**:
   ```bash
   cd /home/maria/demetrios/compiler
   cargo build --release --features llvm
   ```

3. **Compilar kernels**:
   ```bash
   cd /home/maria/darwin-atlas
   make demetrios
   ```

4. **Testar cross-validation**:
   ```bash
   make cross-validate
   ```

---

## Nota Importante

O Darwin Atlas **funciona completamente sem Demetrios** usando apenas Julia (Layers 0-1). A integração com Demetrios (Layer 2) é **opcional** e serve para:
- Validação cruzada entre implementações
- Demonstração de capacidades do Demetrios
- Kernels de alta performance (quando necessário)

---

## Status Atualizado (2025-12-17)

### ✅ Dependências LLVM Instaladas
- `libpolly-18-dev`: ✅ Instalado
- Bibliotecas encontradas em: `/usr/lib/llvm-18`

### ⚠️ Erros de Compilação no Compilador Demetrios
O compilador Demetrios apresenta erros de compilação Rust ao tentar compilar com `--features llvm`. Os erros são relacionados a:
- Mudanças na API do `inkwell` (bindings Rust para LLVM)
- Métodos renomeados (`build_bitcast` → `build_bit_cast`)
- Traits não importadas (`BasicType` precisa estar no escopo)
- Padrões não exaustivos em matches

**Soluções possíveis:**
1. Atualizar o repositório Demetrios: `cd /home/maria/demetrios && git pull`
2. Corrigir os erros manualmente no código Rust
3. Usar uma versão compatível do `inkwell`

**Nota importante:** O Darwin Atlas funciona completamente sem Demetrios usando apenas Julia (Layers 0-1). A integração Demetrios é opcional e serve para validação cruzada e demonstração de capacidades.

---

## Status Atualizado (2025-12-17 - v0.70.0)

### ✅ Dependências LLVM Instaladas
- `libpolly-18-dev`: ✅ Instalado
- Bibliotecas encontradas em: `/usr/lib/llvm-18`

### ✅ Versão 0.70.0
- Checkout realizado: `git checkout v0.70.0`
- Versão confirmada no `Cargo.toml`: `0.70.0`

### ❌ Erros de Compilação Persistem
A versão 0.70.0 ainda apresenta **18 erros de compilação Rust** ao tentar compilar com `--features llvm`. Os erros são relacionados a:
- Métodos não encontrados na API do `inkwell` (mudanças na API)
- Traits não implementadas (`BasicValueEnum` vs `AggregateValueEnum`)
- Padrões não exaustivos em matches (Vec2, Vec3, Vec4, Mat2, Mat3)
- Mudanças na API de metadados

**Erros principais:**
- `error[E0599]`: Métodos não encontrados (`array_type`, `get_undef`, `build_bitcast`, etc.)
- `error[E0277]`: Traits não implementadas (`From<AggregateValueEnum>`)
- `error[E0004]`: Padrões não exaustivos em matches
- `error[E0061]`: Número incorreto de argumentos em métodos

**Soluções possíveis:**
1. Corrigir os erros manualmente no código Rust do compilador Demetrios
2. Usar uma versão compatível do `inkwell` (downgrade)
3. Aguardar correções no repositório Demetrios

**Nota importante:** O Darwin Atlas funciona completamente sem Demetrios usando apenas Julia (Layers 0-1). A integração Demetrios é opcional e serve para validação cruzada e demonstração de capacidades.

---

## Status Final (2025-12-17 - v0.70.0)

### ✅ Compilador Funcionando
- **Versão**: 0.70.0
- **LLVM Backend**: ✅ Habilitado
- **Polly**: ✅ Instalado (`libpolly-18-dev`)
- **Compilação**: ✅ Bem-sucedida

### ✅ Correções Aplicadas
- Importado trait `BasicType` para usar `array_type()`
- Corrigido `build_bitcast` → `build_bit_cast`
- Corrigido conversões `AggregateValueEnum` → `BasicValueEnum`
- Removido `create_subrange` (API mudou no inkwell)
- Corrigido sintaxe `CondBr` e `Return`
- Corrigido `into_struct_value()`/`into_array_value()` (não existem, usar diretamente)
- Corrigido chamada `compile()` em `lib.rs`
- Corrigido `get_named_metadata` → `get_global_metadata`
- Corrigido erros de tipo em `GpuTerminator::Return` e `GpuType::Struct`

### ✅ Integração Completa
- Compilador `dc` compilado com sucesso
- Biblioteca `libdarwin_kernels.so` gerada
- Integração Julia funcionando (`HAS_DEMETRIOS: true`)

---

**Última atualização**: 2025-12-17 (v0.70.0) - ✅ FUNCIONANDO
