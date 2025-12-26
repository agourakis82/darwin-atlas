import sys
import re

content = open(sys.argv[1]).read()

# Find all extern "C" blocks inside functions
# This is a bit tricky with regex but let's try a simple approach
# We want to find:
#    extern "C" {
#        fn some_fn(...);
#    }

extern_blocks = re.findall(r'(\s+extern "C" \{\s+fn [^;]+;\s+\})', content)

# Remove them from their locations
new_content = content
for block in extern_blocks:
    new_content = new_content.replace(block, "")

# Find the location of the first pub fn or impl
first_item = re.search(r'^(pub )?(fn|enum|struct|impl|type|let|var)', new_content, re.MULTILINE)
if first_item:
    pos = first_item.start()
    # Add all collected blocks at the top (deduplicated)
    unique_blocks = list(set(extern_blocks))
    header = "\n".join([b.strip() for b in unique_blocks]) + "\n\n"
    new_content = new_content[:pos] + header + new_content[pos:]
else:
    # Just append at the end if no items found
    new_content += "\n" + "\n".join([b.strip() for b in extern_blocks])

with open(sys.argv[1], 'w') as f:
    f.write(new_content)
