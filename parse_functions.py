import json

with open('functions.json', 'r', encoding='utf-8') as f:
    functions = json.load(f)

for func in functions:
    filename = f"supabase/{func['filename']}"
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(func['content'])
    print(f"Created: {filename}")

print(f"\nTotal: {len(functions)} files created")