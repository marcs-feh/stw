from dataclasses import dataclass

PARAGRAPH = 'paragraph'
HEADING = 'heading'
CODE = 'code'
LINE_BREAK = 'line_break'
LIST_ITEM = 'list_item'
# CITATION = 'citation'

@dataclass
class Block:
    kind : str = PARAGRAPH
    data : str = ''
    level : int = 0
    language : str | None = None
    ordered_list : bool = False

    def __repr__(self):
        if self.kind == HEADING:
            return f'{self.kind}({self.level}): {self.data}'
        elif self.kind == CODE:
            return f'{self.kind}({self.language}): {self.data}'
        else:
            return f'{self.kind}: {self.data}'

def consume_code_lines(lines: list[str], start: int) -> list[str]:
    code = []
    for line in lines[start:]:
        if line.startswith('```'):
            break
        code.append(line)
    return code

def parse_heading(line: str):
    n = 0
    for c in line:
        if c != '=': break
        n += 1
    return Block(HEADING, line[n:].strip(), n)

def parse_list_item(lines: list[str], start: int):
    pass

def makeblock(lines):
    blocks = []
    i = 0

    while i < len(lines):
        line = lines[i].rstrip()
        if len(line) == 0:
            blocks.append(Block(LINE_BREAK))
        elif line.startswith('='):
            blocks.append(parse_heading(line))
        elif line.startswith('```'):
            language = line.lstrip('```')
            code_lines = consume_code_lines(lines, i + 1)
            blocks.append(Block(CODE, ''.join(code_lines), language=language))
            i = i + len(code_lines) + 2
            continue
        elif line.strip().startswith('+'):
            pass
        else:
            blocks.append(Block(PARAGRAPH, line))

        i += 1

    return blocks

with open('example.txt', 'r') as f:
    data = f.readlines()

blocks = makeblock(data)
for block in blocks:
    print(block)
