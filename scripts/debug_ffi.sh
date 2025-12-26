#!/bin/bash
# Debug script para investigar problema FFI Demetrios

set -e

echo "=== Debug FFI Demetrios ==="
echo ""

echo "1. Verificando funções em ffi.d:"
cd demetrios
grep -n "pub extern\|extern \"C\" fn" src/ffi.d | head -10
echo ""

echo "2. Verificando imports em lib.d:"
grep "import" src/lib.d
echo ""

echo "3. Compilando com verbose:"
dc build --cdylib src/lib.d -O 3 -o target/release/libdarwin_kernels.so -v 2>&1 | grep -E "Compiled|DEBUG|items|functions|Error" | head -10
echo ""

echo "4. Verificando símbolos na biblioteca:"
if [ -f target/release/libdarwin_kernels.so ]; then
    echo "Biblioteca existe: $(ls -lh target/release/libdarwin_kernels.so | awk '{print $5}')"
    echo "Símbolos darwin_*:"
    nm -D target/release/libdarwin_kernels.so 2>/dev/null | grep darwin_ || echo "Nenhum símbolo darwin_ encontrado"
    echo ""
    echo "Todos os símbolos exportados:"
    nm -D target/release/libdarwin_kernels.so 2>/dev/null | grep " T " | head -10 || echo "Nenhum símbolo exportado"
else
    echo "Biblioteca não encontrada"
fi
echo ""

echo "5. Verificando se module_loader está carregando ffi.d:"
# Verificar se ffi.d existe e é acessível
if [ -f src/ffi.d ]; then
    echo "✓ ffi.d existe"
    echo "  Tamanho: $(wc -l < src/ffi.d) linhas"
    echo "  Funções extern: $(grep -c 'extern "C" fn' src/ffi.d)"
else
    echo "✗ ffi.d não encontrado"
fi

