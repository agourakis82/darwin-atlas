# Funcionalidades Faltantes no Demetrios para `verify_knowledge.d`

## Resumo Executivo

O arquivo `demetrios/src/verify_knowledge.d` requer funcionalidades de I/O e JSON parsing que ainda não estão totalmente implementadas na biblioteca padrão do Demetrios (v0.72.0). Este documento detalha cada funcionalidade faltante, seu uso no código, e o que seria necessário para implementá-la.

---

## 1. Módulo `std.io` (I/O Operations)

### 1.1 Tipo `IoError`

**Uso no código:**
```d
pub fn validate_knowledge_file(path: &str) -> Result<ValidationReport, IoError> with IO
```

**Descrição:**
- Tipo de erro para operações de I/O (leitura/escrita de arquivos)
- Deve ser compatível com `Result<T, IoError>` e o operador `?` (try)

**Requisitos:**
- Enum ou struct que representa diferentes tipos de erro de I/O
- Implementação de `Display` ou `ToString` para mensagens de erro
- Compatibilidade com `Result<T, E>` e propagação de erros

**Exemplo de implementação esperada:**
```d
pub enum IoError {
    NotFound { path: String },
    PermissionDenied { path: String },
    ReadError { path: String, message: String },
    WriteError { path: String, message: String },
    // ... outros tipos de erro
}
```

---

### 1.2 Função `read_file(path: &str) -> Result<String, IoError>`

**Uso no código:**
```d
let content = read_file(path)?;  // Linha 91
match read_file(path) {          // Linha 662
    Ok(content) => { ... }
    Err(_) => {}
}
```

**Descrição:**
- Lê o conteúdo completo de um arquivo como `String`
- Retorna `Result<String, IoError>` para tratamento de erros
- Deve funcionar com o operador `?` para propagação de erros

**Requisitos:**
- Abrir arquivo em modo leitura
- Ler todo o conteúdo em uma única operação
- Fechar arquivo automaticamente (RAII)
- Tratar erros (arquivo não encontrado, permissão negada, etc.)

**Exemplo de uso esperado:**
```d
// Com propagação de erro
let content = read_file("data/file.txt")?;

// Com match
match read_file("data/file.txt") {
    Ok(content) => println!("Read {} bytes", content.len()),
    Err(e) => println!("Error: {}", e),
}
```

---

### 1.3 Função `write_file(path: &str, content: &str) -> Result<(), IoError>`

**Uso no código:**
```d
write_file(&output_path, &report_str).unwrap();  // Linha 629
```

**Descrição:**
- Escreve uma `String` completa em um arquivo
- Cria o arquivo se não existir, sobrescreve se existir
- Retorna `Result<(), IoError>` para tratamento de erros

**Requisitos:**
- Criar arquivo se não existir
- Escrever conteúdo completo
- Fechar arquivo automaticamente
- Tratar erros (diretório não existe, permissão negada, disco cheio, etc.)

**Exemplo de uso esperado:**
```d
match write_file("output.txt", "Hello, world!") {
    Ok(()) => println!("File written successfully"),
    Err(e) => println!("Error: {}", e),
}
```

---

### 1.4 Função `exit(code: i32) -> !`

**Uso no código:**
```d
exit(1);  // Linha 638, 641, 646
exit(0);  // Linha 641
```

**Descrição:**
- Encerra o processo com código de saída
- Tipo de retorno `!` indica função que nunca retorna (divergente)
- Código 0 = sucesso, código != 0 = erro

**Requisitos:**
- Chamar `std::process::exit()` ou equivalente do sistema
- Tipo de retorno divergente (`!` em Rust, `Never` em alguns sistemas de tipos)
- Deve ser marcado como `with IO` ou similar para efeitos

**Exemplo de uso esperado:**
```d
if error_occurred {
    exit(1);  // Nunca retorna
}
exit(0);  // Sucesso
```

---

### 1.5 Função `env::args() -> Vec<String>`

**Uso no código:**
```d
let args = env::args();  // Linha 608
let input_path = if args.len() > 1 {
    args[1].clone()
} else {
    "data/epistemic/atlas_knowledge.jsonl".into()
};
```

**Descrição:**
- Retorna vetor de argumentos da linha de comando
- Primeiro elemento é o nome do programa
- Elementos subsequentes são argumentos passados

**Requisitos:**
- Acessar argumentos da linha de comando do sistema
- Retornar `Vec<String>`
- Primeiro elemento = nome do executável

**Exemplo de uso esperado:**
```d
// Se executado: ./program input.jsonl output.md
let args = env::args();
// args = ["program", "input.jsonl", "output.md"]
```

---

## 2. Módulo `std.json` (JSON Parsing)

### 2.1 Tipo `JsonValue`

**Uso no código:**
```d
pub struct KnowledgeRecord {
    value: JsonValue,  // Linha 26
    // ...
}

fn validate_record(json: &JsonValue, ...) -> ...  // Linha 147
```

**Descrição:**
- Tipo que representa qualquer valor JSON (objeto, array, string, número, bool, null)
- Deve suportar acesso indexado (`json["key"]`) e métodos de conversão

**Requisitos:**
- Representar todos os tipos JSON:
  - Objeto (`{ "key": "value" }`)
  - Array (`[1, 2, 3]`)
  - String (`"text"`)
  - Número (`123`, `45.67`)
  - Boolean (`true`, `false`)
  - Null (`null`)
- Suportar acesso indexado: `json["key"]` para objetos
- Suportar métodos de conversão: `as_str()`, `as_f64()`, `as_i64()`, `as_bool()`
- Suportar verificação de existência: `has("key")`

**Exemplo de uso esperado:**
```d
let json: JsonValue = parse_json(r#"{"name": "test", "value": 42}"#)?;
let name = json["name"].as_str().unwrap_or("default");
let value = json["value"].as_i64().unwrap_or(0);
if json.has("optional_key") {
    // ...
}
```

---

### 2.2 Função `parse_json(input: &str) -> Result<JsonValue, ParseError>`

**Uso no código:**
```d
match parse_json(line) {  // Linha 107
    Ok(json) => { ... }
    Err(e) => { ... }
}
```

**Descrição:**
- Faz parsing de uma string JSON para `JsonValue`
- Retorna `Result<JsonValue, ParseError>` para tratamento de erros
- Deve suportar JSON válido conforme RFC 7159

**Requisitos:**
- Parser JSON completo e robusto
- Suportar:
  - Objetos aninhados
  - Arrays aninhados
  - Strings com escape (`\"`, `\n`, `\uXXXX`, etc.)
  - Números (inteiros e floats)
  - Boolean e null
- Tratar erros de sintaxe (JSON inválido)
- Retornar `ParseError` com mensagem descritiva

**Exemplo de uso esperado:**
```d
match parse_json(r#"{"key": "value"}"#) {
    Ok(json) => {
        let value = json["key"].as_str().unwrap();
    }
    Err(e) => {
        println!("Parse error: {}", e);
    }
}
```

---

### 2.3 Métodos de `JsonValue`

#### 2.3.1 `json.has(key: &str) -> bool`

**Uso no código:**
```d
if !json.has("provenance") { ... }  // Linha 153
if !prov.has("atlas_git_sha") { ... }  // Linha 166
// ... muitas outras ocorrências
```

**Descrição:**
- Verifica se uma chave existe em um objeto JSON
- Retorna `false` se a chave não existe ou se o valor não é um objeto

**Requisitos:**
- Funcionar apenas em objetos JSON
- Retornar `false` para arrays, strings, números, etc.
- Retornar `false` se a chave não existe

---

#### 2.3.2 `json["key"] -> &JsonValue` (Indexação)

**Uso no código:**
```d
let prov = &json["provenance"];  // Linha 162
let record_type = json["record_type"].as_str().unwrap_or("");  // Linha 225
let validity = &json["validity"];  // Linha 291
// ... muitas outras ocorrências
```

**Descrição:**
- Acessa um campo de um objeto JSON por chave
- Retorna referência a `JsonValue`
- Deve retornar `JsonValue::Null` ou similar se a chave não existe

**Requisitos:**
- Implementar trait `Index<&str>` ou equivalente
- Retornar referência a `JsonValue`
- Tratar chaves inexistentes (retornar null ou panicking)

---

#### 2.3.3 `json.as_str() -> Option<&str>`

**Uso no código:**
```d
prov["atlas_git_sha"].as_str().unwrap_or("")  // Linha 166
json["record_type"].as_str().unwrap_or("")  // Linha 225
validity["predicate"].as_str().unwrap_or("?")  // Linha 307
// ... muitas outras ocorrências
```

**Descrição:**
- Converte `JsonValue` para `&str` se for uma string JSON
- Retorna `Option<&str>` (Some se for string, None caso contrário)

**Requisitos:**
- Verificar se o valor é string JSON
- Retornar `Some(&str)` se for string
- Retornar `None` se for outro tipo

---

#### 2.3.4 `json.as_f64() -> Option<f64>`

**Uso no código:**
```d
if let Some(eps) = json["epsilon"].as_f64() { ... }  // Linha 258
if let Some(conf) = json["confidence"].as_f64() { ... }  // Linha 270
if let Some(value) = json["value"].as_f64() { ... }  // Linha 319
```

**Descrição:**
- Converte `JsonValue` para `f64` se for um número JSON
- Retorna `Option<f64>` (Some se for número, None caso contrário)
- Deve suportar números inteiros e floats

**Requisitos:**
- Verificar se o valor é número JSON
- Converter inteiros para `f64`
- Retornar `Some(f64)` se for número
- Retornar `None` se for outro tipo

---

#### 2.3.5 `json.as_i64() -> Option<i64>`

**Uso no código:**
```d
if prov["pipeline_max"].as_i64().is_none() { ... }  // Linha 206
if prov["pipeline_seed"].as_i64().is_none() { ... }  // Linha 216
```

**Descrição:**
- Converte `JsonValue` para `i64` se for um número inteiro JSON
- Retorna `Option<i64>` (Some se for inteiro, None caso contrário)

**Requisitos:**
- Verificar se o valor é número inteiro JSON
- Retornar `Some(i64)` se for inteiro
- Retornar `None` se for float ou outro tipo

---

#### 2.3.6 `json.as_bool() -> Option<bool>`

**Uso no código:**
```d
if validity["holds"].as_bool().is_none() { ... }  // Linha 293
if let Some(holds) = validity["holds"].as_bool() { ... }  // Linha 304
```

**Descrição:**
- Converte `JsonValue` para `bool` se for um boolean JSON
- Retorna `Option<bool>` (Some se for boolean, None caso contrário)

**Requisitos:**
- Verificar se o valor é boolean JSON (`true` ou `false`)
- Retornar `Some(bool)` se for boolean
- Retornar `None` se for outro tipo

---

## 3. Módulo `std` (Utilitários)

### 3.1 Função `min(a: T, b: T) -> T`

**Uso no código:**
```d
for failure in &report.failures[..min(20, report.failures.len())] {  // Linha 591
```

**Descrição:**
- Retorna o menor de dois valores
- Deve funcionar com tipos comparáveis (números, etc.)

**Requisitos:**
- Função genérica que aceita qualquer tipo `T: Ord` ou similar
- Retornar o menor valor entre `a` e `b`

**Exemplo de uso esperado:**
```d
let smaller = min(10, 20);  // 10
let smaller = min(3.14, 2.71);  // 2.71
```

---

## 4. Métodos de `String` e `&str`

### 4.1 `str.lines() -> Iterator<&str>`

**Uso no código:**
```d
let lines: Vec<String> = content.lines().collect();  // Linha 92
var iter = content.lines();  // Linha 677
```

**Descrição:**
- Retorna um iterador sobre as linhas de uma string
- Cada linha é um `&str` (sem o caractere de nova linha)

**Requisitos:**
- Dividir string por `\n` ou `\r\n`
- Remover caracteres de nova linha do final de cada linha
- Retornar iterador lazy

---

### 4.2 `str.split(delimiter: &str) -> Iterator<&str>`

**Uso no código:**
```d
let cols: Vec<&str> = header.split(',').collect();  // Linha 683
let parts: Vec<&str> = line.split(',').collect();  // Linha 702
```

**Descrição:**
- Divide uma string por um delimitador
- Retorna iterador sobre as partes

**Requisitos:**
- Dividir string por delimitador
- Retornar iterador lazy
- Não incluir o delimitador nos resultados

---

### 4.3 `str.trim() -> &str`

**Uso no código:**
```d
if line.trim().is_empty() { ... }  // Linhas 102, 699
if c.trim() == "replicon_id" { ... }  // Linha 686
let rid = parts[rid_idx].trim();  // Linha 706
```

**Descrição:**
- Remove espaços em branco do início e fim de uma string
- Retorna slice da string original

**Requisitos:**
- Remover `' '`, `'\t'`, `'\n'`, `'\r'` do início e fim
- Retornar referência (não alocar nova string)

---

### 4.4 `str.is_empty() -> bool`

**Uso no código:**
```d
if line.trim().is_empty() { ... }  // Linhas 102, 699
if rid.is_empty() { ... }  // Linha 238
```

**Descrição:**
- Verifica se uma string está vazia (length == 0)

**Requisitos:**
- Retornar `true` se `len() == 0`
- Retornar `false` caso contrário

---

## 5. Métodos de `Vec<T>`

### 5.1 `vec.extend(iter: Iterator<T>)`

**Uso no código:**
```d
failures.extend(record_failures);  // Linha 112
```

**Descrição:**
- Adiciona todos os elementos de um iterador ao final do vetor
- Consome o iterador

**Requisitos:**
- Aceitar qualquer iterador que produza `T`
- Adicionar elementos ao final do vetor
- Pode precisar realocar se capacidade insuficiente

---

## 6. Métodos de `Option<T>`

### 6.1 `option.as_ref() -> Option<&T>`

**Uso no código:**
```d
let (record_failures, record_checks) = validate_record(&json, idx, replicon_ids.as_ref());  // Linha 109
```

**Descrição:**
- Converte `Option<T>` em `Option<&T>`
- Útil para passar `Option` por referência sem mover

**Requisitos:**
- Retornar `Some(&value)` se `Some(value)`
- Retornar `None` se `None`
- Não consumir o `Option` original

---

## 7. Trait `Into<String>` ou Conversão de `&str` para `String`

### 7.1 `.into()` para `String`

**Uso no código:**
```d
message: "Missing provenance object".into(),  // Linha 157
message: format!("Missing assembly_accession for {}", record_type),  // Linha 232
```

**Descrição:**
- Converte `&str` para `String`
- Implementado via trait `Into<String>` para `&str`

**Requisitos:**
- Trait `Into<String>` implementado para `&str`
- Método `.into()` que aloca nova `String`

---

## 8. Efeitos e Anotações

### 8.1 Efeito `with IO`

**Uso no código:**
```d
pub fn validate_knowledge_file(path: &str) -> Result<ValidationReport, IoError> with IO
pub fn main() with IO
```

**Descrição:**
- Anotação de efeito que indica que a função realiza I/O
- Necessário para o sistema de efeitos do Demetrios

**Requisitos:**
- Sistema de efeitos que rastreia I/O
- Funções que fazem I/O devem ser marcadas com `with IO`
- Funções que chamam outras com `with IO` também precisam do efeito

---

## Resumo de Prioridades

### Crítico (bloqueia compilação):
1. ✅ `JsonValue` - Tipo base para JSON
2. ✅ `parse_json()` - Parser JSON
3. ✅ `read_file()` - Leitura de arquivos
4. ✅ `IoError` - Tipo de erro para I/O
5. ✅ Métodos de `JsonValue` (`has()`, `as_str()`, `as_f64()`, `as_i64()`, `as_bool()`, indexação)

### Importante (necessário para funcionalidade completa):
6. ✅ `write_file()` - Escrita de arquivos
7. ✅ `exit()` - Encerramento do processo
8. ✅ `env::args()` - Argumentos da linha de comando
9. ✅ `min()` - Função utilitária

### Suporte (já podem existir, mas precisam verificação):
10. ✅ Métodos de `String` (`lines()`, `split()`, `trim()`, `is_empty()`)
11. ✅ Métodos de `Vec` (`extend()`)
12. ✅ Métodos de `Option` (`as_ref()`)
13. ✅ Trait `Into<String>` para `&str`

---

## Notas de Implementação

### JSON Parser
- Pode usar biblioteca externa (serde_json, simdjson) via FFI
- Ou implementar parser próprio seguindo RFC 7159
- Deve ser robusto e tratar erros graciosamente

### I/O
- Pode usar `std::fs` do Rust via FFI
- Ou implementar wrappers nativos
- Deve suportar caminhos relativos e absolutos
- Deve tratar erros do sistema operacional

### Efeitos
- Sistema de efeitos do Demetrios deve rastrear `IO`
- Funções com `with IO` não podem ser chamadas de funções sem efeito (a menos que explicitamente permitido)

---

## Status Atual (Demetrios v0.72.0)

| Funcionalidade | Status | Notas |
|----------------|--------|-------|
| `std.io` | ❌ Não implementado | Módulo não existe |
| `std.json` | ❌ Não implementado | Módulo não existe |
| `JsonValue` | ❌ Não existe | Tipo não definido |
| `read_file()` | ❌ Não existe | Função não definida |
| `write_file()` | ❌ Não existe | Função não definida |
| `parse_json()` | ❌ Não existe | Função não definida |
| `exit()` | ❌ Não existe | Função não definida |
| `env::args()` | ❌ Não existe | Função não definida |
| `min()` | ❌ Não existe | Função não definida |
| `str.lines()` | ⚠️ Verificar | Pode existir em `std.str` |
| `str.split()` | ⚠️ Verificar | Pode existir em `std.str` |
| `str.trim()` | ⚠️ Verificar | Pode existir em `std.str` |
| `str.is_empty()` | ⚠️ Verificar | Pode existir em `std.str` |

---

## Issues recentes (FFI)

- Escritas em ponteiros de saida (`*mut u8`) dentro de `extern "C"` parecem ser ignoradas pelo codegen, impedindo kernels batch de retornar resultados por buffer.
  - Issue: https://github.com/sounio-lang/sounio/issues/11
  - Status: ainda falha na cross-validation com `dc 0.78.1`; fallback por item permanece.

---

## Conclusão

O arquivo `verify_knowledge.d` é um validador completo de registros epistêmicos que requer:
- **I/O completo**: Leitura e escrita de arquivos, argumentos da linha de comando, encerramento de processo
- **JSON parsing completo**: Parser robusto com acesso tipo-seguro a valores
- **Utilitários de string**: Manipulação de strings para parsing de CSV e formatação

Essas funcionalidades são fundamentais para qualquer aplicação que processe dados estruturados (JSON, CSV) e interaja com o sistema de arquivos. A implementação dessas funcionalidades tornaria o Demetrios adequado para scripts de validação e processamento de dados além dos kernels de computação científica.

**Recomendação**: Implementar `std.io` e `std.json` como módulos prioritários para expandir os casos de uso do Demetrios além de kernels de computação numérica.
