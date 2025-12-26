# Migração Demetrios → Sounio

**Data**: 2025-01-14  
**Versão**: 2.0.0-alpha → 2.0.0-alpha (pós-migração)

## Resumo

Este commit marca a migração completa do projeto Darwin Operator Symmetry Atlas (DOSA) da linguagem Demetrios para **Sounio**, o novo nome canônico da linguagem científica de programação.

## Mudanças Principais

### Estrutura de Arquivos

- ✅ Pasta `demetrios/` → `sounio/` renomeada
- ✅ Todos arquivos `.d` → `.sio` (31 arquivos)
- ✅ `demetrios.toml` → `sounio.toml`

### Build System

- ✅ `Makefile`: `DEMETRIOS ?= dc` → `SOUNIO ?= souc`
- ✅ Comandos atualizados: `make demetrios` → `make sounio`
- ✅ Paths atualizados: `demetrios/target/` → `sounio/target/`

### Documentação

- ✅ `README.md`: Referências e URLs atualizadas
- ✅ `CLAUDE.md`: Especificação completa atualizada
- ✅ `sounio/README.md`: Documentação atualizada
- ✅ `conductor/tech-stack.md`: URLs atualizadas

### Metadados

- ✅ `.zenodo.json`: Keywords atualizadas
- ✅ `CITATION.cff`: Referência ao repositório canônico

### Código Julia

- ✅ `DemetriosFFI.jl`: Path atualizado para `sounio/`
- ✅ Scripts atualizados: mensagens e paths

### Repositório Canônico

- ✅ Todas URLs atualizadas para: **https://github.com/sounio-lang/sounio**
- ✅ Substituídas referências a:
  - `https://github.com/Chiuratto-AI/demetrios`
  - `https://github.com/chiuratto-AI/demetrios`

## Preservado

- ✅ Nome do autor: "Demetrios Chiuratto Agourakis" mantido em todos os lugares
- ✅ Funcionalidade: Código mantém a mesma funcionalidade
- ✅ Compatibilidade: Nomes de módulos Julia mantidos para compatibilidade (`DemetriosFFI`)

## Breaking Changes

### Requisitos

- **Compilador**: Requer `souc` (Sounio compiler) ao invés de `dc` (Demetrios compiler)
- **Instalação**: Repositório canônico mudou para `https://github.com/sounio-lang/sounio`
- **Extensões**: Arquivos agora usam extensão `.sio` ao invés de `.d`

### Compatibilidade

- O projeto continua funcionando em modo Julia-only se Sounio não estiver instalado
- FFI bindings mantêm compatibilidade com código existente
- Dados e resultados permanecem inalterados

## Próximos Passos

1. Instalar Sounio compiler: `git clone https://github.com/sounio-lang/sounio`
2. Build: `make sounio`
3. Testes: `make test`
4. Cross-validation: `make cross-validate`

## Referências

- **Sounio Language**: https://github.com/sounio-lang/sounio
- **Documentação**: `sounio/README.md`
- **Arquitetura**: `CLAUDE.md`

---

🏛️ **Sounio** — Compute at the Horizon of Certainty 🌊

