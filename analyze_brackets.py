import re

with open('lib/features/auth/pages/login_page.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Find build() method start line
build_start = None
for i, line in enumerate(lines):
    if 'Widget build(BuildContext context)' in line:
        build_start = i
        break
print(f'build() starts at line {build_start + 1}, total lines: {len(lines)}')

# Scan from build_start to end, track bracket balance
stack = []
types_open = {'(': 'paren', '[': 'bracket', '{': 'brace'}
types_close = {')': 'paren', ']': 'bracket', '}': 'brace'}

i = build_start
for i, line in enumerate(lines[build_start:], start=build_start):
    stripped = line.rstrip()
    # Skip string literals and comments roughly
    in_str = False
    str_ch = None
    skip_line = False
    
    for ch in stripped:
        if not in_str and ch in ('"', "'"):
            in_str = True
            str_ch = ch
        elif in_str and ch == str_ch and (len(stripped) == 1 or stripped.index(ch) == stripped.rfind(ch)):
            in_str = False
            str_ch = None
        elif in_str:
            continue
        
        if ch in types_open:
            stack.append((ch, i+1))
        elif ch in types_close:
            if stack:
                stack.pop()

print(f'Unmatched opens remaining: {len(stack)}')
for item in stack:
    print(f'  line {item[1]}: unmatched {item[0]}')

# Also check before build()
stack2 = []
for i, line in enumerate(lines[:build_start]):
    stripped = line.rstrip()
    in_str = False
    str_ch = None
    for ch in stripped:
        if not in_str and ch in ('"', "'"):
            in_str = True
            str_ch = ch
        elif in_str and ch == str_ch:
            in_str = False
            str_ch = None
        elif in_str:
            continue
        if ch in types_open:
            stack2.append((ch, i+1))
        elif ch in types_close:
            if stack2:
                stack2.pop()

print(f'Before build(), unmatched: {len(stack2)}')
for item in stack2[-10:]:
    print(f'  line {item[1]}: unmatched {item[0]}')
